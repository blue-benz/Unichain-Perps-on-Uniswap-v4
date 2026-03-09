// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PerpsFixture} from "../helpers/PerpsFixture.sol";
import {PerpsEngine} from "../../src/PerpsEngine.sol";
import {RiskManager} from "../../src/RiskManager.sol";

contract PerpsEngineFuzzTest is PerpsFixture {
    function setUp() public {
        _deployCore();
    }

    function testFuzz_openPositionMarginRules(uint96 rawNotional, uint96 rawMargin) public {
        uint256 notional = bound(uint256(rawNotional), 1e18, 10_000e18);
        uint256 margin = bound(uint256(rawMargin), 1e18, 1_500e18);

        vm.startPrank(TRADER);
        engine.depositCollateral(2_000e18);

        if (margin * 10_000 < notional * 1_000) {
            vm.expectRevert(RiskManager.InitialMarginTooLow.selector);
            engine.openPosition(unitTestMarketId, true, notional, margin);
        } else {
            engine.openPosition(unitTestMarketId, true, notional, margin);
            PerpsEngine.PositionSnapshot memory snapshot = engine.getPosition(unitTestMarketId, TRADER);
            assertEq(snapshot.collateralUsdX18, margin);
        }

        vm.stopPrank();
    }

    function testFuzz_fundingAccrualMonotonicity(uint8 windows) public {
        uint256 nWindows = bound(uint256(windows), 1, 24);

        vm.prank(TRADER);
        engine.depositCollateral(600e18);
        vm.prank(TRADER);
        engine.openPosition(unitTestMarketId, true, 1_000e18, 200e18);

        engine.setIndexPrice(unitTestMarketId, 1e18);
        _captureMarkFromHook(unitTestPoolKey, _sqrtPriceFromRatio(105, 100));

        int256 previous = engine.getMarket(unitTestMarketId).cumulativeFundingRateX18;
        for (uint256 i = 0; i < nWindows; i++) {
            vm.warp(block.timestamp + 1 hours);
            engine.updateFunding(unitTestMarketId);
            int256 current = engine.getMarket(unitTestMarketId).cumulativeFundingRateX18;
            assertGe(current, previous);
            previous = current;
        }
    }

    function testFuzz_liquidationNotBypassableWhenUnhealthy(uint96 leverageNotional) public {
        uint256 notional = bound(uint256(leverageNotional), 700e18, 2_000e18);

        vm.prank(TRADER);
        engine.depositCollateral(300e18);
        vm.prank(TRADER);
        engine.openPosition(unitTestMarketId, true, notional, 200e18);

        _captureMarkFromHook(unitTestPoolKey, _sqrtPriceFromRatio(65, 100));

        vm.prank(LIQUIDATOR);
        liquidation.liquidate(TRADER, unitTestMarketId);

        PerpsEngine.PositionSnapshot memory snapshot = engine.getPosition(unitTestMarketId, TRADER);
        assertEq(snapshot.sizeUsdX18, 0);
    }
}
