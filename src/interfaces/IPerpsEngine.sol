// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

interface IPerpsEngine {
    struct PositionSnapshot {
        int256 sizeUsdX18;
        uint256 collateralUsdX18;
        uint256 entryPriceX18;
        int256 lastCumulativeFundingRateX18;
    }

    struct MarketSnapshot {
        bool exists;
        bytes32 marketId;
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

    function createMarket(
        PoolKey calldata key,
        uint256 initialPriceX18,
        uint256 fundingInterval,
        int256 fundingVelocityX18,
        uint256 maxOpenNotionalUsdX18
    ) external returns (bytes32 marketId);

    function marketIdFromPoolKey(PoolKey calldata key) external pure returns (bytes32);

    function captureMarkPriceFromHook(PoolKey calldata key, uint160 sqrtPriceX96, int24 tick) external;

    function updateFunding(bytes32 marketId) external;

    function setIndexPrice(bytes32 marketId, uint256 indexPriceX18) external;

    function depositCollateral(uint256 amount) external;

    function withdrawCollateral(uint256 amount) external;

    function addMargin(bytes32 marketId, uint256 amount) external;

    function removeMargin(bytes32 marketId, uint256 amount) external;

    function openPosition(bytes32 marketId, bool isLong, uint256 notionalUsdX18, uint256 marginUsdX18) external;

    function modifyPosition(bytes32 marketId, int256 sizeDeltaUsdX18) external;

    function closePosition(bytes32 marketId, uint256 reduceNotionalUsdX18) external;

    function liquidatePosition(address trader, bytes32 marketId, address liquidator) external;

    function getMarket(bytes32 marketId) external view returns (MarketSnapshot memory);

    function getPosition(bytes32 marketId, address trader) external view returns (PositionSnapshot memory);

    function positionEquityUsdX18(bytes32 marketId, address trader) external view returns (int256 equityUsdX18);

    function unrealizedPnlUsdX18(bytes32 marketId, address trader) external view returns (int256 pnlUsdX18);
}
