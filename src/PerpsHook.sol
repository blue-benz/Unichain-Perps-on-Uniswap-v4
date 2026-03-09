// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {IPoolManager, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {IPerpsEngine} from "./interfaces/IPerpsEngine.sol";

contract PerpsHook is BaseHook, Ownable {
    using PoolIdLibrary for PoolKey;

    error HookPaused();
    error MaxSwapImpactExceeded();
    error ZeroAddress();

    IPerpsEngine public immutable engine;

    uint256 public maxAbsAmountSpecified;
    bool public paused;

    mapping(bytes32 poolId => int24 tick) public lastObservedTick;

    event GuardrailsUpdated(uint256 maxAbsAmountSpecified, bool paused);
    event MarkCaptured(bytes32 indexed marketId, uint256 markPriceX18, int24 tick);

    constructor(IPoolManager poolManager_, address engine_, address initialOwner) BaseHook(poolManager_) Ownable(initialOwner) {
        if (engine_ == address(0)) revert ZeroAddress();
        engine = IPerpsEngine(engine_);
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function setGuardrails(uint256 maxAbsAmountSpecified_, bool paused_) external onlyOwner {
        maxAbsAmountSpecified = maxAbsAmountSpecified_;
        paused = paused_;

        emit GuardrailsUpdated(maxAbsAmountSpecified_, paused_);
    }

    function _beforeSwap(address, PoolKey calldata, SwapParams calldata params, bytes calldata)
        internal
        override
        view
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        if (paused) revert HookPaused();

        if (maxAbsAmountSpecified > 0) {
            uint256 swapAbs = params.amountSpecified >= 0 ? uint256(params.amountSpecified) : uint256(-params.amountSpecified);
            if (swapAbs > maxAbsAmountSpecified) revert MaxSwapImpactExceeded();
        }

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(address, PoolKey calldata key, SwapParams calldata, BalanceDelta, bytes calldata)
        internal
        override
        returns (bytes4, int128)
    {
        PoolId poolId = key.toId();
        (uint160 sqrtPriceX96, int24 tick,,) = StateLibrary.getSlot0(poolManager, poolId);

        bytes32 rawPoolId = PoolId.unwrap(poolId);
        lastObservedTick[rawPoolId] = tick;

        engine.captureMarkPriceFromHook(key, sqrtPriceX96, tick);
        emit MarkCaptured(rawPoolId, _priceFromSqrtPrice(sqrtPriceX96), tick);

        return (BaseHook.afterSwap.selector, 0);
    }

    function _priceFromSqrtPrice(uint160 sqrtPriceX96) internal pure returns (uint256) {
        uint256 numerator = uint256(sqrtPriceX96) * uint256(sqrtPriceX96) * 1e18;
        return numerator / (uint256(2 ** 96) * uint256(2 ** 96));
    }
}
