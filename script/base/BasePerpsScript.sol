// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {Deployers} from "test/utils/Deployers.sol";

abstract contract BasePerpsScript is Script, Deployers {
    address internal deployerAddress;

    function setUpArtifacts() internal {
        deployArtifacts();
        deployerAddress = _deployer();
    }

    function _deployer() internal returns (address) {
        address[] memory wallets = vm.getWallets();
        if (wallets.length > 0) {
            return wallets[0];
        }

        uint256 privateKey = vm.envOr("PRIVATE_KEY", uint256(0));
        if (privateKey != 0) {
            return vm.addr(privateKey);
        }

        return msg.sender;
    }

    function _sortCurrencies(Currency a, Currency b) internal pure returns (Currency currency0, Currency currency1) {
        require(Currency.unwrap(a) != Currency.unwrap(b), "identical currencies");
        if (Currency.unwrap(a) < Currency.unwrap(b)) {
            return (a, b);
        }
        return (b, a);
    }

    function _etch(address target, bytes memory bytecode) internal override {
        if (block.chainid == 31337) {
            vm.rpc("anvil_setCode", string.concat('["', vm.toString(target), '",', '"', vm.toString(bytecode), '"]'));
        } else {
            revert("etch only supported on anvil");
        }
    }
}
