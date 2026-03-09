// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ICollateralVault} from "./interfaces/ICollateralVault.sol";

contract CollateralVault is ICollateralVault, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error OnlyEngine();
    error InsufficientFreeCollateral();
    error InsufficientLockedCollateral();
    error InsufficientInsurance();
    error ZeroAddress();

    IERC20 public immutable token;
    address public engine;

    mapping(address trader => uint256 amount) public override freeBalance;
    mapping(address trader => uint256 amount) public override lockedBalance;
    uint256 public override insuranceBalance;

    event EngineUpdated(address indexed oldEngine, address indexed newEngine);
    event CollateralDeposited(address indexed trader, uint256 amount);
    event CollateralWithdrawn(address indexed trader, uint256 amount);
    event CollateralLocked(address indexed trader, uint256 amount);
    event CollateralUnlocked(address indexed trader, uint256 amount);
    event InsuranceDeposited(address indexed payer, uint256 amount);
    event InsuranceWithdrawn(address indexed to, uint256 amount);

    modifier onlyEngine() {
        if (msg.sender != engine) revert OnlyEngine();
        _;
    }

    constructor(address collateralToken_, address initialOwner) Ownable(initialOwner) {
        if (collateralToken_ == address(0)) revert ZeroAddress();
        token = IERC20(collateralToken_);
    }

    function collateralToken() external view returns (address) {
        return address(token);
    }

    function setEngine(address newEngine) external onlyOwner {
        if (newEngine == address(0)) revert ZeroAddress();
        emit EngineUpdated(engine, newEngine);
        engine = newEngine;
    }

    function depositFor(address trader, uint256 amount) external onlyEngine nonReentrant {
        token.safeTransferFrom(trader, address(this), amount);
        freeBalance[trader] += amount;
        emit CollateralDeposited(trader, amount);
    }

    function withdrawTo(address trader, uint256 amount) external onlyEngine nonReentrant {
        uint256 free = freeBalance[trader];
        if (free < amount) revert InsufficientFreeCollateral();

        unchecked {
            freeBalance[trader] = free - amount;
        }

        token.safeTransfer(trader, amount);
        emit CollateralWithdrawn(trader, amount);
    }

    function lockCollateral(address trader, uint256 amount) external onlyEngine {
        uint256 free = freeBalance[trader];
        if (free < amount) revert InsufficientFreeCollateral();

        unchecked {
            freeBalance[trader] = free - amount;
        }
        lockedBalance[trader] += amount;

        emit CollateralLocked(trader, amount);
    }

    function unlockCollateral(address trader, uint256 amount) external onlyEngine {
        uint256 locked = lockedBalance[trader];
        if (locked < amount) revert InsufficientLockedCollateral();

        unchecked {
            lockedBalance[trader] = locked - amount;
        }
        freeBalance[trader] += amount;

        emit CollateralUnlocked(trader, amount);
    }

    function transferLockedToInsurance(address trader, uint256 amount) external onlyEngine {
        uint256 locked = lockedBalance[trader];
        if (locked < amount) revert InsufficientLockedCollateral();

        unchecked {
            lockedBalance[trader] = locked - amount;
        }
        insuranceBalance += amount;
    }

    function creditLockedFromInsurance(address trader, uint256 amount) external onlyEngine {
        uint256 insurance = insuranceBalance;
        if (insurance < amount) revert InsufficientInsurance();

        unchecked {
            insuranceBalance = insurance - amount;
        }
        lockedBalance[trader] += amount;
    }

    function creditFreeFromInsurance(address trader, uint256 amount) external onlyEngine {
        uint256 insurance = insuranceBalance;
        if (insurance < amount) revert InsufficientInsurance();

        unchecked {
            insuranceBalance = insurance - amount;
        }
        freeBalance[trader] += amount;
    }

    function depositInsurance(uint256 amount) external nonReentrant {
        token.safeTransferFrom(msg.sender, address(this), amount);
        insuranceBalance += amount;
        emit InsuranceDeposited(msg.sender, amount);
    }

    function withdrawInsurance(address to, uint256 amount) external onlyOwner nonReentrant {
        uint256 insurance = insuranceBalance;
        if (insurance < amount) revert InsufficientInsurance();

        unchecked {
            insuranceBalance = insurance - amount;
        }
        token.safeTransfer(to, amount);

        emit InsuranceWithdrawn(to, amount);
    }
}
