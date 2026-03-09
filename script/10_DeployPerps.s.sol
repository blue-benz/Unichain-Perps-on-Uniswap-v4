// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/console2.sol";

import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";

import {BasePerpsScript} from "./base/BasePerpsScript.sol";
import {CollateralVault} from "../src/CollateralVault.sol";
import {RiskManager} from "../src/RiskManager.sol";
import {PerpsEngine} from "../src/PerpsEngine.sol";
import {PerpsHook} from "../src/PerpsHook.sol";
import {LiquidationModule} from "../src/LiquidationModule.sol";
import {IRiskManager} from "../src/interfaces/IRiskManager.sol";

contract DeployPerpsScript is BasePerpsScript {
    using PoolIdLibrary for PoolKey;

    struct Deployment {
        address vault;
        address riskManager;
        address engine;
        address hook;
        address liquidationModule;
        bytes32 marketId;
    }

    function run() external {
        setUpArtifacts();

        uint256 privateKey = vm.envOr("PRIVATE_KEY", uint256(0));
        if (privateKey != 0) {
            vm.startBroadcast(privateKey);
        } else {
            vm.startBroadcast();
        }

        Deployment memory dep = _deployPerps(deployerAddress);
        vm.stopBroadcast();

        _printDeployment(dep);
    }

    function _deployPerps(address owner_) internal returns (Deployment memory dep) {
        address collateralAddress = _resolveCollateral();
        (Currency currency0, Currency currency1) = _resolvePoolCurrencies();

        RiskManager riskManager = new RiskManager(owner_);
        CollateralVault vault = new CollateralVault(collateralAddress, owner_);
        PerpsEngine engine = new PerpsEngine(address(vault), address(riskManager), owner_);
        LiquidationModule liquidationModule = new LiquidationModule(address(engine), owner_);

        vault.setEngine(address(engine));
        engine.setLiquidationModule(address(liquidationModule));

        PerpsHook hook = _deployHook(owner_, engine);
        engine.setHook(address(hook));

        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: uint24(vm.envOr("POOL_FEE", uint256(3_000))),
            tickSpacing: int24(int256(vm.envOr("POOL_TICK_SPACING", uint256(60)))),
            hooks: IHooks(hook)
        });

        bytes32 marketId = PoolId.unwrap(poolKey.toId());

        riskManager.setRiskParams(
            marketId,
            IRiskManager.RiskParams({
                initialMarginBps: uint16(vm.envOr("INITIAL_MARGIN_BPS", uint256(1_000))),
                maintenanceMarginBps: uint16(vm.envOr("MAINT_MARGIN_BPS", uint256(500))),
                liquidationPenaltyBps: uint16(vm.envOr("LIQUIDATION_PENALTY_BPS", uint256(400))),
                liquidationIncentiveBps: uint16(vm.envOr("LIQUIDATION_INCENTIVE_BPS", uint256(200))),
                maxLeverageBps: uint32(vm.envOr("MAX_LEVERAGE_BPS", uint256(100_000))),
                maxPremiumBps: uint16(vm.envOr("MAX_PREMIUM_BPS", uint256(300)))
            })
        );

        engine.createMarket(
            poolKey,
            vm.envOr("INITIAL_PRICE_X18", uint256(1e18)),
            vm.envOr("FUNDING_INTERVAL", uint256(1 hours)),
            int256(vm.envOr("FUNDING_VELOCITY_X18", uint256(1e17))),
            vm.envOr("MAX_OPEN_NOTIONAL_X18", uint256(50_000_000e18))
        );

        dep = Deployment({
            vault: address(vault),
            riskManager: address(riskManager),
            engine: address(engine),
            hook: address(hook),
            liquidationModule: address(liquidationModule),
            marketId: marketId
        });
    }

    function _resolveCollateral() internal returns (address collateralAddress) {
        collateralAddress = vm.envOr("COLLATERAL_TOKEN", address(0));
        if (collateralAddress == address(0)) {
            collateralAddress = address(new MockERC20("Perps Collateral", "pUSD", 18));
        }
    }

    function _resolvePoolCurrencies() internal returns (Currency currency0, Currency currency1) {
        Currency currencyA = Currency.wrap(vm.envOr("CURRENCY_A", address(0)));
        Currency currencyB = Currency.wrap(vm.envOr("CURRENCY_B", address(0)));

        if (Currency.unwrap(currencyA) == address(0) || Currency.unwrap(currencyB) == address(0)) {
            (currencyA, currencyB) = deployCurrencyPair();
        }

        (currency0, currency1) = _sortCurrencies(currencyA, currencyB);
    }

    function _deployHook(address owner_, PerpsEngine engine) internal returns (PerpsHook hook) {
        uint160 requiredFlags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);
        bytes memory constructorArgs = abi.encode(poolManager, address(engine), owner_);

        (address expectedHookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_FACTORY, requiredFlags, type(PerpsHook).creationCode, constructorArgs);

        hook = new PerpsHook{salt: salt}(poolManager, address(engine), owner_);
        require(address(hook) == expectedHookAddress, "hook address mismatch");
    }

    function _printDeployment(Deployment memory dep) internal view {
        console2.log("Deployer", deployerAddress);
        console2.log("PoolManager", address(poolManager));
        console2.log("CollateralVault", dep.vault);
        console2.log("RiskManager", dep.riskManager);
        console2.log("PerpsEngine", dep.engine);
        console2.log("PerpsHook", dep.hook);
        console2.log("LiquidationModule", dep.liquidationModule);
        console2.log("MarketId");
        console2.logBytes32(dep.marketId);
    }
}
