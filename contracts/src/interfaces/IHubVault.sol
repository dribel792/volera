// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IHubVault
/// @notice Interface for HubVault - single global vault for cross-venue portfolio margin
interface IHubVault {
    // ──────────────────────────── Events ────────────────────────────

    event CollateralDeposited(address indexed user, uint256 amount);
    event CollateralWithdrawn(address indexed user, uint256 amount);
    event VenueEquityUpdated(address indexed user, address indexed venue, uint256 newEquity, bytes32 eventId);
    event MarginLocked(address indexed user, uint256 totalMargin);
    event ShortfallProcessed(address indexed user, address indexed venue, uint256 amount, uint256 fromCollateral, uint256 fromInsurance, bytes32 refId);
    event InsuranceDeposited(address indexed from, uint256 amount);
    event OverspendDetected(address indexed user, uint256 totalMargin, uint256 collateral);
    event VenueRegistered(address venue);
    event VenueRemoved(address venue);

    // ──────────────────────────── User Functions ────────────────────────────

    /// @notice Deposit collateral into HubVault
    function depositCollateral(uint256 amount) external;

    /// @notice Withdraw available collateral
    function withdrawAvailable(uint256 amount) external;

    /// @notice Get available balance for a user
    function availableBalance(address user) external view returns (uint256);

    // ──────────────────────────── Keeper Functions ────────────────────────────

    /// @notice Update equity shown to a venue for a user
    function updateVenueEquity(
        address user,
        address venue,
        uint256 newEquity,
        bytes32 eventId
    ) external;

    /// @notice Update total margin locked for a user
    function updateMarginLocked(address user, uint256 newTotalMargin) external;

    /// @notice Process liquidation shortfall from a venue
    function processShortfall(
        address user,
        address venue,
        uint256 amount,
        bytes32 refId
    ) external;

    /// @notice Batch update equity for multiple users/venues
    function batchUpdateEquity(
        address[] calldata users,
        address[] calldata venues,
        uint256[] calldata equities,
        bytes32 eventId
    ) external;

    // ──────────────────────────── Insurance Functions ────────────────────────────

    /// @notice Deposit into insurance pool
    function depositInsurance(uint256 amount) external;

    // ──────────────────────────── Governance Functions ────────────────────────────

    /// @notice Register a new venue
    function registerVenue(address venue) external;

    /// @notice Remove a venue
    function removeVenue(address venue) external;

    /// @notice Set keeper address
    function setKeeper(address _keeper) external;

    /// @notice Set haircut basis points
    function setHaircutBps(uint256 _bps) external;

    /// @notice Set max venue allocation basis points
    function setMaxVenueAllocationBps(uint256 _bps) external;

    /// @notice Set overspend threshold basis points
    function setOverspendThresholdBps(uint256 _bps) external;

    // ──────────────────────────── View Functions ────────────────────────────

    /// @notice Get user portfolio information
    function getUserPortfolio(address user) external view returns (
        uint256 userCollateral,
        uint256 marginLocked,
        uint256 available,
        uint256 insurancePoolBalance
    );

    /// @notice Get equity shown to a venue for a user
    function getVenueEquity(address user, address venue) external view returns (uint256);

    /// @notice Get number of registered venues
    function venueCount() external view returns (uint256);

    /// @notice Get list of all registered venues
    function getVenueList() external view returns (address[] memory);

    // ──────────────────────────── State Variables ────────────────────────────

    function collateral(address user) external view returns (uint256);
    function totalMarginLocked(address user) external view returns (uint256);
    function venueEquity(address user, address venue) external view returns (uint256);
    function registeredVenues(address venue) external view returns (bool);
    function insurancePool() external view returns (uint256);
    function totalDeposits() external view returns (uint256);
    function haircutBps() external view returns (uint256);
    function maxVenueAllocationBps() external view returns (uint256);
    function overspendThresholdBps() external view returns (uint256);
    function processedEvents(bytes32 eventId) external view returns (bool);
    function keeper() external view returns (address);
    function governance() external view returns (address);
}
