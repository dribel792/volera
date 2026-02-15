// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IMarginVault
/// @notice Interface for MarginVault used by ClearingVault
interface IMarginVault {
    /// @notice Transfer funds to clearing vault for cross-broker settlement
    function transferToClearing(uint256 amount) external;

    /// @notice Receive funds from clearing vault
    function receiveFromClearing(uint256 amount) external;

    /// @notice Get broker stake amount
    function brokerStake() external view returns (uint256);

    /// @notice Get insurance fund amount
    function insuranceFund() external view returns (uint256);
}
