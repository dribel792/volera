// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title HubVault
/// @notice Single global vault for cross-venue portfolio margin
/// @dev Replaces MarginVault in V3 architecture - one contract, per-user accounting
contract HubVault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ──────────────────────────── Immutables ────────────────────────────

    IERC20 public immutable usdc;

    // ──────────────────────────── State ────────────────────────────

    address public keeper;                // equity engine keeper
    address public governance;            // timelocked governance

    // User state
    mapping(address => uint256) public collateral;           // user deposits
    mapping(address => uint256) public totalMarginLocked;    // total margin across all venues
    mapping(address => mapping(address => uint256)) public venueEquity;  // equity shown to each venue

    // Venue registry
    mapping(address => bool) public registeredVenues;
    address[] public venueList;

    // Insurance
    uint256 public insurancePool;
    uint256 public totalDeposits;

    // Risk parameters
    uint256 public haircutBps;          // default 5000 = 50%
    uint256 public maxVenueAllocationBps; // max % of collateral to one venue, e.g. 8000 = 80%
    uint256 public overspendThresholdBps; // margin/collateral ratio trigger, e.g. 9000 = 90%

    // Dedup
    mapping(bytes32 => bool) public processedEvents;

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
    event KeeperUpdated(address indexed oldKeeper, address indexed newKeeper);
    event GovernanceUpdated(address indexed oldGovernance, address indexed newGovernance);
    event HaircutUpdated(uint256 oldBps, uint256 newBps);
    event MaxVenueAllocationUpdated(uint256 oldBps, uint256 newBps);
    event OverspendThresholdUpdated(uint256 oldBps, uint256 newBps);

    // ──────────────────────────── Modifiers ────────────────────────────

    modifier onlyKeeper() {
        require(msg.sender == keeper, "HubVault: caller is not keeper");
        _;
    }

    modifier onlyGovernance() {
        require(msg.sender == governance, "HubVault: caller is not governance");
        _;
    }

    // ──────────────────────────── Constructor ────────────────────────────

    constructor(
        address _usdc,
        address _keeper,
        address _governance,
        uint256 _haircutBps
    ) {
        require(_usdc != address(0), "HubVault: zero address usdc");
        require(_keeper != address(0), "HubVault: zero address keeper");
        require(_governance != address(0), "HubVault: zero address governance");
        require(_haircutBps <= 10000, "HubVault: haircut exceeds 100%");

        usdc = IERC20(_usdc);
        keeper = _keeper;
        governance = _governance;
        haircutBps = _haircutBps;
        maxVenueAllocationBps = 8000; // 80% default
        overspendThresholdBps = 9000; // 90% default
    }

    // ──────────────────────────── USER FUNCTIONS ────────────────────────────

    /// @notice Deposit collateral into HubVault
    /// @param amount Amount of USDC to deposit
    function depositCollateral(uint256 amount) external nonReentrant {
        require(amount > 0, "HubVault: zero amount");

        collateral[msg.sender] += amount;
        totalDeposits += amount;

        usdc.safeTransferFrom(msg.sender, address(this), amount);

        emit CollateralDeposited(msg.sender, amount);
    }

    /// @notice Withdraw available collateral
    /// @param amount Amount of USDC to withdraw
    /// @dev NO pause modifier — users can always withdraw available balance
    function withdrawAvailable(uint256 amount) external nonReentrant {
        require(amount > 0, "HubVault: zero amount");

        uint256 available = availableBalance(msg.sender);
        require(amount <= available, "HubVault: insufficient available balance");

        collateral[msg.sender] -= amount;
        totalDeposits -= amount;

        usdc.safeTransfer(msg.sender, amount);

        emit CollateralWithdrawn(msg.sender, amount);
    }

    /// @notice Get available balance for a user
    /// @param user User address
    /// @return Available balance (collateral - totalMarginLocked)
    function availableBalance(address user) public view returns (uint256) {
        uint256 userCollateral = collateral[user];
        uint256 locked = totalMarginLocked[user];
        
        if (locked >= userCollateral) {
            return 0;
        }
        
        return userCollateral - locked;
    }

    // ──────────────────────────── KEEPER FUNCTIONS ────────────────────────────

    /// @notice Update equity shown to a venue for a user
    /// @param user User address
    /// @param venue Venue address
    /// @param newEquity New equity amount
    /// @param eventId Event identifier for deduplication
    function updateVenueEquity(
        address user,
        address venue,
        uint256 newEquity,
        bytes32 eventId
    ) external onlyKeeper {
        require(registeredVenues[venue], "HubVault: venue not registered");
        require(!processedEvents[eventId], "HubVault: event already processed");

        processedEvents[eventId] = true;
        venueEquity[user][venue] = newEquity;

        emit VenueEquityUpdated(user, venue, newEquity, eventId);
    }

    /// @notice Update total margin locked for a user across all venues
    /// @param user User address
    /// @param newTotalMargin New total margin amount
    function updateMarginLocked(
        address user,
        uint256 newTotalMargin
    ) external onlyKeeper {
        totalMarginLocked[user] = newTotalMargin;

        // Check for overspend
        uint256 userCollateral = collateral[user];
        if (userCollateral > 0) {
            uint256 utilizationBps = (newTotalMargin * 10000) / userCollateral;
            if (utilizationBps >= overspendThresholdBps) {
                emit OverspendDetected(user, newTotalMargin, userCollateral);
            }
        }

        emit MarginLocked(user, newTotalMargin);
    }

    /// @notice Process liquidation shortfall from a venue
    /// @param user User address
    /// @param venue Venue address
    /// @param amount Shortfall amount
    /// @param refId Reference identifier for deduplication
    /// @dev Waterfall: user collateral → insurance pool → bad debt
    function processShortfall(
        address user,
        address venue,
        uint256 amount,
        bytes32 refId
    ) external onlyKeeper nonReentrant {
        require(registeredVenues[venue], "HubVault: venue not registered");
        require(!processedEvents[refId], "HubVault: refId already processed");
        require(amount > 0, "HubVault: zero amount");

        processedEvents[refId] = true;

        uint256 fromCollateral = 0;
        uint256 fromInsurance = 0;
        uint256 remaining = amount;

        // Step 1: Try to cover from user's remaining collateral
        uint256 userAvailable = availableBalance(user);
        if (userAvailable > 0) {
            fromCollateral = remaining < userAvailable ? remaining : userAvailable;
            collateral[user] -= fromCollateral;
            totalDeposits -= fromCollateral;
            remaining -= fromCollateral;
        }

        // Step 2: Try to cover from insurance pool
        if (remaining > 0 && insurancePool > 0) {
            fromInsurance = remaining < insurancePool ? remaining : insurancePool;
            insurancePool -= fromInsurance;
            remaining -= fromInsurance;
        }

        // Step 3: If still insufficient, remaining is bad debt (tracked in event)
        // No further action here - bad debt socialization is handled off-chain

        // Transfer covered amount to venue
        uint256 covered = fromCollateral + fromInsurance;
        if (covered > 0) {
            usdc.safeTransfer(venue, covered);
        }

        emit ShortfallProcessed(user, venue, amount, fromCollateral, fromInsurance, refId);
    }

    /// @notice Batch update equity for multiple users/venues
    /// @param users Array of user addresses
    /// @param venues Array of venue addresses
    /// @param equities Array of equity amounts
    /// @param eventId Event identifier for deduplication
    /// @dev All arrays must be same length
    function batchUpdateEquity(
        address[] calldata users,
        address[] calldata venues,
        uint256[] calldata equities,
        bytes32 eventId
    ) external onlyKeeper {
        require(
            users.length == venues.length && venues.length == equities.length,
            "HubVault: array length mismatch"
        );
        require(!processedEvents[eventId], "HubVault: event already processed");

        processedEvents[eventId] = true;

        for (uint256 i = 0; i < users.length; i++) {
            require(registeredVenues[venues[i]], "HubVault: venue not registered");
            venueEquity[users[i]][venues[i]] = equities[i];
            emit VenueEquityUpdated(users[i], venues[i], equities[i], eventId);
        }
    }

    // ──────────────────────────── INSURANCE FUNCTIONS ────────────────────────────

    /// @notice Deposit into insurance pool
    /// @param amount Amount to deposit
    function depositInsurance(uint256 amount) external nonReentrant {
        require(amount > 0, "HubVault: zero amount");

        insurancePool += amount;
        usdc.safeTransferFrom(msg.sender, address(this), amount);

        emit InsuranceDeposited(msg.sender, amount);
    }

    // ──────────────────────────── GOVERNANCE FUNCTIONS ────────────────────────────

    /// @notice Register a new venue
    /// @param venue Venue address
    function registerVenue(address venue) external onlyGovernance {
        require(venue != address(0), "HubVault: zero address");
        require(!registeredVenues[venue], "HubVault: venue already registered");

        registeredVenues[venue] = true;
        venueList.push(venue);

        emit VenueRegistered(venue);
    }

    /// @notice Remove a venue
    /// @param venue Venue address
    function removeVenue(address venue) external onlyGovernance {
        require(registeredVenues[venue], "HubVault: venue not registered");

        registeredVenues[venue] = false;

        // Remove from venueList
        for (uint256 i = 0; i < venueList.length; i++) {
            if (venueList[i] == venue) {
                venueList[i] = venueList[venueList.length - 1];
                venueList.pop();
                break;
            }
        }

        emit VenueRemoved(venue);
    }

    /// @notice Set keeper address
    /// @param _keeper New keeper address
    function setKeeper(address _keeper) external onlyGovernance {
        require(_keeper != address(0), "HubVault: zero address");
        address oldKeeper = keeper;
        keeper = _keeper;
        emit KeeperUpdated(oldKeeper, _keeper);
    }

    /// @notice Set haircut basis points
    /// @param _bps New haircut bps (max 10000)
    function setHaircutBps(uint256 _bps) external onlyGovernance {
        require(_bps <= 10000, "HubVault: haircut exceeds 100%");
        uint256 oldBps = haircutBps;
        haircutBps = _bps;
        emit HaircutUpdated(oldBps, _bps);
    }

    /// @notice Set max venue allocation basis points
    /// @param _bps New max allocation bps
    function setMaxVenueAllocationBps(uint256 _bps) external onlyGovernance {
        require(_bps <= 10000, "HubVault: allocation exceeds 100%");
        uint256 oldBps = maxVenueAllocationBps;
        maxVenueAllocationBps = _bps;
        emit MaxVenueAllocationUpdated(oldBps, _bps);
    }

    /// @notice Set overspend threshold basis points
    /// @param _bps New threshold bps
    function setOverspendThresholdBps(uint256 _bps) external onlyGovernance {
        require(_bps <= 10000, "HubVault: threshold exceeds 100%");
        uint256 oldBps = overspendThresholdBps;
        overspendThresholdBps = _bps;
        emit OverspendThresholdUpdated(oldBps, _bps);
    }

    // ──────────────────────────── VIEW FUNCTIONS ────────────────────────────

    /// @notice Get user portfolio information
    /// @param user User address
    /// @return userCollateral User's total collateral
    /// @return marginLocked Total margin locked
    /// @return available Available balance
    /// @return insurancePoolBalance Current insurance pool balance
    function getUserPortfolio(address user) external view returns (
        uint256 userCollateral,
        uint256 marginLocked,
        uint256 available,
        uint256 insurancePoolBalance
    ) {
        userCollateral = collateral[user];
        marginLocked = totalMarginLocked[user];
        available = availableBalance(user);
        insurancePoolBalance = insurancePool;
    }

    /// @notice Get equity shown to a venue for a user
    /// @param user User address
    /// @param venue Venue address
    /// @return Equity amount
    function getVenueEquity(address user, address venue) external view returns (uint256) {
        return venueEquity[user][venue];
    }

    /// @notice Get number of registered venues
    /// @return Number of venues
    function venueCount() external view returns (uint256) {
        return venueList.length;
    }

    /// @notice Get list of all registered venues
    /// @return Array of venue addresses
    function getVenueList() external view returns (address[] memory) {
        return venueList;
    }
}
