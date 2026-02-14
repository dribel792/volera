// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title PrivateSettlementVault
/// @notice Commitment-based settlement that hides amounts from public view
/// @dev See docs/PRIVATE_SETTLEMENTS.md for full architecture
contract PrivateSettlementVault is Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ──────────────────────────── Types ────────────────────────────

    struct PrivateSettlement {
        address user;
        bytes32 commitmentHash;      // keccak256(amount, salt, refId)
        bytes32 refId;
        bytes encryptedMemo;         // Encrypted with user's public key
        uint256 timestamp;
        bool executed;
        bool isCredit;               // true = credit PnL, false = seize collateral
    }

    // ──────────────────────────── State ────────────────────────────

    IERC20 public immutable usdc;
    address public admin;
    address public settlement;

    mapping(bytes32 => PrivateSettlement) public settlements;
    mapping(address => uint256) public collateral;
    mapping(address => uint256) public pnl;
    uint256 public brokerPool;

    // ──────────────────────────── Events ───────────────────────────

    event PrivateSettlementCommitted(
        address indexed user,
        bytes32 indexed refId,
        bytes32 commitmentHash,
        bool isCredit
    );

    event PrivateSettlementExecuted(
        bytes32 indexed refId,
        address indexed user
    );

    // NOTE: No amount in event — that's the whole point of private settlements.
    // Amount is only known to settlement role + user (via encrypted memo).

    // ──────────────────────────── Errors ───────────────────────────

    error Unauthorized();
    error SettlementAlreadyExecuted();
    error InvalidReveal();
    error InsufficientBalance();

    // ──────────────────────────── Modifiers ────────────────────────

    modifier onlyAdmin() {
        if (msg.sender != admin) revert Unauthorized();
        _;
    }

    modifier onlySettlement() {
        if (msg.sender != settlement) revert Unauthorized();
        _;
    }

    // ──────────────────────────── Constructor ──────────────────────

    constructor(
        address _usdc,
        address _admin,
        address _settlement
    ) {
        usdc = IERC20(_usdc);
        admin = _admin;
        settlement = _settlement;
    }

    // ──────────────────────────── Core Functions ───────────────────

    /// @notice Commit to a private settlement (amount hidden)
    /// @param user The user being settled
    /// @param commitmentHash keccak256(abi.encodePacked(amount, salt, refId))
    /// @param refId Unique settlement identifier
    /// @param encryptedMemo Encrypted settlement details for user verification
    /// @param isCredit true = credit PnL (win), false = seize collateral (loss)
    function commitSettlement(
        address user,
        bytes32 commitmentHash,
        bytes32 refId,
        bytes calldata encryptedMemo,
        bool isCredit
    ) external onlySettlement whenNotPaused {
        require(settlements[refId].timestamp == 0, "Settlement exists");

        settlements[refId] = PrivateSettlement({
            user: user,
            commitmentHash: commitmentHash,
            refId: refId,
            encryptedMemo: encryptedMemo,
            timestamp: block.timestamp,
            executed: false,
            isCredit: isCredit
        });

        emit PrivateSettlementCommitted(user, refId, commitmentHash, isCredit);
    }

    /// @notice Execute a private settlement (verify commitment and update balances)
    /// @param refId Settlement to execute
    /// @param amount The actual settlement amount (revealed)
    /// @param salt Random salt used in commitment
    function executePrivateSettlement(
        bytes32 refId,
        uint256 amount,
        bytes32 salt
    ) external onlySettlement whenNotPaused nonReentrant {
        PrivateSettlement storage s = settlements[refId];
        require(s.timestamp > 0, "Settlement not found");
        require(!s.executed, "Already executed");

        // Verify commitment
        bytes32 computed = keccak256(abi.encodePacked(amount, salt, refId));
        if (computed != s.commitmentHash) revert InvalidReveal();

        // Execute settlement
        if (s.isCredit) {
            // Credit PnL (win)
            require(brokerPool >= amount, "Insufficient broker pool");
            brokerPool -= amount;
            pnl[s.user] += amount;
        } else {
            // Seize collateral (loss)
            require(collateral[s.user] >= amount, "Insufficient collateral");
            collateral[s.user] -= amount;
            brokerPool += amount;
        }

        s.executed = true;
        emit PrivateSettlementExecuted(refId, s.user);
    }

    /// @notice Verify a settlement (doesn't reveal amount publicly)
    /// @param refId Settlement to verify
    /// @param amount The claimed amount
    /// @param salt The salt used in commitment
    /// @return valid True if the reveal is correct
    function verifySettlement(
        bytes32 refId,
        uint256 amount,
        bytes32 salt
    ) external view returns (bool valid) {
        PrivateSettlement storage s = settlements[refId];
        bytes32 computed = keccak256(abi.encodePacked(amount, salt, refId));
        return computed == s.commitmentHash;
    }

    /// @notice Standard collateral deposit (compatible with existing vault)
    function depositCollateral(uint256 amount) external whenNotPaused nonReentrant {
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        collateral[msg.sender] += amount;
    }

    /// @notice Withdraw collateral
    function withdrawCollateral(uint256 amount) external whenNotPaused nonReentrant {
        require(collateral[msg.sender] >= amount, "Insufficient collateral");
        collateral[msg.sender] -= amount;
        usdc.safeTransfer(msg.sender, amount);
    }

    /// @notice Withdraw PnL
    function withdrawPnL(uint256 amount) external whenNotPaused nonReentrant {
        require(pnl[msg.sender] >= amount, "Insufficient PnL");
        pnl[msg.sender] -= amount;
        usdc.safeTransfer(msg.sender, amount);
    }

    /// @notice Broker deposits into pool
    function brokerDeposit(uint256 amount) external whenNotPaused nonReentrant {
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        brokerPool += amount;
    }

    // ──────────────────────────── Admin ────────────────────────────

    function pause() external onlyAdmin {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }

    function setSettlement(address _settlement) external onlyAdmin {
        settlement = _settlement;
    }
}
