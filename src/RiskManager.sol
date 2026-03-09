// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IRiskManager} from "./interfaces/IRiskManager.sol";

contract RiskManager is IRiskManager, Ownable {
    error InvalidRiskParameter();
    error InitialMarginTooLow();
    error MaintenanceMarginTooLow();
    error ZeroMarket();

    mapping(bytes32 marketId => RiskParams params) internal _riskParams;

    event RiskParamsUpdated(bytes32 indexed marketId, RiskParams params);

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setRiskParams(bytes32 marketId, RiskParams calldata params) external override onlyOwner {
        if (marketId == bytes32(0)) revert ZeroMarket();
        if (
            params.initialMarginBps == 0 || params.maintenanceMarginBps == 0 || params.maxLeverageBps == 0
                || params.initialMarginBps > 10_000 || params.maintenanceMarginBps > params.initialMarginBps
                || params.liquidationPenaltyBps > 2_000 || params.liquidationIncentiveBps > 2_000
        ) {
            revert InvalidRiskParameter();
        }

        _riskParams[marketId] = params;
        emit RiskParamsUpdated(marketId, params);
    }

    function getRiskParams(bytes32 marketId) external view override returns (RiskParams memory) {
        return _params(marketId);
    }

    function initialMarginRequired(bytes32 marketId, uint256 notionalUsdX18) public view override returns (uint256) {
        RiskParams memory params = _params(marketId);
        return (notionalUsdX18 * params.initialMarginBps) / 10_000;
    }

    function maintenanceMarginRequired(bytes32 marketId, uint256 notionalUsdX18)
        public
        view
        override
        returns (uint256)
    {
        RiskParams memory params = _params(marketId);
        return (notionalUsdX18 * params.maintenanceMarginBps) / 10_000;
    }

    function validateInitialMargin(bytes32 marketId, uint256 notionalUsdX18, uint256 collateralUsdX18)
        external
        view
        override
    {
        RiskParams memory params = _params(marketId);
        uint256 required = (notionalUsdX18 * params.initialMarginBps) / 10_000;
        if (collateralUsdX18 < required) revert InitialMarginTooLow();

        // leverage = notional / collateral, bounded in bps precision (1x = 10_000)
        uint256 leverageBps = (notionalUsdX18 * 10_000) / collateralUsdX18;
        if (leverageBps > params.maxLeverageBps) revert InitialMarginTooLow();
    }

    function validateMaintenanceMargin(bytes32 marketId, uint256 notionalUsdX18, int256 equityUsdX18)
        external
        view
        override
    {
        if (equityUsdX18 < 0) revert MaintenanceMarginTooLow();

        uint256 required = maintenanceMarginRequired(marketId, notionalUsdX18);
        if (uint256(equityUsdX18) < required) revert MaintenanceMarginTooLow();
    }

    function _params(bytes32 marketId) internal view returns (RiskParams memory params) {
        params = _riskParams[marketId];
        if (params.maxLeverageBps == 0) revert ZeroMarket();
    }
}
