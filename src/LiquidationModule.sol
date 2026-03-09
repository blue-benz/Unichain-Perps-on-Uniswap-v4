// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IPerpsEngine} from "./interfaces/IPerpsEngine.sol";

contract LiquidationModule is Ownable, ReentrancyGuard {
    error ZeroAddress();

    IPerpsEngine public immutable engine;

    event LiquidationExecuted(address indexed liquidator, address indexed trader, bytes32 indexed marketId);

    constructor(address engine_, address initialOwner) Ownable(initialOwner) {
        if (engine_ == address(0)) revert ZeroAddress();
        engine = IPerpsEngine(engine_);
    }

    function liquidate(address trader, bytes32 marketId) external nonReentrant {
        engine.liquidatePosition(trader, marketId, msg.sender);
        emit LiquidationExecuted(msg.sender, trader, marketId);
    }
}
