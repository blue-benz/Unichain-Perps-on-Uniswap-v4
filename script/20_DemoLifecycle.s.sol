// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/console2.sol";

import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";

import {BasePerpsScript} from "./base/BasePerpsScript.sol";
import {EasyPosm} from "../test/utils/libraries/EasyPosm.sol";
import {CollateralVault} from "../src/CollateralVault.sol";
import {RiskManager} from "../src/RiskManager.sol";
import {PerpsEngine} from "../src/PerpsEngine.sol";
import {PerpsHook} from "../src/PerpsHook.sol";
import {LiquidationModule} from "../src/LiquidationModule.sol";
import {IRiskManager} from "../src/interfaces/IRiskManager.sol";

contract DemoLifecycleScript is BasePerpsScript {
    using PoolIdLibrary for PoolKey;
    using EasyPosm for IPositionManager;

    function run() external {
        setUpArtifacts();

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        uint256 traderAKey = vm.envUint("TRADER_A_PRIVATE_KEY");
        uint256 traderBKey = vm.envUint("TRADER_B_PRIVATE_KEY");

        address deployer = vm.addr(deployerKey);
        address traderA = vm.addr(traderAKey);
        address traderB = vm.addr(traderBKey);

        vm.startBroadcast(deployerKey);

        (Currency currencyA, Currency currencyB) = deployCurrencyPair();
        (Currency currency0, Currency currency1) = _sortCurrencies(currencyA, currencyB);

        MockERC20 collateral = new MockERC20("Perps USD", "pUSD", 18);
        RiskManager riskManager = new RiskManager(deployer);
        CollateralVault vault = new CollateralVault(address(collateral), deployer);
        PerpsEngine engine = new PerpsEngine(address(vault), address(riskManager), deployer);
        LiquidationModule liquidationModule = new LiquidationModule(address(engine), deployer);

        vault.setEngine(address(engine));
        engine.setLiquidationModule(address(liquidationModule));

        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);
        bytes memory constructorArgs = abi.encode(poolManager, address(engine), deployer);
        (address expectedHookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_FACTORY, flags, type(PerpsHook).creationCode, constructorArgs);
        PerpsHook hook = new PerpsHook{salt: salt}(poolManager, address(engine), deployer);
        require(address(hook) == expectedHookAddress, "hook address mismatch");
        engine.setHook(address(hook));

        PoolKey memory poolKey =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3_000, tickSpacing: 60, hooks: IHooks(hook)});
        bytes32 marketId = PoolId.unwrap(poolKey.toId());

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

        // short funding window for demo.
        engine.createMarket(poolKey, 1e18, 30 seconds, 1e17, 20_000_000e18);

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
            deployer,
            block.timestamp,
            Constants.ZERO_BYTES
        );

        collateral.mint(traderA, 5_000e18);
        collateral.mint(traderB, 5_000e18);
        vm.stopBroadcast();

        vm.startBroadcast(traderAKey);
        collateral.approve(address(vault), type(uint256).max);
        engine.depositCollateral(1_000e18);
        engine.openPosition(marketId, true, 2_000e18, 500e18);
        vm.stopBroadcast();

        vm.startBroadcast(traderBKey);
        collateral.approve(address(vault), type(uint256).max);
        engine.depositCollateral(1_000e18);
        engine.openPosition(marketId, false, 2_000e18, 500e18);
        vm.stopBroadcast();

        vm.startBroadcast(deployerKey);
        swapRouter.swapExactTokensForTokens({
            amountIn: 50e18,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: deployer,
            deadline: block.timestamp + 180
        });

        engine.updateFunding(marketId);

        // deterministic liquidation stress move for local demo.
        engine.setHook(deployer);
        engine.captureMarkPriceFromHook(poolKey, uint160((2 ** 96) * 75 / 100), 0);
        _liquidate(liquidationModule, traderA, marketId);

        vm.stopBroadcast();

        console2.log("Demo deployed");
        console2.log("vault", address(vault));
        console2.log("risk", address(riskManager));
        console2.log("engine", address(engine));
        console2.log("hook", address(hook));
        console2.log("liquidation", address(liquidationModule));
        console2.log("marketId");
        console2.logBytes32(marketId);
    }

    function _liquidate(LiquidationModule module_, address trader, bytes32 marketId) internal {
        module_.liquidate(trader, marketId);
    }
}
