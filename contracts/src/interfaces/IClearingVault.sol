// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IClearingVault
/// @notice Interface for ClearingVault used by MarginVault
interface IClearingVault {
    /// @notice Record an obligation between vaults
    function recordObligation(
        address fromVault,
        address toVault,
        uint256 amount,
        bytes32 refId
    ) external;

    /// @notice Execute netting
    function executeNetting() external;

    /// @notice Get net obligation between two vaults
    function netObligation(address vaultA, address vaultB) external view returns (int256);

    /// @notice Get pending obligation count
    function pendingObligationCount() external view returns (uint256);
}
