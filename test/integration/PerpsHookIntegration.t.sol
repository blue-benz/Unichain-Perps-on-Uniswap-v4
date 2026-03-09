// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";

import {EasyPosm} from "../utils/libraries/EasyPosm.sol";
import {BaseTest} from "../utils/BaseTest.sol";

import {PerpsHook} from "../../src/PerpsHook.sol";
import {PerpsEngine} from "../../src/PerpsEngine.sol";
import {RiskManager} from "../../src/RiskManager.sol";
import {CollateralVault} from "../../src/CollateralVault.sol";
import {LiquidationModule} from "../../src/LiquidationModule.sol";
import {IRiskManager} from "../../src/interfaces/IRiskManager.sol";

contract PerpsHookIntegrationTest is BaseTest {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);

    Currency currency0;
    Currency currency1;

    PoolKey poolKey;
    PoolId poolId;

    MockERC20 collateral;
    RiskManager riskManager;
    CollateralVault vault;
    PerpsEngine engine;
    LiquidationModule liquidationModule;
    PerpsHook hook;

    bytes32 marketId;

    function setUp() public {
        deployArtifactsAndLabel();

        (currency0, currency1) = deployCurrencyPair();

        collateral = new MockERC20("Collateral", "COL", 18);
        riskManager = new RiskManager(address(this));
        vault = new CollateralVault(address(collateral), address(this));
        engine = new PerpsEngine(address(vault), address(riskManager), address(this));
        liquidationModule = new LiquidationModule(address(engine), address(this));

        vault.setEngine(address(engine));
        engine.setLiquidationModule(address(liquidationModule));

        address flags = address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) ^ (0x8888 << 144));
        bytes memory constructorArgs = abi.encode(poolManager, address(engine), address(this));
        deployCodeTo("PerpsHook.sol:PerpsHook", constructorArgs, flags);
        hook = PerpsHook(flags);

        engine.setHook(address(hook));

        poolKey = PoolKey(currency0, currency1, 3_000, 60, IHooks(hook));
        poolId = poolKey.toId();

        marketId = engine.marketIdFromPoolKey(poolKey);

        riskManager.setRiskParams(
            marketId,
            IRiskManager.RiskParams({
                initialMarginBps: 1_000,
                maintenanceMarginBps: 500,
                liquidationPenaltyBps: 400,
                liquidationIncentiveBps: 200,
                maxLeverageBps: 100_000,
                maxPremiumBps: 300
            })
        );

        engine.createMarket(poolKey, 1e18, 1 hours, 1e17, 10_000_000e18);

        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        int24 tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        int24 tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);

        uint128 liquidityAmount = 200e18;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        positionManager.mint(
            poolKey,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            Constants.ZERO_BYTES
        );

        collateral.mint(address(this), 1_000_000e18);
        collateral.approve(address(vault), type(uint256).max);
        vault.depositInsurance(500_000e18);

        collateral.mint(ALICE, 10_000e18);
        collateral.mint(BOB, 10_000e18);

        vm.prank(ALICE);
        collateral.approve(address(vault), type(uint256).max);

        vm.prank(BOB);
        collateral.approve(address(vault), type(uint256).max);
    }

    function test_swapUpdatesMarkPriceViaHookAndSupportsLongShortLifecycle() public {
        vm.prank(ALICE);
        engine.depositCollateral(1_000e18);
        vm.prank(BOB);
        engine.depositCollateral(1_000e18);

        vm.prank(ALICE);
        engine.openPosition(marketId, true, 2_000e18, 500e18);

        vm.prank(BOB);
        engine.openPosition(marketId, false, 1_500e18, 500e18);

        uint256 markBefore = engine.getMarket(marketId).markPriceX18;

        swapRouter.swapExactTokensForTokens({
            amountIn: 20e18,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });

        uint256 markAfter = engine.getMarket(marketId).markPriceX18;
        assertGt(markAfter, 0);
        assertTrue(markAfter != markBefore);

        vm.warp(block.timestamp + 1 hours);
        engine.updateFunding(marketId);

        vm.prank(ALICE);
        engine.closePosition(marketId, 1_000e18);

        PerpsEngine.PositionSnapshot memory alice = engine.getPosition(marketId, ALICE);
        PerpsEngine.PositionSnapshot memory bob = engine.getPosition(marketId, BOB);

        assertEq(alice.sizeUsdX18, int256(1_000e18));
        assertEq(bob.sizeUsdX18, -int256(1_500e18));

        int24 observedTick = hook.lastObservedTick(PoolId.unwrap(poolId));
        assertTrue(observedTick != 0 || markAfter != 1e18);
    }
}
