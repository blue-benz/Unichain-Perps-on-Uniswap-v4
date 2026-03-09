// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {CollateralVault} from "../../src/CollateralVault.sol";
import {RiskManager} from "../../src/RiskManager.sol";
import {PerpsEngine} from "../../src/PerpsEngine.sol";
import {LiquidationModule} from "../../src/LiquidationModule.sol";
import {IRiskManager} from "../../src/interfaces/IRiskManager.sol";

abstract contract PerpsFixture is Test {
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    address internal constant TRADER = address(0xA11CE);
    address internal constant TRADER_TWO = address(0xB0B);
    address internal constant LIQUIDATOR = address(0xC0FFEE);

    MockERC20 internal collateral;
    CollateralVault internal vault;
    RiskManager internal riskManager;
    PerpsEngine internal engine;
    LiquidationModule internal liquidation;

    PoolKey internal unitTestPoolKey;
    bytes32 internal unitTestMarketId;

    function _deployCore() internal {
        collateral = new MockERC20("Mock USD", "mUSD", 18);

        riskManager = new RiskManager(address(this));
        vault = new CollateralVault(address(collateral), address(this));
        engine = new PerpsEngine(address(vault), address(riskManager), address(this));
        liquidation = new LiquidationModule(address(engine), address(this));

        vault.setEngine(address(engine));
        engine.setLiquidationModule(address(liquidation));
        engine.setHook(address(this));

        unitTestPoolKey = PoolKey({
            currency0: Currency.wrap(address(0x1000000000000000000000000000000000000001)),
            currency1: Currency.wrap(address(0x2000000000000000000000000000000000000002)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0x1234))
        });

        unitTestMarketId = engine.marketIdFromPoolKey(unitTestPoolKey);

        riskManager.setRiskParams(
            unitTestMarketId,
            IRiskManager.RiskParams({
                initialMarginBps: 1_000,
                maintenanceMarginBps: 500,
                liquidationPenaltyBps: 400,
                liquidationIncentiveBps: 200,
                maxLeverageBps: 100_000,
                maxPremiumBps: 300
            })
        );

        engine.createMarket(unitTestPoolKey, 1e18, 1 hours, 1e17, 5_000_000e18);

        collateral.mint(address(this), 2_000_000e18);
        collateral.approve(address(vault), type(uint256).max);
        vault.depositInsurance(1_000_000e18);

        collateral.mint(TRADER, 250_000e18);
        collateral.mint(TRADER_TWO, 250_000e18);
        vm.prank(TRADER);
        collateral.approve(address(vault), type(uint256).max);

        vm.prank(TRADER_TWO);
        collateral.approve(address(vault), type(uint256).max);
    }

    function _captureMarkFromHook(PoolKey memory key, uint160 sqrtPriceX96) internal {
        engine.captureMarkPriceFromHook(key, sqrtPriceX96, 0);
    }

    function _sqrtPriceFromRatio(uint256 numerator, uint256 denominator) internal pure returns (uint160) {
        return uint160((uint256(SQRT_PRICE_1_1) * numerator) / denominator);
    }
}
