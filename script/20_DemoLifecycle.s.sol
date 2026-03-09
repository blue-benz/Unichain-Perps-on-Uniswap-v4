// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/console2.sol";

import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {BasePerpsScript} from "./base/BasePerpsScript.sol";
import {CollateralVault} from "../src/CollateralVault.sol";
import {RiskManager} from "../src/RiskManager.sol";
import {PerpsEngine} from "../src/PerpsEngine.sol";
import {PerpsHook} from "../src/PerpsHook.sol";
import {LiquidationModule} from "../src/LiquidationModule.sol";
import {IRiskManager} from "../src/interfaces/IRiskManager.sol";

contract DemoLifecycleScript is BasePerpsScript {
    using PoolIdLibrary for PoolKey;

    MockERC20 internal collateral;
    PerpsEngine internal engine;
    LiquidationModule internal liquidationModule;
    RiskManager internal riskManager;
    CollateralVault internal vault;
    PerpsHook internal hook;

    PoolKey internal poolKey;
    bytes32 internal marketId;

    function run() external {
        setUpArtifacts();

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        uint256 traderAKey = vm.envUint("TRADER_A_PRIVATE_KEY");
        uint256 traderBKey = vm.envUint("TRADER_B_PRIVATE_KEY");

        address deployer = vm.addr(deployerKey);
        address traderA = vm.addr(traderAKey);
        address traderB = vm.addr(traderBKey);

        vm.startBroadcast(deployerKey);
        _deployPhase(deployer, traderA, traderB);
        vm.stopBroadcast();

        vm.startBroadcast(traderAKey);
        _openTraderPosition(true, 3_000e18, 400e18);
        vm.stopBroadcast();

        vm.startBroadcast(traderBKey);
        _openTraderPosition(false, 2_000e18, 400e18);
        vm.stopBroadcast();

        vm.startBroadcast(deployerKey);
        _runLiquidationDemo(deployer, traderA);
        vm.stopBroadcast();

        console2.log("Demo deployed and executed");
        console2.log("vault", address(vault));
        console2.log("risk", address(riskManager));
        console2.log("engine", address(engine));
        console2.log("hook", address(hook));
        console2.log("liquidation", address(liquidationModule));
        console2.log("marketId");
        console2.logBytes32(marketId);
    }

    function _deployPhase(address deployer, address traderA, address traderB) internal {
        MockERC20 tokenA = new MockERC20("Asset A", "ASA", 18);
        MockERC20 tokenB = new MockERC20("Asset B", "ASB", 18);
        collateral = new MockERC20("Perps USD", "pUSD", 18);

        (Currency memory0, Currency memory1) =
            _sortCurrencies(Currency.wrap(address(tokenA)), Currency.wrap(address(tokenB)));

        riskManager = new RiskManager(deployer);
        vault = new CollateralVault(address(collateral), deployer);
        engine = new PerpsEngine(address(vault), address(riskManager), deployer);
        liquidationModule = new LiquidationModule(address(engine), deployer);

        vault.setEngine(address(engine));
        engine.setLiquidationModule(address(liquidationModule));

        hook = _deployHook(deployer);
        engine.setHook(address(hook));

        poolKey = PoolKey({currency0: memory0, currency1: memory1, fee: 3_000, tickSpacing: 60, hooks: IHooks(hook)});
        marketId = PoolId.unwrap(poolKey.toId());

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

        engine.createMarket(poolKey, 1e18, 30 seconds, 1e17, 20_000_000e18);

        collateral.mint(deployer, 1_000_000e18);
        collateral.approve(address(vault), type(uint256).max);
        vault.depositInsurance(500_000e18);

        collateral.mint(traderA, 5_000e18);
        collateral.mint(traderB, 5_000e18);
    }

    function _deployHook(address deployer) internal returns (PerpsHook deployedHook) {
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);
        bytes memory constructorArgs = abi.encode(poolManager, address(engine), deployer);
        (address expectedHookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_FACTORY, flags, type(PerpsHook).creationCode, constructorArgs);

        deployedHook = new PerpsHook{salt: salt}(poolManager, address(engine), deployer);
        require(address(deployedHook) == expectedHookAddress, "hook address mismatch");
    }

    function _openTraderPosition(bool isLong, uint256 notional, uint256 margin) internal {
        collateral.approve(address(vault), type(uint256).max);
        engine.depositCollateral(1_000e18);
        engine.openPosition(marketId, isLong, notional, margin);
    }

    function _runLiquidationDemo(address deployer, address traderA) internal {
        engine.setIndexPrice(marketId, 1e18);

        // deterministic local demo move to trigger liquidation path.
        engine.setHook(deployer);
        engine.captureMarkPriceFromHook(poolKey, uint160((uint256(2) ** 96) * 70 / 100), 0);
        engine.updateFunding(marketId);
        liquidationModule.liquidate(traderA, marketId);
    }
}
