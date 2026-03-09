// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library PerpsMath {
    uint256 internal constant ONE = 1e18;
    uint256 internal constant Q96 = 2 ** 96;

    error DivisionByZero();
    error IntOverflow();

    function abs(int256 value) internal pure returns (uint256) {
        if (value >= 0) return uint256(value);
        unchecked {
            return uint256(-value);
        }
    }

    function signedMulDiv(int256 a, int256 b, int256 denominator) internal pure returns (int256) {
        if (denominator == 0) revert DivisionByZero();

        bool negative = (a ^ b ^ denominator) < 0;
        uint256 result = (abs(a) * abs(b)) / abs(denominator);
        if (result > uint256(type(int256).max)) revert IntOverflow();

        int256 signedResult = int256(result);
        return negative ? -signedResult : signedResult;
    }

    function toPriceX18FromSqrtPriceX96(uint160 sqrtPriceX96) internal pure returns (uint256) {
        uint256 numerator = uint256(sqrtPriceX96) * uint256(sqrtPriceX96) * ONE;
        uint256 denominator = Q96 * Q96;
        return numerator / denominator;
    }

    function notionalFromSize(int256 sizeUsdX18) internal pure returns (uint256) {
        return abs(sizeUsdX18);
    }

    function pnlUsdX18(int256 sizeUsdX18, uint256 entryPriceX18, uint256 markPriceX18) internal pure returns (int256) {
        if (sizeUsdX18 == 0 || entryPriceX18 == 0) return 0;

        int256 priceDiff = int256(markPriceX18) - int256(entryPriceX18);
        return signedMulDiv(sizeUsdX18, priceDiff, int256(entryPriceX18));
    }

    function weightedAveragePrice(
        uint256 oldPriceX18,
        uint256 oldNotionalUsdX18,
        uint256 addedPriceX18,
        uint256 addedNotionalUsdX18
    ) internal pure returns (uint256) {
        uint256 totalNotional = oldNotionalUsdX18 + addedNotionalUsdX18;
        if (totalNotional == 0) revert DivisionByZero();

        uint256 weightedSum = (oldPriceX18 * oldNotionalUsdX18) + (addedPriceX18 * addedNotionalUsdX18);
        return weightedSum / totalNotional;
    }
}
