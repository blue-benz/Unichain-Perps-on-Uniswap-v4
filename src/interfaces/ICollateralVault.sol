// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface ICollateralVault {
    function collateralToken() external view returns (address);

    function freeBalance(address trader) external view returns (uint256);

    function lockedBalance(address trader) external view returns (uint256);

    function insuranceBalance() external view returns (uint256);

    function depositFor(address trader, uint256 amount) external;

    function withdrawTo(address trader, uint256 amount) external;

    function lockCollateral(address trader, uint256 amount) external;

    function unlockCollateral(address trader, uint256 amount) external;

    function transferLockedToInsurance(address trader, uint256 amount) external;

    function creditLockedFromInsurance(address trader, uint256 amount) external;

    function creditFreeFromInsurance(address trader, uint256 amount) external;
}
