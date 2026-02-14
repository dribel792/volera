// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./ITradingHoursGuard.sol";
import "./IOracleGuard.sol";

/// @title UnifiedAccountVault
/// @notice Core vault managing per-user collateral/PnL sub-ledgers and a broker pool.
///         Collateral is seizable on losses; PnL (winnings) is never seizable.
contract UnifiedAccountVault is Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ──────────────────────────── State ────────────────────────────

    IERC20 public immutable usdc;

    address public admin;
    address public settlement;
    address public broker;

    /// @notice Optional guard contracts
    address public tradingHoursGuard;  // 0x0 = disabled
    address public oracleGuard;        // 0x0 = disabled

    /// @notice Per-user collateral balance (only goes up via deposit, down via withdraw/seize)
    mapping(address => uint256) public collateral;

    /// @notice Per-user PnL balance (only goes up via credit, down via user withdraw)
    mapping(address => uint256) public pnl;

    /// @notice Broker's deposited liquidity pool
    uint256 public brokerPool;

    /// @notice Tracks used refIds to enforce idempotent settlement
    mapping(bytes32 => bool) public usedRefIds;

    // ──────────────────────────── Caps ─────────────────────────────

    uint256 public perUserDailyCap;   // 0 = unlimited
    uint256 public globalDailyCap;    // 0 = unlimited

    /// @notice Per-user daily withdrawn amount, resets each day
    mapping(address => uint256) public userDailyWithdrawn;
    mapping(address => uint256) public userLastWithdrawDay;

    uint256 public globalDailyWithdrawn;
    uint256 public globalLastWithdrawDay;

    // ──────────────────────────── Events ───────────────────────────

    event CollateralDeposited(address indexed user, uint256 amount);
    event CollateralWithdrawn(address indexed user, uint256 amount);
    event PnLCredited(address indexed user, uint256 amount, bytes32 indexed refId);
    event PnLWithdrawn(address indexed user, uint256 amount);
    event CollateralSeized(address indexed user, uint256 amount, bytes32 indexed refId);
    event BrokerDeposited(uint256 amount);
    event BrokerWithdrawn(uint256 amount);

    // ──────────────────────────── Errors ───────────────────────────

    error Unauthorized();
    error InsufficientBalance();
    error InsufficientBrokerPool();
    error DuplicateRefId();
    error ExceedsUserDailyCap();
    error ExceedsGlobalDailyCap();
    error ZeroAmount();

    // ──────────────────────────── Modifiers ────────────────────────

    modifier onlyAdmin() {
        if (msg.sender != admin) revert Unauthorized();
        _;
    }

    modifier onlySettlement() {
        if (msg.sender != settlement) revert Unauthorized();
        _;
    }

    modifier onlyBroker() {
        if (msg.sender != broker) revert Unauthorized();
        _;
    }

    // ──────────────────────────── Constructor ──────────────────────

    constructor(
        address _usdc,
        address _admin,
        address _settlement,
        address _broker
    ) {
        usdc = IERC20(_usdc);
        admin = _admin;
        settlement = _settlement;
        broker = _broker;
    }

    // ──────────────────────────── User Functions ───────────────────

    /// @notice Deposit USDC as collateral
    function depositCollateral(uint256 amount) external whenNotPaused nonReentrant {
        if (amount == 0) revert ZeroAmount();
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        collateral[msg.sender] += amount;
        emit CollateralDeposited(msg.sender, amount);
    }

    /// @notice Withdraw collateral (respects daily caps)
    function withdrawCollateral(uint256 amount) external whenNotPaused nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (collateral[msg.sender] < amount) revert InsufficientBalance();
        _enforceWithdrawCaps(msg.sender, amount);
        collateral[msg.sender] -= amount;
        usdc.safeTransfer(msg.sender, amount);
        emit CollateralWithdrawn(msg.sender, amount);
    }

    /// @notice Withdraw PnL winnings (respects daily caps)
    function withdrawPnL(uint256 amount) external whenNotPaused nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (pnl[msg.sender] < amount) revert InsufficientBalance();
        _enforceWithdrawCaps(msg.sender, amount);
        pnl[msg.sender] -= amount;
        usdc.safeTransfer(msg.sender, amount);
        emit PnLWithdrawn(msg.sender, amount);
    }

    // ──────────────────────────── Settlement Functions ─────────────

    /// @notice Credit PnL to a user (positive settlement). Idempotent via refId.
    function creditPnl(
        address user,
        uint256 amount,
        bytes32 refId
    ) external onlySettlement whenNotPaused nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (usedRefIds[refId]) revert DuplicateRefId();
        if (brokerPool < amount) revert InsufficientBrokerPool();

        usedRefIds[refId] = true;
        brokerPool -= amount;
        pnl[user] += amount;

        emit PnLCredited(user, amount, refId);
    }

    /// @notice Seize user collateral (negative settlement). Moves to broker pool. Idempotent via refId.
    function seizeCollateral(
        address user,
        uint256 amount,
        bytes32 refId
    ) external onlySettlement whenNotPaused nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (usedRefIds[refId]) revert DuplicateRefId();
        if (collateral[user] < amount) revert InsufficientBalance();

        usedRefIds[refId] = true;
        collateral[user] -= amount;
        brokerPool += amount;

        emit CollateralSeized(user, amount, refId);
    }

    /// @notice Credit PnL with guard checks (symbolId required if guards are set)
    function creditPnlWithGuards(
        address user,
        uint256 amount,
        bytes32 refId,
        bytes32 symbolId
    ) external onlySettlement whenNotPaused nonReentrant {
        _checkGuards(symbolId);
        
        if (amount == 0) revert ZeroAmount();
        if (usedRefIds[refId]) revert DuplicateRefId();
        if (brokerPool < amount) revert InsufficientBrokerPool();

        usedRefIds[refId] = true;
        brokerPool -= amount;
        pnl[user] += amount;

        emit PnLCredited(user, amount, refId);
    }

    /// @notice Seize collateral with guard checks (symbolId required if guards are set)
    function seizeCollateralWithGuards(
        address user,
        uint256 amount,
        bytes32 refId,
        bytes32 symbolId
    ) external onlySettlement whenNotPaused nonReentrant {
        _checkGuards(symbolId);
        
        if (amount == 0) revert ZeroAmount();
        if (usedRefIds[refId]) revert DuplicateRefId();
        if (collateral[user] < amount) revert InsufficientBalance();

        usedRefIds[refId] = true;
        collateral[user] -= amount;
        brokerPool += amount;

        emit CollateralSeized(user, amount, refId);
    }

    // ──────────────────────────── Broker Functions ─────────────────

    /// @notice Broker deposits USDC into the broker pool
    function brokerDeposit(uint256 amount) external onlyBroker whenNotPaused nonReentrant {
        if (amount == 0) revert ZeroAmount();
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        brokerPool += amount;
        emit BrokerDeposited(amount);
    }

    /// @notice Broker withdraws from the broker pool
    function brokerWithdraw(uint256 amount) external onlyBroker whenNotPaused nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (brokerPool < amount) revert InsufficientBrokerPool();
        brokerPool -= amount;
        usdc.safeTransfer(msg.sender, amount);
        emit BrokerWithdrawn(amount);
    }

    // ──────────────────────────── Admin Functions ──────────────────

    function pause() external onlyAdmin {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }

    function setPerUserDailyCap(uint256 cap) external onlyAdmin {
        perUserDailyCap = cap;
    }

    function setGlobalDailyCap(uint256 cap) external onlyAdmin {
        globalDailyCap = cap;
    }

    function setSettlement(address _settlement) external onlyAdmin {
        settlement = _settlement;
    }

    function setBroker(address _broker) external onlyAdmin {
        broker = _broker;
    }

    function setAdmin(address _admin) external onlyAdmin {
        admin = _admin;
    }

    function setTradingHoursGuard(address _guard) external onlyAdmin {
        tradingHoursGuard = _guard;
    }

    function setOracleGuard(address _guard) external onlyAdmin {
        oracleGuard = _guard;
    }

    // ──────────────────────────── Internal ─────────────────────────

    /// @notice Check trading hours and oracle guards (if set)
    function _checkGuards(bytes32 symbolId) internal view {
        // Check trading hours guard
        if (tradingHoursGuard != address(0)) {
            ITradingHoursGuard(tradingHoursGuard).requireCanTrade(symbolId);
        }
        
        // Oracle guard check is passive - just ensures oracle is configured
        // Actual price validation happens off-chain in bridge service
        if (oracleGuard != address(0)) {
            (bool valid,) = IOracleGuard(oracleGuard).isPriceValid(symbolId);
            require(valid, "Oracle price invalid");
        }
    }

    function _currentDay() internal view returns (uint256) {
        return block.timestamp / 1 days;
    }

    function _enforceWithdrawCaps(address user, uint256 amount) internal {
        uint256 today = _currentDay();

        // Per-user daily cap
        if (perUserDailyCap > 0) {
            if (userLastWithdrawDay[user] != today) {
                userDailyWithdrawn[user] = 0;
                userLastWithdrawDay[user] = today;
            }
            if (userDailyWithdrawn[user] + amount > perUserDailyCap) {
                revert ExceedsUserDailyCap();
            }
            userDailyWithdrawn[user] += amount;
        }

        // Global daily cap
        if (globalDailyCap > 0) {
            if (globalLastWithdrawDay != today) {
                globalDailyWithdrawn = 0;
                globalLastWithdrawDay = today;
            }
            if (globalDailyWithdrawn + amount > globalDailyCap) {
                revert ExceedsGlobalDailyCap();
            }
            globalDailyWithdrawn += amount;
        }
    }
}
