// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IRiskManager {
    struct RiskParams {
        uint16 initialMarginBps;
        uint16 maintenanceMarginBps;
        uint16 liquidationPenaltyBps;
        uint16 liquidationIncentiveBps;
        uint32 maxLeverageBps;
        uint16 maxPremiumBps;
    }

    function getRiskParams(bytes32 marketId) external view returns (RiskParams memory);

    function setRiskParams(bytes32 marketId, RiskParams calldata params) external;

    function initialMarginRequired(bytes32 marketId, uint256 notionalUsdX18) external view returns (uint256);

    function maintenanceMarginRequired(bytes32 marketId, uint256 notionalUsdX18) external view returns (uint256);

    function validateInitialMargin(bytes32 marketId, uint256 notionalUsdX18, uint256 collateralUsdX18) external view;

    function validateMaintenanceMargin(bytes32 marketId, uint256 notionalUsdX18, int256 equityUsdX18) external view;
}
