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

    uint256 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    MockERC20 internal collateral;
    PerpsEngine internal engine;
    LiquidationModule internal liquidationModule;
    RiskManager internal riskManager;
    CollateralVault internal vault;
    PerpsHook internal hook;

    PoolKey internal poolKey;
    bytes32 internal marketId;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        uint256 traderAKey = vm.envUint("TRADER_A_PRIVATE_KEY");
        uint256 traderBKey = vm.envUint("TRADER_B_PRIVATE_KEY");

        address deployer = vm.addr(deployerKey);
        address traderA = vm.addr(traderAKey);
        address traderB = vm.addr(traderBKey);

        bool reuseExistingDeployment = vm.envOr("DEMO_USE_EXISTING_DEPLOYMENT", false);
        bool seedCollateral = vm.envOr("DEMO_SEED_COLLATERAL", true);

        console2.log("=== DEMO START ===");
        console2.log("chainId", block.chainid);
        console2.log("deployer", deployer);
        console2.log("traderA (LP hedge actor)", traderA);
        console2.log("traderB (directional trader)", traderB);

        if (reuseExistingDeployment) {
            console2.log("[Phase 1] Attach existing deployment from .env");
            _attachPhase();

            // Normalize mark/index so repeated demo runs remain deterministic.
            if (seedCollateral) {
                console2.log("[Phase 2] Seed collateral + insurance for demo actors");
                vm.startBroadcast(deployerKey);
                _seedCollateralPhase(deployer, traderA, traderB);
                _normalizeMarkForDemo(deployer);
                vm.stopBroadcast();
            } else {
                vm.startBroadcast(deployerKey);
                _normalizeMarkForDemo(deployer);
                vm.stopBroadcast();
            }
        } else {
            console2.log("[Phase 1] Deploy core contracts + create market");
            setUpArtifacts();
            vm.startBroadcast(deployerKey);
            _deployPhase(deployer);
            if (seedCollateral) {
                console2.log("[Phase 2] Seed collateral + insurance for demo actors");
                _seedCollateralPhase(deployer, traderA, traderB);
            }
            _normalizeMarkForDemo(deployer);
            vm.stopBroadcast();
        }

        console2.log("[Phase 3] User perspective: deposit collateral + open long/short");

        vm.startBroadcast(traderAKey);
        _openTraderPosition(true, 3_000e18, 400e18);
        vm.stopBroadcast();

        vm.startBroadcast(traderBKey);
        _openTraderPosition(false, 2_000e18, 400e18);
        vm.stopBroadcast();

        console2.log("[Phase 4] Funding update + deterministic adverse move + liquidation");
        vm.startBroadcast(deployerKey);
        _runLiquidationDemo(deployer, traderA);
        vm.stopBroadcast();

        console2.log("[Phase 5] Final state proof");
        console2.log("vault", address(vault));
        console2.log("risk", address(riskManager));
        console2.log("engine", address(engine));
        console2.log("hook", address(hook));
        console2.log("liquidation", address(liquidationModule));
        console2.log("marketId");
        console2.logBytes32(marketId);
    }

    function _deployPhase(address deployer) internal {
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
    }

    function _attachPhase() internal {
        vault = CollateralVault(vm.envAddress("COLLATERAL_VAULT_ADDRESS"));
        riskManager = RiskManager(vm.envAddress("RISK_MANAGER_ADDRESS"));
        engine = PerpsEngine(vm.envAddress("PERPS_ENGINE_ADDRESS"));
        hook = PerpsHook(vm.envAddress("PERPS_HOOK_ADDRESS"));
        liquidationModule = LiquidationModule(vm.envAddress("LIQUIDATION_MODULE_ADDRESS"));
        marketId = vm.envBytes32("MARKET_ID");

        address currency0 = vm.envAddress("POOL_CURRENCY0");
        address currency1 = vm.envAddress("POOL_CURRENCY1");
        (Currency memory0, Currency memory1) =
            _sortCurrencies(Currency.wrap(currency0), Currency.wrap(currency1));

        poolKey = PoolKey({
            currency0: memory0,
            currency1: memory1,
            fee: uint24(vm.envOr("POOL_FEE", uint256(3_000))),
            tickSpacing: int24(int256(vm.envOr("POOL_TICK_SPACING", uint256(60)))),
            hooks: IHooks(hook)
        });

        collateral = MockERC20(vault.collateralToken());
    }

    function _seedCollateralPhase(address deployer, address traderA, address traderB) internal {
        uint256 deployerMint = vm.envOr("DEMO_DEPLOYER_COLLATERAL_MINT", uint256(1_000_000e18));
        uint256 insuranceDeposit = vm.envOr("DEMO_INSURANCE_DEPOSIT", uint256(500_000e18));
        uint256 traderMint = vm.envOr("DEMO_TRADER_COLLATERAL_MINT", uint256(5_000e18));

        collateral.mint(deployer, deployerMint);
        collateral.approve(address(vault), type(uint256).max);
        if (insuranceDeposit > 0) {
            vault.depositInsurance(insuranceDeposit);
        }

        collateral.mint(traderA, traderMint);
        collateral.mint(traderB, traderMint);
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

    function _normalizeMarkForDemo(address deployer) internal {
        engine.setHook(deployer);
        engine.captureMarkPriceFromHook(poolKey, uint160(SQRT_PRICE_1_1), 0);
        engine.setIndexPrice(marketId, 1e18);
    }

    function _runLiquidationDemo(address deployer, address traderA) internal {
        engine.setIndexPrice(marketId, 1e18);

        // deterministic local demo move to trigger liquidation path.
        engine.setHook(deployer);
        uint256 numerator = vm.envOr("DEMO_MARK_RATIO_NUMERATOR", uint256(70));
        uint256 denominator = vm.envOr("DEMO_MARK_RATIO_DENOMINATOR", uint256(100));
        uint160 sqrtPriceX96 = uint160((SQRT_PRICE_1_1 * numerator) / denominator);
        engine.captureMarkPriceFromHook(poolKey, sqrtPriceX96, 0);
        engine.updateFunding(marketId);
        liquidationModule.liquidate(traderA, marketId);
    }
}
