// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PerpsFixture} from "./helpers/PerpsFixture.sol";
import {PerpsEngine} from "../src/PerpsEngine.sol";
import {RiskManager} from "../src/RiskManager.sol";
import {CollateralVault} from "../src/CollateralVault.sol";
import {LiquidationModule} from "../src/LiquidationModule.sol";
import {IRiskManager} from "../src/interfaces/IRiskManager.sol";

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

    function test_withdrawCollateralAndVaultTokenView() public {
        assertEq(vault.collateralToken(), address(collateral));

        vm.prank(TRADER);
        engine.depositCollateral(100e18);

        vm.prank(TRADER);
        engine.withdrawCollateral(40e18);
        assertEq(vault.freeBalance(TRADER), 60e18);

        vm.prank(TRADER);
        vm.expectRevert(CollateralVault.InsufficientFreeCollateral.selector);
        engine.withdrawCollateral(61e18);
    }

    function test_addAndRemoveMarginPaths() public {
        vm.prank(TRADER);
        engine.depositCollateral(700e18);
        vm.prank(TRADER);
        engine.openPosition(unitTestMarketId, true, 1_000e18, 200e18);

        vm.prank(TRADER);
        engine.addMargin(unitTestMarketId, 50e18);
        vm.prank(TRADER);
        engine.removeMargin(unitTestMarketId, 25e18);

        PerpsEngine.PositionSnapshot memory snapshot = engine.getPosition(unitTestMarketId, TRADER);
        assertEq(snapshot.collateralUsdX18, 225e18);

        vm.prank(TRADER);
        vm.expectRevert(PerpsEngine.InsufficientPositionCollateral.selector);
        engine.removeMargin(unitTestMarketId, 226e18);
    }

    function test_openPosition_revertsOnDirectionMismatch() public {
        vm.prank(TRADER);
        engine.depositCollateral(500e18);
        vm.prank(TRADER);
        engine.openPosition(unitTestMarketId, true, 1_000e18, 200e18);

        vm.prank(TRADER);
        vm.expectRevert(PerpsEngine.DirectionMismatch.selector);
        engine.openPosition(unitTestMarketId, false, 100e18, 0);
    }

    function test_modifyPosition_reducePathAndFlipRevert() public {
        vm.prank(TRADER);
        engine.depositCollateral(700e18);
        vm.prank(TRADER);
        engine.openPosition(unitTestMarketId, true, 1_000e18, 200e18);

        vm.prank(TRADER);
        engine.modifyPosition(unitTestMarketId, -int256(400e18));
        assertEq(engine.getPosition(unitTestMarketId, TRADER).sizeUsdX18, int256(600e18));

        vm.prank(TRADER);
        vm.expectRevert(PerpsEngine.FlipNotSupported.selector);
        engine.modifyPosition(unitTestMarketId, -int256(700e18));
    }

    function test_positionViewsIncludeProjectedFunding() public {
        vm.prank(TRADER);
        engine.depositCollateral(500e18);
        vm.prank(TRADER);
        engine.openPosition(unitTestMarketId, true, 1_000e18, 200e18);

        engine.setIndexPrice(unitTestMarketId, 1e18);
        _captureMarkFromHook(unitTestPoolKey, _sqrtPriceFromRatio(110, 100));

        vm.warp(block.timestamp + 1 hours);
        int256 pnl = engine.unrealizedPnlUsdX18(unitTestMarketId, TRADER);
        int256 equity = engine.positionEquityUsdX18(unitTestMarketId, TRADER);

        assertGt(pnl, 0);
        assertGt(equity, 0);
    }

    function test_fundingSettlementPositiveAndNegativePaths() public {
        vm.prank(TRADER);
        engine.depositCollateral(500e18);
        vm.prank(TRADER);
        engine.openPosition(unitTestMarketId, true, 1_000e18, 100e18);

        vm.prank(TRADER_TWO);
        engine.depositCollateral(500e18);
        vm.prank(TRADER_TWO);
        engine.openPosition(unitTestMarketId, false, 1_000e18, 200e18);

        engine.setIndexPrice(unitTestMarketId, 1e18);
        _captureMarkFromHook(unitTestPoolKey, _sqrtPriceFromRatio(130, 100));
        vm.warp(block.timestamp + 40 hours);
        engine.updateFunding(unitTestMarketId);

        uint256 badDebtBefore = engine.getMarket(unitTestMarketId).badDebtUsdX18;
        vm.prank(TRADER);
        engine.addMargin(unitTestMarketId, 1e18);
        uint256 badDebtAfter = engine.getMarket(unitTestMarketId).badDebtUsdX18;
        assertGt(badDebtAfter, badDebtBefore);

        uint256 shortCollateralBefore = engine.getPosition(unitTestMarketId, TRADER_TWO).collateralUsdX18;
        vm.prank(TRADER_TWO);
        engine.addMargin(unitTestMarketId, 1e18);
        uint256 shortCollateralAfter = engine.getPosition(unitTestMarketId, TRADER_TWO).collateralUsdX18;
        assertGt(shortCollateralAfter, shortCollateralBefore);
    }

    function test_riskManagerRequiredMarginAndInvalidParams() public {
        assertEq(riskManager.initialMarginRequired(unitTestMarketId, 1_000e18), 100e18);

        vm.expectRevert(RiskManager.InvalidRiskParameter.selector);
        riskManager.setRiskParams(
            unitTestMarketId,
            IRiskManager.RiskParams({
                initialMarginBps: 800,
                maintenanceMarginBps: 900,
                liquidationPenaltyBps: 100,
                liquidationIncentiveBps: 100,
                maxLeverageBps: 100_000,
                maxPremiumBps: 300
            })
        );
    }

    function test_withdrawInsuranceRevertsAndSucceeds() public {
        vm.expectRevert(CollateralVault.InsufficientInsurance.selector);
        vault.withdrawInsurance(address(this), 2_000_000e18);

        uint256 balanceBefore = collateral.balanceOf(address(this));
        vault.withdrawInsurance(address(this), 100e18);
        assertEq(collateral.balanceOf(address(this)) - balanceBefore, 100e18);
    }

    function test_liquidationModuleConstructorRevertsOnZeroEngine() public {
        vm.expectRevert(LiquidationModule.ZeroAddress.selector);
        new LiquidationModule(address(0), address(this));
    }

    function test_createMarketRevertsWhenMarketAlreadyExists() public {
        vm.expectRevert(PerpsEngine.MarketExists.selector);
        engine.createMarket(unitTestPoolKey, 1e18, 1 hours, 1e17, 1_000_000e18);
    }

    function test_closePositionFullResetsEntryAndSize() public {
        vm.prank(TRADER);
        engine.depositCollateral(600e18);
        vm.prank(TRADER);
        engine.openPosition(unitTestMarketId, true, 1_000e18, 200e18);

        vm.prank(TRADER);
        engine.closePosition(unitTestMarketId, 1_000e18);

        PerpsEngine.PositionSnapshot memory snapshot = engine.getPosition(unitTestMarketId, TRADER);
        assertEq(snapshot.sizeUsdX18, 0);
        assertEq(snapshot.entryPriceX18, 0);
    }

    function test_partialCloseCanHitExtraLossPathBeforeMaintenanceRevert() public {
        vm.prank(TRADER);
        engine.depositCollateral(700e18);
        vm.prank(TRADER);
        engine.openPosition(unitTestMarketId, true, 1_000e18, 200e18);

        // ~0.75x price level to force realized loss > collateralPortion on a half close.
        _captureMarkFromHook(unitTestPoolKey, _sqrtPriceFromRatio(866, 1000));

        vm.prank(TRADER);
        vm.expectRevert(RiskManager.MaintenanceMarginTooLow.selector);
        engine.closePosition(unitTestMarketId, 500e18);
    }
}
