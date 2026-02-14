// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/// @title BatchSettlementVault
/// @notice Batch settlements with off-chain netting and Merkle proofs
/// @dev See docs/BATCH_SETTLEMENTS.md for full architecture
contract BatchSettlementVault is Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ──────────────────────────── Types ────────────────────────────

    struct Batch {
        bytes32 merkleRoot;
        uint256 windowStart;
        uint256 windowEnd;
        uint16 userCount;
        uint16 claimedCount;
        bool finalized;
    }

    // ──────────────────────────── State ────────────────────────────

    IERC20 public immutable usdc;
    address public admin;
    address public settlement;

    mapping(bytes32 => Batch) public batches;
    mapping(bytes32 => mapping(address => bool)) public claimed;
    
    mapping(address => uint256) public collateral;
    mapping(address => uint256) public pnl;
    uint256 public brokerPool;

    // ──────────────────────────── Events ───────────────────────────

    event BatchSubmitted(
        bytes32 indexed batchId,
        bytes32 merkleRoot,
        uint256 windowStart,
        uint256 windowEnd,
        uint16 userCount
    );

    event SettlementClaimed(
        bytes32 indexed batchId,
        address indexed user,
        int256 netAmount
    );

    event BatchFinalized(
        bytes32 indexed batchId,
        uint16 claimedCount,
        uint16 totalUsers
    );

    // ──────────────────────────── Errors ───────────────────────────

    error Unauthorized();
    error BatchNotFound();
    error BatchAlreadyExists();
    error AlreadyClaimed();
    error InvalidMerkleProof();
    error InsufficientBalance();
    error InsufficientBrokerPool();

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

    /// @notice Submit a batch of netted settlements
    /// @param merkleRoot Root of Merkle tree containing all netted settlements
    /// @param windowStart Settlement window start timestamp
    /// @param windowEnd Settlement window end timestamp
    /// @param userCount Number of users in batch
    function submitBatch(
        bytes32 merkleRoot,
        uint256 windowStart,
        uint256 windowEnd,
        uint16 userCount
    ) external onlySettlement whenNotPaused {
        bytes32 batchId = keccak256(abi.encodePacked(windowStart, windowEnd));
        
        if (batches[batchId].merkleRoot != bytes32(0)) revert BatchAlreadyExists();

        batches[batchId] = Batch({
            merkleRoot: merkleRoot,
            windowStart: windowStart,
            windowEnd: windowEnd,
            userCount: userCount,
            claimedCount: 0,
            finalized: false
        });

        emit BatchSubmitted(batchId, merkleRoot, windowStart, windowEnd, userCount);
    }

    /// @notice Claim a user's netted settlement from a batch
    /// @param batchId Batch identifier
    /// @param netAmount Net settlement amount (positive = credit, negative = seize)
    /// @param merkleProof Merkle proof that user is in batch
    function claimBatchSettlement(
        bytes32 batchId,
        int256 netAmount,
        bytes32[] calldata merkleProof
    ) external whenNotPaused nonReentrant {
        Batch storage batch = batches[batchId];
        if (batch.merkleRoot == bytes32(0)) revert BatchNotFound();
        if (claimed[batchId][msg.sender]) revert AlreadyClaimed();

        // Verify Merkle proof
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, netAmount, batchId));
        if (!MerkleProof.verify(merkleProof, batch.merkleRoot, leaf)) {
            revert InvalidMerkleProof();
        }

        // Mark claimed
        claimed[batchId][msg.sender] = true;
        batch.claimedCount++;

        // Execute settlement
        if (netAmount > 0) {
            // Credit PnL
            uint256 amount = uint256(netAmount);
            if (brokerPool < amount) revert InsufficientBrokerPool();
            brokerPool -= amount;
            pnl[msg.sender] += amount;
        } else if (netAmount < 0) {
            // Seize collateral
            uint256 amount = uint256(-netAmount);
            if (collateral[msg.sender] < amount) revert InsufficientBalance();
            collateral[msg.sender] -= amount;
            brokerPool += amount;
        }
        // netAmount == 0: user broke even, no settlement needed

        emit SettlementClaimed(batchId, msg.sender, netAmount);
    }

    /// @notice Finalize a batch (marks it immutable)
    /// @param batchId Batch to finalize
    function finalizeBatch(bytes32 batchId) external onlySettlement {
        Batch storage batch = batches[batchId];
        if (batch.merkleRoot == bytes32(0)) revert BatchNotFound();
        require(!batch.finalized, "Already finalized");
        
        batch.finalized = true;
        emit BatchFinalized(batchId, batch.claimedCount, batch.userCount);
    }

    /// @notice Check if a settlement can be claimed
    /// @param batchId Batch identifier
    /// @param user User address
    /// @param netAmount Net settlement amount
    /// @param merkleProof Merkle proof
    /// @return valid True if the claim is valid
    function canClaim(
        bytes32 batchId,
        address user,
        int256 netAmount,
        bytes32[] calldata merkleProof
    ) external view returns (bool valid) {
        Batch storage batch = batches[batchId];
        if (batch.merkleRoot == bytes32(0)) return false;
        if (claimed[batchId][user]) return false;

        bytes32 leaf = keccak256(abi.encodePacked(user, netAmount, batchId));
        return MerkleProof.verify(merkleProof, batch.merkleRoot, leaf);
    }

    /// @notice Get unclaimed users in a batch
    /// @param batchId Batch identifier
    /// @return claimedCount Number of users who claimed
    /// @return totalCount Total users in batch
    function getBatchStatus(bytes32 batchId) external view returns (
        uint16 claimedCount,
        uint16 totalCount,
        bool finalized
    ) {
        Batch storage batch = batches[batchId];
        return (batch.claimedCount, batch.userCount, batch.finalized);
    }

    // ──────────────────────────── User Functions ───────────────────

    function depositCollateral(uint256 amount) external whenNotPaused nonReentrant {
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        collateral[msg.sender] += amount;
    }

    function withdrawCollateral(uint256 amount) external whenNotPaused nonReentrant {
        if (collateral[msg.sender] < amount) revert InsufficientBalance();
        collateral[msg.sender] -= amount;
        usdc.safeTransfer(msg.sender, amount);
    }

    function withdrawPnL(uint256 amount) external whenNotPaused nonReentrant {
        if (pnl[msg.sender] < amount) revert InsufficientBalance();
        pnl[msg.sender] -= amount;
        usdc.safeTransfer(msg.sender, amount);
    }

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
