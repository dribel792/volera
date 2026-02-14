// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ITradingHoursGuard {
    function canTrade(bytes32 symbolId) external view returns (bool allowed, string memory reason);
    function requireCanTrade(bytes32 symbolId) external view;
}
