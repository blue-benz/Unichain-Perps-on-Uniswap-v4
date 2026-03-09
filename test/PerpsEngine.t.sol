// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PerpsFixture} from "./helpers/PerpsFixture.sol";
import {PerpsEngine} from "../src/PerpsEngine.sol";
import {RiskManager} from "../src/RiskManager.sol";

contract PerpsEngineUnitTest is PerpsFixture {
    function setUp() public {
        _deployCore();
    }

    function test_openPosition_revertsWhenUndercollateralized() public {
        vm.startPrank(TRADER);
        engine.depositCollateral(50e18);

        vm.expectRevert(RiskManager.InitialMarginTooLow.selector);
        engine.openPosition(unitTestMarketId, true, 1_000e18, 50e18);
        vm.stopPrank();
    }

    function test_openIncreaseAndPartialCloseFlow() public {
        vm.startPrank(TRADER);
        engine.depositCollateral(500e18);
        engine.openPosition(unitTestMarketId, true, 1_000e18, 200e18);

        engine.modifyPosition(unitTestMarketId, int256(500e18));
        vm.stopPrank();

        _captureMarkFromHook(unitTestPoolKey, _sqrtPriceFromRatio(12, 10)); // 1.44x spot

        vm.prank(TRADER);
        engine.closePosition(unitTestMarketId, 800e18);

        PerpsEngine.PositionSnapshot memory snapshot = engine.getPosition(unitTestMarketId, TRADER);
        assertEq(snapshot.sizeUsdX18, int256(700e18));
        assertEq(snapshot.entryPriceX18, 1e18);
    }

    function test_fundingWindowBoundaryAccrual() public {
        vm.prank(TRADER);
        engine.depositCollateral(300e18);

        vm.prank(TRADER);
        engine.openPosition(unitTestMarketId, true, 1_000e18, 200e18);

        engine.setIndexPrice(unitTestMarketId, 1e18);
        _captureMarkFromHook(unitTestPoolKey, _sqrtPriceFromRatio(11, 10));

        vm.warp(block.timestamp + 59 minutes);
        engine.updateFunding(unitTestMarketId);
        PerpsEngine.MarketSnapshot memory beforeWindow = engine.getMarket(unitTestMarketId);
        assertEq(beforeWindow.cumulativeFundingRateX18, 0);

        vm.warp(block.timestamp + 1 minutes);
        engine.updateFunding(unitTestMarketId);
        PerpsEngine.MarketSnapshot memory afterWindow = engine.getMarket(unitTestMarketId);
        assertGt(afterWindow.cumulativeFundingRateX18, 0);
    }

    function test_liquidationBoundaryAndExecution() public {
        vm.prank(TRADER);
        engine.depositCollateral(150e18);

        vm.prank(TRADER);
        engine.openPosition(unitTestMarketId, true, 1_000e18, 100e18);

        // ~ -4.94% move => equity stays above maintenance threshold.
        _captureMarkFromHook(unitTestPoolKey, _sqrtPriceFromRatio(975, 1000));

        vm.prank(LIQUIDATOR);
        vm.expectRevert(PerpsEngine.PositionStillHealthy.selector);
        liquidation.liquidate(TRADER, unitTestMarketId);

        // push below maintenance
        _captureMarkFromHook(unitTestPoolKey, _sqrtPriceFromRatio(97, 100));

        vm.prank(LIQUIDATOR);
        liquidation.liquidate(TRADER, unitTestMarketId);

        PerpsEngine.PositionSnapshot memory snapshot = engine.getPosition(unitTestMarketId, TRADER);
        assertEq(snapshot.sizeUsdX18, 0);
    }

    function test_badDebtPathTrackedOnLargeMove() public {
        vm.prank(TRADER);
        engine.depositCollateral(120e18);

        vm.prank(TRADER);
        engine.openPosition(unitTestMarketId, true, 1_000e18, 100e18);

        // 70% down -> large loss and bad debt path.
        _captureMarkFromHook(unitTestPoolKey, _sqrtPriceFromRatio(30, 100));

        vm.prank(LIQUIDATOR);
        liquidation.liquidate(TRADER, unitTestMarketId);

        PerpsEngine.MarketSnapshot memory market = engine.getMarket(unitTestMarketId);
        assertGt(market.badDebtUsdX18, 0);
    }

    function test_tinyPositionAndDustRounding() public {
        vm.prank(TRADER);
        engine.depositCollateral(1e12);

        vm.prank(TRADER);
        engine.openPosition(unitTestMarketId, false, 2e12, 1e12);

        vm.prank(TRADER);
        engine.closePosition(unitTestMarketId, 1e12);

        PerpsEngine.PositionSnapshot memory snapshot = engine.getPosition(unitTestMarketId, TRADER);
        assertEq(snapshot.sizeUsdX18, -int256(1e12));
    }

    function test_unauthorizedHookCaptureReverts() public {
        engine.setHook(address(0x1111));

        vm.expectRevert(PerpsEngine.UnauthorizedHook.selector);
        engine.captureMarkPriceFromHook(unitTestPoolKey, SQRT_PRICE_1_1, 0);
    }
}
