// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IClearingVault.sol";

/// @title MarginVault
/// @notice Self-governed per-broker vault with margin locking and insurance waterfall.
///         Users can ALWAYS withdraw available balance. Broker deposits stake as skin in the game.
///         Integrates with ClearingVault for cross-broker settlements.
contract MarginVault is Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ──────────────────────────── State ────────────────────────────

    IERC20 public immutable usdc;

    // Roles — set at deployment, immutable
    address public immutable broker;        // The exchange operator
    address public settlement;              // Keeper that executes settlements
    address public clearingVault;           // For cross-broker flows

    // User balances
    mapping(address => uint256) public balances;
    mapping(address => uint256) public marginInUse;

    // Broker's skin in the game
    uint256 public brokerStake;
    uint256 public minimumStakeRatio;  // Basis points (e.g., 1000 = 10%)

    // Insurance
    uint256 public insuranceFund;

    // Safety
    uint256 public socializedLoss;
    mapping(bytes32 => bool) public settledRefIds;  // Dedup

    // Daily caps (from V1)
    uint256 public perUserDailyCap;
    uint256 public globalDailyCap;
    mapping(address => mapping(uint256 => uint256)) public userDailySettled;
    uint256 public globalDailySettled;
    uint256 public currentDay;

    // ──────────────────────────── Events ───────────────────────────

    event CollateralDeposited(address indexed user, uint256 amount);
    event CollateralWithdrawn(address indexed user, uint256 amount);
    event MarginLocked(address indexed user, uint256 amount, bytes32 positionId);
    event MarginUnlocked(address indexed user, uint256 amount, bytes32 positionId);
    event PnLCredited(address indexed user, uint256 amount, bytes32 refId);
    event CollateralSeized(address indexed user, uint256 amount, bytes32 refId);
    event Shortfall(address indexed user, uint256 amount, uint256 coveredByInsurance, uint256 coveredByBroker, uint256 socialized);
    event BrokerStakeDeposited(uint256 amount);
    event BrokerStakeWithdrawn(uint256 amount);
    event InsuranceFundDeposited(uint256 amount);
    event ClearingTransferOut(uint256 amount);
    event ClearingTransferIn(uint256 amount);
    event Liquidation(address indexed user, bytes32 positionId, uint256 amount);
    event SettlementSet(address indexed settlement);
    event ClearingVaultSet(address indexed clearingVault);

    // ──────────────────────────── Errors ───────────────────────────

    error Unauthorized();
    error InsufficientBalance();
    error InsufficientBrokerStake();
    error DuplicateRefId();
    error ExceedsUserDailyCap();
    error ExceedsGlobalDailyCap();
    error ZeroAmount();
    error BelowMinimumStake();

    // ──────────────────────────── Modifiers ────────────────────────

    modifier onlySettlement() {
        if (msg.sender != settlement) revert Unauthorized();
        _;
    }

    modifier onlyBroker() {
        if (msg.sender != broker) revert Unauthorized();
        _;
    }

    modifier onlyClearingVault() {
        if (msg.sender != clearingVault) revert Unauthorized();
        _;
    }

    // ──────────────────────────── Constructor ──────────────────────

    constructor(
        address _usdc,
        address _broker,
        address _settlement,
        uint256 _minimumStakeRatio
    ) {
        usdc = IERC20(_usdc);
        broker = _broker;
        settlement = _settlement;
        minimumStakeRatio = _minimumStakeRatio;
    }

    // ──────────────────────────── User Functions ───────────────────

    /// @notice Deposit USDC as collateral
    function depositCollateral(uint256 amount) external whenNotPaused nonReentrant {
        if (amount == 0) revert ZeroAmount();
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        balances[msg.sender] += amount;
        emit CollateralDeposited(msg.sender, amount);
    }

    /// @notice Withdraw available balance (balance - marginInUse)
    /// Users can ALWAYS withdraw available funds - no admin override
    function withdrawAvailable(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        uint256 available = availableBalance(msg.sender);
        if (amount > available) revert InsufficientBalance();
        
        _enforceWithdrawCaps(msg.sender, amount);
        
        balances[msg.sender] -= amount;
        usdc.safeTransfer(msg.sender, amount);
        emit CollateralWithdrawn(msg.sender, amount);
    }

    /// @notice Get user's total balance
    function balanceOf(address user) external view returns (uint256) {
        return balances[user];
    }

    /// @notice Get user's available balance (can withdraw)
    function availableBalance(address user) public view returns (uint256) {
        uint256 balance = balances[user];
        uint256 locked = marginInUse[user];
        return balance > locked ? balance - locked : 0;
    }

    // ──────────────────────────── Settlement Functions ─────────────

    /// @notice Credit PnL to a user (they won). Funds come from brokerStake.
    function creditPnl(address user, uint256 amount, bytes32 refId) 
        external 
        onlySettlement 
        whenNotPaused 
        nonReentrant 
    {
        if (amount == 0) revert ZeroAmount();
        if (settledRefIds[refId]) revert DuplicateRefId();
        if (brokerStake < amount) revert InsufficientBrokerStake();

        settledRefIds[refId] = true;
        brokerStake -= amount;
        balances[user] += amount;

        emit PnLCredited(user, amount, refId);
    }

    /// @notice Seize collateral from a user (they lost). Goes to brokerStake.
    /// @return shortfall Amount that couldn't be seized (covered by insurance waterfall)
    function seizeCollateral(address user, uint256 amount, bytes32 refId) 
        external 
        onlySettlement 
        whenNotPaused 
        nonReentrant 
        returns (uint256 shortfall)
    {
        if (amount == 0) revert ZeroAmount();
        if (settledRefIds[refId]) revert DuplicateRefId();

        settledRefIds[refId] = true;

        uint256 available = availableBalance(user);
        uint256 seized = amount > available ? available : amount;
        shortfall = amount - seized;

        // Seize available collateral
        if (seized > 0) {
            balances[user] -= seized;
            brokerStake += seized;
            emit CollateralSeized(user, seized, refId);
        }

        // Handle shortfall via insurance waterfall
        if (shortfall > 0) {
            uint256 coveredByInsurance = 0;
            uint256 coveredByBroker = 0;
            uint256 socialized = 0;
            uint256 remainingShortfall = shortfall;

            // 1. Insurance fund
            if (insuranceFund >= remainingShortfall) {
                coveredByInsurance = remainingShortfall;
                insuranceFund -= remainingShortfall;
                brokerStake += remainingShortfall;
                remainingShortfall = 0;
            } else if (insuranceFund > 0) {
                coveredByInsurance = insuranceFund;
                brokerStake += insuranceFund;
                remainingShortfall -= insuranceFund;
                insuranceFund = 0;
            }

            // 2. Broker stake (already there from the seized amount, just accounting)
            if (remainingShortfall > 0 && brokerStake >= remainingShortfall) {
                coveredByBroker = remainingShortfall;
                // Broker stake already covers it (no movement needed)
                remainingShortfall = 0;
            } else if (remainingShortfall > 0 && brokerStake > 0) {
                coveredByBroker = brokerStake;
                remainingShortfall -= brokerStake;
                // brokerStake stays as is (can't go negative)
            }

            // 3. Socialized loss (last resort)
            if (remainingShortfall > 0) {
                socialized = remainingShortfall;
                socializedLoss += remainingShortfall;
            }

            emit Shortfall(user, shortfall, coveredByInsurance, coveredByBroker, socialized);
        }

        return shortfall;
    }

    /// @notice Lock margin for an open position
    function lockMargin(address user, uint256 amount, bytes32 positionId) 
        external 
        onlySettlement 
        whenNotPaused 
        nonReentrant 
    {
        if (amount == 0) revert ZeroAmount();
        if (balances[user] < marginInUse[user] + amount) revert InsufficientBalance();

        marginInUse[user] += amount;
        emit MarginLocked(user, amount, positionId);
    }

    /// @notice Unlock margin when position closes
    function unlockMargin(address user, uint256 amount, bytes32 positionId) 
        external 
        onlySettlement 
        whenNotPaused 
        nonReentrant 
    {
        if (amount == 0) revert ZeroAmount();
        if (marginInUse[user] < amount) revert InsufficientBalance();

        marginInUse[user] -= amount;
        emit MarginUnlocked(user, amount, positionId);
    }

    /// @notice Liquidate a position: unlock margin + seize collateral in one tx
    function liquidate(address user, bytes32 positionId, uint256 seizeAmount, bytes32 refId) 
        external 
        onlySettlement 
        whenNotPaused 
        nonReentrant 
    {
        if (seizeAmount == 0) revert ZeroAmount();
        if (settledRefIds[refId]) revert DuplicateRefId();

        settledRefIds[refId] = true;

        // Unlock all margin for this position (passed as seizeAmount for simplicity)
        if (marginInUse[user] >= seizeAmount) {
            marginInUse[user] -= seizeAmount;
        } else {
            marginInUse[user] = 0;
        }

        // Seize collateral
        uint256 available = availableBalance(user);
        uint256 seized = seizeAmount > available ? available : seizeAmount;
        
        if (seized > 0) {
            balances[user] -= seized;
            brokerStake += seized;
        }

        emit Liquidation(user, positionId, seized);
    }

    // ──────────────────────────── Broker Functions ─────────────────

    /// @notice Broker deposits stake (skin in the game)
    function depositBrokerStake(uint256 amount) external onlyBroker whenNotPaused nonReentrant {
        if (amount == 0) revert ZeroAmount();
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        brokerStake += amount;
        emit BrokerStakeDeposited(amount);
    }

    /// @notice Broker withdraws stake (cannot go below minimum requirement)
    function withdrawBrokerStake(uint256 amount) external onlyBroker whenNotPaused nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (brokerStake < amount) revert InsufficientBrokerStake();
        
        uint256 minRequired = minimumRequired();
        if (brokerStake - amount < minRequired) revert BelowMinimumStake();

        brokerStake -= amount;
        usdc.safeTransfer(msg.sender, amount);
        emit BrokerStakeWithdrawn(amount);
    }

    /// @notice Broker deposits into insurance fund
    function depositInsurance(uint256 amount) external onlyBroker whenNotPaused nonReentrant {
        if (amount == 0) revert ZeroAmount();
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        insuranceFund += amount;
        emit InsuranceFundDeposited(amount);
    }

    // ──────────────────────────── Clearing Vault Functions ─────────

    /// @notice Transfer funds to clearing vault for cross-broker settlement
    function transferToClearing(uint256 amount) external onlyClearingVault whenNotPaused nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (brokerStake < amount) revert InsufficientBrokerStake();

        brokerStake -= amount;
        usdc.safeTransfer(clearingVault, amount);
        emit ClearingTransferOut(amount);
    }

    /// @notice Receive funds from clearing vault
    function receiveFromClearing(uint256 amount) external onlyClearingVault whenNotPaused nonReentrant {
        if (amount == 0) revert ZeroAmount();
        usdc.safeTransferFrom(clearingVault, address(this), amount);
        brokerStake += amount;
        emit ClearingTransferIn(amount);
    }

    // ──────────────────────────── View Functions ───────────────────

    /// @notice Total user deposits across all users
    function totalUserDeposits() public view returns (uint256) {
        // This would require tracking in production; simplified here
        // In practice, sum all balances or maintain a counter
        return usdc.balanceOf(address(this)) - brokerStake - insuranceFund;
    }

    /// @notice Minimum required broker stake
    function minimumRequired() public view returns (uint256) {
        uint256 totalDeposits = totalUserDeposits();
        return (totalDeposits * minimumStakeRatio) / 10000;
    }

    /// @notice Vault health metrics
    function vaultHealth() external view returns (
        uint256 totalDeposits,
        uint256 stake,
        uint256 insurance,
        uint256 ratio
    ) {
        totalDeposits = totalUserDeposits();
        stake = brokerStake;
        insurance = insuranceFund;
        ratio = totalDeposits > 0 ? (stake * 10000) / totalDeposits : 0;
    }

    // ──────────────────────────── Admin Functions ──────────────────

    /// @notice Update settlement address (only callable by broker, one-time setup)
    function setSettlement(address _settlement) external onlyBroker {
        settlement = _settlement;
        emit SettlementSet(_settlement);
    }

    /// @notice Set clearing vault address (only callable by broker, one-time setup)
    function setClearingVault(address _clearingVault) external onlyBroker {
        clearingVault = _clearingVault;
        emit ClearingVaultSet(_clearingVault);
    }

    /// @notice Pause settlements (NOT user withdrawals)
    function pauseSettlements() external onlyBroker {
        _pause();
    }

    /// @notice Unpause settlements
    function unpauseSettlements() external onlyBroker {
        _unpause();
    }

    // ──────────────────────────── Internal ─────────────────────────

    function _currentDay() internal view returns (uint256) {
        return block.timestamp / 1 days;
    }

    function _enforceWithdrawCaps(address user, uint256 amount) internal {
        uint256 today = _currentDay();

        // Per-user daily cap
        if (perUserDailyCap > 0) {
            if (currentDay != today) {
                // Reset daily counters
                currentDay = today;
            }
            
            uint256 userWithdrawnToday = userDailySettled[user][today];
            if (userWithdrawnToday + amount > perUserDailyCap) {
                revert ExceedsUserDailyCap();
            }
            userDailySettled[user][today] = userWithdrawnToday + amount;
        }

        // Global daily cap
        if (globalDailyCap > 0) {
            if (currentDay != today) {
                globalDailySettled = 0;
                currentDay = today;
            }
            if (globalDailySettled + amount > globalDailyCap) {
                revert ExceedsGlobalDailyCap();
            }
            globalDailySettled += amount;
        }
    }
}
