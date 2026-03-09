// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";

import {IPerpsEngine} from "./interfaces/IPerpsEngine.sol";
import {ICollateralVault} from "./interfaces/ICollateralVault.sol";
import {IRiskManager} from "./interfaces/IRiskManager.sol";
import {PerpsMath} from "./libraries/PerpsMath.sol";

contract PerpsEngine is IPerpsEngine, Ownable, ReentrancyGuard {
    using PoolIdLibrary for PoolKey;

    uint256 internal constant ONE = 1e18;

    error ZeroAddress();
    error UnauthorizedHook();
    error UnauthorizedLiquidationModule();
    error InvalidAmount();
    error InvalidPrice();
    error MarketExists();
    error MarketNotFound();
    error PositionNotFound();
    error DirectionMismatch();
    error FlipNotSupported();
    error PositionStillHealthy();
    error NotionalCapExceeded();
    error InsufficientPositionCollateral();

    struct Position {
        int256 sizeUsdX18;
        uint256 collateralUsdX18;
        uint256 entryPriceX18;
        int256 lastCumulativeFundingRateX18;
    }

    struct Market {
        bool exists;
        PoolKey poolKey;
        bytes32 poolId;
        uint256 markPriceX18;
        uint256 indexPriceX18;
        int256 cumulativeFundingRateX18;
        uint256 fundingInterval;
        uint256 lastFundingTimestamp;
        int256 fundingVelocityX18;
        uint256 maxOpenNotionalUsdX18;
        uint256 totalOpenNotionalUsdX18;
        uint256 badDebtUsdX18;
    }

    ICollateralVault public immutable vault;
    IRiskManager public immutable riskManager;

    address public hook;
    address public liquidationModule;

    mapping(bytes32 marketId => Market market) internal markets;
    mapping(bytes32 marketId => mapping(address trader => Position position)) internal positions;

    event HookSet(address indexed hook);
    event LiquidationModuleSet(address indexed module);
    event MarketCreated(bytes32 indexed marketId, bytes32 indexed poolId, uint256 priceX18);
    event MarkPriceCaptured(bytes32 indexed marketId, uint256 markPriceX18, int24 tick);
    event IndexPriceUpdated(bytes32 indexed marketId, uint256 indexPriceX18);
    event FundingUpdated(bytes32 indexed marketId, int256 newCumulativeFundingRateX18, uint256 windowsApplied);
    event FundingSettled(address indexed trader, bytes32 indexed marketId, int256 fundingPaymentUsdX18);
    event MarginAdded(address indexed trader, bytes32 indexed marketId, uint256 amount);
    event MarginRemoved(address indexed trader, bytes32 indexed marketId, uint256 amount);
    event PositionOpened(address indexed trader, bytes32 indexed marketId, int256 sizeUsdX18, uint256 entryPriceX18);
    event PositionModified(address indexed trader, bytes32 indexed marketId, int256 newSizeUsdX18, uint256 entryPriceX18);
    event PositionClosed(address indexed trader, bytes32 indexed marketId, uint256 reducedNotionalUsdX18, int256 realizedPnlUsdX18);
    event PositionLiquidated(
        address indexed trader,
        address indexed liquidator,
        bytes32 indexed marketId,
        int256 equityUsdX18,
        uint256 badDebtDeltaUsdX18
    );

    constructor(address vault_, address riskManager_, address initialOwner) Ownable(initialOwner) {
        if (vault_ == address(0) || riskManager_ == address(0)) revert ZeroAddress();

        vault = ICollateralVault(vault_);
        riskManager = IRiskManager(riskManager_);
    }

    function setHook(address hook_) external onlyOwner {
        if (hook_ == address(0)) revert ZeroAddress();
        hook = hook_;
        emit HookSet(hook_);
    }

    function setLiquidationModule(address module_) external onlyOwner {
        if (module_ == address(0)) revert ZeroAddress();
        liquidationModule = module_;
        emit LiquidationModuleSet(module_);
    }

    function createMarket(
        PoolKey calldata key,
        uint256 initialPriceX18,
        uint256 fundingInterval,
        int256 fundingVelocityX18,
        uint256 maxOpenNotionalUsdX18
    ) external override onlyOwner returns (bytes32 marketId) {
        if (initialPriceX18 == 0 || fundingInterval == 0 || maxOpenNotionalUsdX18 == 0) revert InvalidAmount();

        marketId = marketIdFromPoolKey(key);
        if (markets[marketId].exists) revert MarketExists();

        IRiskManager.RiskParams memory params = riskManager.getRiskParams(marketId);
        if (params.maxLeverageBps == 0) revert InvalidAmount();

        markets[marketId] = Market({
            exists: true,
            poolKey: key,
            poolId: PoolId.unwrap(PoolIdLibrary.toId(key)),
            markPriceX18: initialPriceX18,
            indexPriceX18: initialPriceX18,
            cumulativeFundingRateX18: 0,
            fundingInterval: fundingInterval,
            lastFundingTimestamp: block.timestamp,
            fundingVelocityX18: fundingVelocityX18,
            maxOpenNotionalUsdX18: maxOpenNotionalUsdX18,
            totalOpenNotionalUsdX18: 0,
            badDebtUsdX18: 0
        });

        emit MarketCreated(marketId, PoolId.unwrap(PoolIdLibrary.toId(key)), initialPriceX18);
    }

    function marketIdFromPoolKey(PoolKey calldata key) public pure override returns (bytes32) {
        return PoolId.unwrap(PoolIdLibrary.toId(key));
    }

    function captureMarkPriceFromHook(PoolKey calldata key, uint160 sqrtPriceX96, int24 tick) external override {
        if (msg.sender != hook) revert UnauthorizedHook();

        bytes32 marketId = marketIdFromPoolKey(key);
        Market storage market = _market(marketId);

        uint256 markPriceX18 = PerpsMath.toPriceX18FromSqrtPriceX96(sqrtPriceX96);
        if (markPriceX18 == 0) revert InvalidPrice();

        market.markPriceX18 = markPriceX18;
        emit MarkPriceCaptured(marketId, markPriceX18, tick);
    }

    function updateFunding(bytes32 marketId) external override {
        _updateFunding(marketId, _market(marketId));
    }

    function setIndexPrice(bytes32 marketId, uint256 indexPriceX18) external override onlyOwner {
        if (indexPriceX18 == 0) revert InvalidPrice();

        Market storage market = _market(marketId);
        market.indexPriceX18 = indexPriceX18;

        emit IndexPriceUpdated(marketId, indexPriceX18);
    }

    function depositCollateral(uint256 amount) external override nonReentrant {
        if (amount == 0) revert InvalidAmount();
        vault.depositFor(msg.sender, amount);
    }

    function withdrawCollateral(uint256 amount) external override nonReentrant {
        if (amount == 0) revert InvalidAmount();
        vault.withdrawTo(msg.sender, amount);
    }

    function addMargin(bytes32 marketId, uint256 amount) public override nonReentrant {
        if (amount == 0) revert InvalidAmount();

        Market storage market = _market(marketId);
        Position storage position = positions[marketId][msg.sender];

        _updateFunding(marketId, market);
        _settleFunding(marketId, market, position, msg.sender);

        vault.lockCollateral(msg.sender, amount);
        position.collateralUsdX18 += amount;

        emit MarginAdded(msg.sender, marketId, amount);
    }

    function removeMargin(bytes32 marketId, uint256 amount) external override nonReentrant {
        if (amount == 0) revert InvalidAmount();

        Market storage market = _market(marketId);
        Position storage position = positions[marketId][msg.sender];
        if (position.collateralUsdX18 < amount) revert InsufficientPositionCollateral();

        _updateFunding(marketId, market);
        _settleFunding(marketId, market, position, msg.sender);

        position.collateralUsdX18 -= amount;
        if (position.sizeUsdX18 != 0) {
            _validateMaintenance(marketId, market, position);
        }

        vault.unlockCollateral(msg.sender, amount);
        emit MarginRemoved(msg.sender, marketId, amount);
    }

    function openPosition(bytes32 marketId, bool isLong, uint256 notionalUsdX18, uint256 marginUsdX18)
        external
        override
        nonReentrant
    {
        if (notionalUsdX18 == 0) revert InvalidAmount();

        Market storage market = _market(marketId);
        Position storage position = positions[marketId][msg.sender];

        _updateFunding(marketId, market);
        _settleFunding(marketId, market, position, msg.sender);

        if (marginUsdX18 > 0) {
            vault.lockCollateral(msg.sender, marginUsdX18);
            position.collateralUsdX18 += marginUsdX18;
            emit MarginAdded(msg.sender, marketId, marginUsdX18);
        }

        int256 signedDelta = isLong ? int256(notionalUsdX18) : -int256(notionalUsdX18);
        if (position.sizeUsdX18 != 0 && !_sameDirection(position.sizeUsdX18, signedDelta)) {
            revert DirectionMismatch();
        }

        _increasePosition(marketId, market, position, msg.sender, signedDelta);
        emit PositionOpened(msg.sender, marketId, position.sizeUsdX18, position.entryPriceX18);
    }

    function modifyPosition(bytes32 marketId, int256 sizeDeltaUsdX18) external override nonReentrant {
        if (sizeDeltaUsdX18 == 0) revert InvalidAmount();

        Market storage market = _market(marketId);
        Position storage position = positions[marketId][msg.sender];
        if (position.sizeUsdX18 == 0) revert PositionNotFound();

        _updateFunding(marketId, market);
        _settleFunding(marketId, market, position, msg.sender);

        if (_sameDirection(position.sizeUsdX18, sizeDeltaUsdX18)) {
            _increasePosition(marketId, market, position, msg.sender, sizeDeltaUsdX18);
        } else {
            uint256 reduceNotionalUsdX18 = PerpsMath.abs(sizeDeltaUsdX18);
            if (reduceNotionalUsdX18 > PerpsMath.abs(position.sizeUsdX18)) revert FlipNotSupported();
            _reducePosition(marketId, market, position, msg.sender, reduceNotionalUsdX18);
        }

        emit PositionModified(msg.sender, marketId, position.sizeUsdX18, position.entryPriceX18);
    }

    function closePosition(bytes32 marketId, uint256 reduceNotionalUsdX18) external override nonReentrant {
        if (reduceNotionalUsdX18 == 0) revert InvalidAmount();

        Market storage market = _market(marketId);
        Position storage position = positions[marketId][msg.sender];
        if (position.sizeUsdX18 == 0) revert PositionNotFound();

        _updateFunding(marketId, market);
        _settleFunding(marketId, market, position, msg.sender);

        _reducePosition(marketId, market, position, msg.sender, reduceNotionalUsdX18);
    }

    function liquidatePosition(address trader, bytes32 marketId, address liquidator) external override nonReentrant {
        if (msg.sender != liquidationModule) revert UnauthorizedLiquidationModule();

        Market storage market = _market(marketId);
        Position storage position = positions[marketId][trader];
        if (position.sizeUsdX18 == 0) revert PositionNotFound();

        _updateFunding(marketId, market);
        _settleFunding(marketId, market, position, trader);

        int256 equity = int256(position.collateralUsdX18) + _unrealizedPnl(position, market);
        uint256 notional = PerpsMath.notionalFromSize(position.sizeUsdX18);
        uint256 maintenance = riskManager.maintenanceMarginRequired(marketId, notional);
        if (equity >= int256(maintenance)) revert PositionStillHealthy();

        uint256 collateral = position.collateralUsdX18;
        int256 netEquity = int256(collateral) + _unrealizedPnl(position, market);

        market.totalOpenNotionalUsdX18 -= notional;

        position.sizeUsdX18 = 0;
        position.collateralUsdX18 = 0;
        position.entryPriceX18 = 0;
        position.lastCumulativeFundingRateX18 = market.cumulativeFundingRateX18;

        if (collateral > 0) {
            vault.transferLockedToInsurance(trader, collateral);
        }

        uint256 badDebtDelta;
        if (netEquity > 0) {
            _distributePositiveLiquidationEquity(trader, liquidator, uint256(netEquity), marketId);
        } else if (netEquity < 0) {
            badDebtDelta = uint256(-netEquity);
            market.badDebtUsdX18 += badDebtDelta;
        }

        emit PositionLiquidated(trader, liquidator, marketId, netEquity, badDebtDelta);
    }

    function getMarket(bytes32 marketId) external view override returns (MarketSnapshot memory snapshot) {
        Market storage market = _market(marketId);
        snapshot = MarketSnapshot({
            exists: market.exists,
            marketId: marketId,
            poolId: market.poolId,
            markPriceX18: market.markPriceX18,
            indexPriceX18: market.indexPriceX18,
            cumulativeFundingRateX18: market.cumulativeFundingRateX18,
            fundingInterval: market.fundingInterval,
            lastFundingTimestamp: market.lastFundingTimestamp,
            fundingVelocityX18: market.fundingVelocityX18,
            maxOpenNotionalUsdX18: market.maxOpenNotionalUsdX18,
            totalOpenNotionalUsdX18: market.totalOpenNotionalUsdX18,
            badDebtUsdX18: market.badDebtUsdX18
        });
    }

    function getPosition(bytes32 marketId, address trader) external view override returns (PositionSnapshot memory snapshot) {
        Position storage position = positions[marketId][trader];
        snapshot = PositionSnapshot({
            sizeUsdX18: position.sizeUsdX18,
            collateralUsdX18: position.collateralUsdX18,
            entryPriceX18: position.entryPriceX18,
            lastCumulativeFundingRateX18: position.lastCumulativeFundingRateX18
        });
    }

    function positionEquityUsdX18(bytes32 marketId, address trader) external view override returns (int256 equityUsdX18) {
        Market storage market = _market(marketId);
        Position storage position = positions[marketId][trader];

        int256 projectedCumulative = _projectedCumulativeFundingRate(marketId, market);
        int256 pendingFunding = _pendingFunding(position, projectedCumulative);
        int256 pnl = _unrealizedPnl(position, market);

        equityUsdX18 = int256(position.collateralUsdX18) + pnl - pendingFunding;
    }

    function unrealizedPnlUsdX18(bytes32 marketId, address trader) external view override returns (int256 pnlUsdX18) {
        Market storage market = _market(marketId);
        Position storage position = positions[marketId][trader];
        pnlUsdX18 = _unrealizedPnl(position, market);
    }

    function _increasePosition(
        bytes32 marketId,
        Market storage market,
        Position storage position,
        address trader,
        int256 signedDeltaUsdX18
    ) internal {
        uint256 addNotional = PerpsMath.abs(signedDeltaUsdX18);
        if (addNotional == 0) revert InvalidAmount();

        uint256 oldNotional = PerpsMath.notionalFromSize(position.sizeUsdX18);
        uint256 newNotional = oldNotional + addNotional;

        uint256 projectedTotalOpen = market.totalOpenNotionalUsdX18 + addNotional;
        if (projectedTotalOpen > market.maxOpenNotionalUsdX18) revert NotionalCapExceeded();

        uint256 mark = market.markPriceX18;
        if (mark == 0) revert InvalidPrice();

        if (oldNotional == 0) {
            position.entryPriceX18 = mark;
        } else {
            position.entryPriceX18 =
                PerpsMath.weightedAveragePrice(position.entryPriceX18, oldNotional, mark, addNotional);
        }

        position.sizeUsdX18 += signedDeltaUsdX18;
        position.lastCumulativeFundingRateX18 = market.cumulativeFundingRateX18;

        riskManager.validateInitialMargin(marketId, newNotional, position.collateralUsdX18);

        market.totalOpenNotionalUsdX18 = projectedTotalOpen;

        emit PositionModified(trader, marketId, position.sizeUsdX18, position.entryPriceX18);
    }

    function _reducePosition(
        bytes32 marketId,
        Market storage market,
        Position storage position,
        address trader,
        uint256 reduceNotionalUsdX18
    ) internal {
        uint256 oldNotional = PerpsMath.notionalFromSize(position.sizeUsdX18);
        if (oldNotional == 0) revert PositionNotFound();
        if (reduceNotionalUsdX18 > oldNotional) revert FlipNotSupported();

        int256 realizedPnl = PerpsMath.signedMulDiv(
            _unrealizedPnl(position, market), int256(reduceNotionalUsdX18), int256(oldNotional)
        );

        uint256 collateralPortion = (position.collateralUsdX18 * reduceNotionalUsdX18) / oldNotional;
        if (collateralPortion > 0) {
            position.collateralUsdX18 -= collateralPortion;
        }

        if (reduceNotionalUsdX18 == oldNotional) {
            position.sizeUsdX18 = 0;
            position.entryPriceX18 = 0;
        } else if (position.sizeUsdX18 > 0) {
            position.sizeUsdX18 -= int256(reduceNotionalUsdX18);
        } else {
            position.sizeUsdX18 += int256(reduceNotionalUsdX18);
        }

        market.totalOpenNotionalUsdX18 -= reduceNotionalUsdX18;

        if (realizedPnl >= 0) {
            if (collateralPortion > 0) {
                vault.unlockCollateral(trader, collateralPortion);
            }

            uint256 profit = uint256(realizedPnl);
            if (profit > 0) {
                vault.creditFreeFromInsurance(trader, profit);
            }
        } else {
            uint256 loss = uint256(-realizedPnl);
            if (loss >= collateralPortion) {
                if (collateralPortion > 0) {
                    vault.transferLockedToInsurance(trader, collateralPortion);
                }

                uint256 extraLoss = loss - collateralPortion;
                if (extraLoss > 0) {
                    if (position.collateralUsdX18 < extraLoss) revert InsufficientPositionCollateral();
                    position.collateralUsdX18 -= extraLoss;
                    vault.transferLockedToInsurance(trader, extraLoss);
                }
            } else {
                vault.transferLockedToInsurance(trader, loss);

                uint256 unlockAmount = collateralPortion - loss;
                if (unlockAmount > 0) {
                    vault.unlockCollateral(trader, unlockAmount);
                }
            }
        }

        if (position.sizeUsdX18 != 0) {
            _validateMaintenance(marketId, market, position);
        } else if (position.collateralUsdX18 > 0) {
            uint256 refund = position.collateralUsdX18;
            position.collateralUsdX18 = 0;
            vault.unlockCollateral(trader, refund);
        }

        emit PositionClosed(trader, marketId, reduceNotionalUsdX18, realizedPnl);
    }

    function _validateMaintenance(bytes32 marketId, Market storage market, Position storage position) internal view {
        uint256 notional = PerpsMath.notionalFromSize(position.sizeUsdX18);
        int256 equity = int256(position.collateralUsdX18) + _unrealizedPnl(position, market);
        riskManager.validateMaintenanceMargin(marketId, notional, equity);
    }

    function _settleFunding(bytes32 marketId, Market storage market, Position storage position, address trader)
        internal
        returns (int256 fundingPayment)
    {
        if (position.sizeUsdX18 == 0) {
            position.lastCumulativeFundingRateX18 = market.cumulativeFundingRateX18;
            return 0;
        }

        fundingPayment = _pendingFunding(position, market.cumulativeFundingRateX18);
        position.lastCumulativeFundingRateX18 = market.cumulativeFundingRateX18;

        if (fundingPayment > 0) {
            uint256 pay = uint256(fundingPayment);
            if (pay > position.collateralUsdX18) {
                uint256 shortfall = pay - position.collateralUsdX18;
                market.badDebtUsdX18 += shortfall;
                pay = position.collateralUsdX18;
            }

            if (pay > 0) {
                position.collateralUsdX18 -= pay;
                vault.transferLockedToInsurance(trader, pay);
            }
        } else if (fundingPayment < 0) {
            uint256 credit = uint256(-fundingPayment);
            if (credit > 0) {
                vault.creditLockedFromInsurance(trader, credit);
                position.collateralUsdX18 += credit;
            }
        }

        emit FundingSettled(trader, marketId, fundingPayment);
    }

    function _updateFunding(bytes32 marketId, Market storage market) internal {
        if (!market.exists) revert MarketNotFound();

        if (market.markPriceX18 == 0 || market.indexPriceX18 == 0) revert InvalidPrice();
        if (market.fundingInterval == 0 || block.timestamp <= market.lastFundingTimestamp) return;

        uint256 elapsed = block.timestamp - market.lastFundingTimestamp;
        uint256 windows = elapsed / market.fundingInterval;
        if (windows == 0) return;

        int256 premiumX18 =
            PerpsMath.signedMulDiv(int256(market.markPriceX18) - int256(market.indexPriceX18), int256(ONE), int256(market.indexPriceX18));

        IRiskManager.RiskParams memory params = riskManager.getRiskParams(marketId);
        int256 maxPremiumX18 = int256(uint256(params.maxPremiumBps) * 1e14);
        if (premiumX18 > maxPremiumX18) premiumX18 = maxPremiumX18;
        if (premiumX18 < -maxPremiumX18) premiumX18 = -maxPremiumX18;

        int256 ratePerWindowX18 = PerpsMath.signedMulDiv(premiumX18, market.fundingVelocityX18, int256(ONE));
        int256 deltaRate = ratePerWindowX18 * int256(windows);

        market.cumulativeFundingRateX18 += deltaRate;
        market.lastFundingTimestamp += windows * market.fundingInterval;

        emit FundingUpdated(marketId, market.cumulativeFundingRateX18, windows);
    }

    function _pendingFunding(Position storage position, int256 cumulativeFundingRateX18) internal view returns (int256) {
        int256 deltaRate = cumulativeFundingRateX18 - position.lastCumulativeFundingRateX18;
        return PerpsMath.signedMulDiv(position.sizeUsdX18, deltaRate, int256(ONE));
    }

    function _distributePositiveLiquidationEquity(
        address trader,
        address liquidator,
        uint256 netEquityUsdX18,
        bytes32 marketId
    ) internal {
        IRiskManager.RiskParams memory params = riskManager.getRiskParams(marketId);

        uint256 penalty = (netEquityUsdX18 * params.liquidationPenaltyBps) / 10_000;
        uint256 incentive = (netEquityUsdX18 * params.liquidationIncentiveBps) / 10_000;

        if (penalty + incentive > netEquityUsdX18) {
            uint256 overflow = penalty + incentive - netEquityUsdX18;
            if (incentive >= overflow) {
                incentive -= overflow;
            } else {
                penalty -= (overflow - incentive);
                incentive = 0;
            }
        }

        uint256 traderRefund = netEquityUsdX18 - penalty - incentive;
        if (incentive > 0) {
            vault.creditFreeFromInsurance(liquidator, incentive);
        }
        if (traderRefund > 0) {
            vault.creditFreeFromInsurance(trader, traderRefund);
        }
    }

    function _projectedCumulativeFundingRate(bytes32 marketId, Market storage market) internal view returns (int256 projected) {
        projected = market.cumulativeFundingRateX18;
        if (market.fundingInterval == 0 || block.timestamp <= market.lastFundingTimestamp) {
            return projected;
        }

        uint256 windows = (block.timestamp - market.lastFundingTimestamp) / market.fundingInterval;
        if (windows == 0) return projected;

        int256 premiumX18 =
            PerpsMath.signedMulDiv(int256(market.markPriceX18) - int256(market.indexPriceX18), int256(ONE), int256(market.indexPriceX18));

        IRiskManager.RiskParams memory params = riskManager.getRiskParams(marketId);
        int256 maxPremiumX18 = int256(uint256(params.maxPremiumBps) * 1e14);
        if (premiumX18 > maxPremiumX18) premiumX18 = maxPremiumX18;
        if (premiumX18 < -maxPremiumX18) premiumX18 = -maxPremiumX18;

        int256 ratePerWindowX18 = PerpsMath.signedMulDiv(premiumX18, market.fundingVelocityX18, int256(ONE));
        projected += ratePerWindowX18 * int256(windows);
    }

    function _unrealizedPnl(Position storage position, Market storage market) internal view returns (int256) {
        return PerpsMath.pnlUsdX18(position.sizeUsdX18, position.entryPriceX18, market.markPriceX18);
    }

    function _market(bytes32 marketId) internal view returns (Market storage market) {
        market = markets[marketId];
        if (!market.exists) revert MarketNotFound();
    }

    function _sameDirection(int256 a, int256 b) internal pure returns (bool) {
        return (a > 0 && b > 0) || (a < 0 && b < 0);
    }
}
