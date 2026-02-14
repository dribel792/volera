// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title SecurityTokenVault
/// @notice DVP (Delivery vs Payment) for security tokens.
///         Handles atomic settlement: user pays USDC, receives security token in wallet.
///         Supports both spot purchases AND tokenization of off-chain positions.
contract SecurityTokenVault is Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ──────────────────────────── Types ────────────────────────────

    enum SettlementType {
        BUY,          // User buys security token with USDC (DVP)
        SELL,         // User sells security token for USDC (DVP)
        TOKENIZE,     // Convert off-chain position to token (no payment, just delivery)
        DETOKENIZE    // Convert token back to off-chain position (burn token)
    }

    struct Settlement {
        bytes32 refId;
        address user;
        address securityToken;
        uint256 tokenAmount;
        uint256 usdcAmount;
        SettlementType settlementType;
        uint256 timestamp;
        bool executed;
    }

    struct SecurityTokenConfig {
        bool exists;
        bool enabled;
        address tokenAddress;
        bytes32 symbolId;              // For oracle/hours lookup
        uint256 minOrderSize;          // Minimum tokens per order
        uint256 maxOrderSize;          // Maximum tokens per order
        uint256 dailyMintLimit;        // Max tokens mintable per day
        uint256 dailyMinted;           // Tokens minted today
        uint256 lastMintDay;
    }

    // ──────────────────────────── State ────────────────────────────

    IERC20 public immutable usdc;

    address public admin;
    address public settlement;     // Can execute settlements
    address public minter;         // Can mint/burn security tokens
    address public treasury;       // Receives/provides USDC for trades

    /// @notice Registered security tokens
    mapping(address => SecurityTokenConfig) public securityTokens;
    
    /// @notice Settlement records by refId
    mapping(bytes32 => Settlement) public settlements;
    
    /// @notice User pending settlements (not yet executed)
    mapping(address => bytes32[]) public userPendingSettlements;
    
    /// @notice Total USDC held in escrow for pending settlements
    uint256 public escrowBalance;

    // ──────────────────────────── Events ───────────────────────────

    event SecurityTokenRegistered(address indexed token, bytes32 symbolId);
    event SecurityTokenEnabled(address indexed token, bool enabled);
    
    event SettlementCreated(
        bytes32 indexed refId,
        address indexed user,
        address indexed securityToken,
        SettlementType settlementType,
        uint256 tokenAmount,
        uint256 usdcAmount
    );
    
    event SettlementExecuted(
        bytes32 indexed refId,
        address indexed user,
        address indexed securityToken,
        SettlementType settlementType
    );
    
    event SettlementCancelled(bytes32 indexed refId, string reason);

    // ──────────────────────────── Errors ───────────────────────────

    error Unauthorized();
    error TokenNotRegistered();
    error TokenDisabled();
    error SettlementNotFound();
    error SettlementAlreadyExecuted();
    error DuplicateRefId();
    error InsufficientBalance();
    error InsufficientEscrow();
    error InsufficientTreasury();
    error OrderTooSmall();
    error OrderTooLarge();
    error DailyMintLimitExceeded();
    error ZeroAmount();
    error InvalidSettlementType();

    // ──────────────────────────── Modifiers ────────────────────────

    modifier onlyAdmin() {
        if (msg.sender != admin) revert Unauthorized();
        _;
    }

    modifier onlySettlement() {
        if (msg.sender != settlement) revert Unauthorized();
        _;
    }

    modifier onlyMinter() {
        if (msg.sender != minter) revert Unauthorized();
        _;
    }

    // ──────────────────────────── Constructor ──────────────────────

    constructor(
        address _usdc,
        address _admin,
        address _settlement,
        address _minter,
        address _treasury
    ) {
        usdc = IERC20(_usdc);
        admin = _admin;
        settlement = _settlement;
        minter = _minter;
        treasury = _treasury;
    }

    // ──────────────────────────── User Functions ───────────────────

    /// @notice User initiates a BUY order: deposits USDC, will receive tokens
    /// @param securityToken Address of the security token to buy
    /// @param tokenAmount Amount of tokens to buy
    /// @param maxUsdcAmount Maximum USDC user is willing to pay
    /// @param refId Unique reference ID for this order
    function initiateBuy(
        address securityToken,
        uint256 tokenAmount,
        uint256 maxUsdcAmount,
        bytes32 refId
    ) external whenNotPaused nonReentrant {
        _validateToken(securityToken, tokenAmount);
        if (settlements[refId].user != address(0)) revert DuplicateRefId();
        
        // Lock user's USDC in escrow
        usdc.safeTransferFrom(msg.sender, address(this), maxUsdcAmount);
        escrowBalance += maxUsdcAmount;
        
        settlements[refId] = Settlement({
            refId: refId,
            user: msg.sender,
            securityToken: securityToken,
            tokenAmount: tokenAmount,
            usdcAmount: maxUsdcAmount,
            settlementType: SettlementType.BUY,
            timestamp: block.timestamp,
            executed: false
        });
        
        userPendingSettlements[msg.sender].push(refId);
        
        emit SettlementCreated(refId, msg.sender, securityToken, SettlementType.BUY, tokenAmount, maxUsdcAmount);
    }

    /// @notice User initiates a SELL order: deposits tokens, will receive USDC
    /// @param securityToken Address of the security token to sell
    /// @param tokenAmount Amount of tokens to sell
    /// @param minUsdcAmount Minimum USDC user expects to receive
    /// @param refId Unique reference ID for this order
    function initiateSell(
        address securityToken,
        uint256 tokenAmount,
        uint256 minUsdcAmount,
        bytes32 refId
    ) external whenNotPaused nonReentrant {
        _validateToken(securityToken, tokenAmount);
        if (settlements[refId].user != address(0)) revert DuplicateRefId();
        
        // Lock user's security tokens
        IERC20(securityToken).safeTransferFrom(msg.sender, address(this), tokenAmount);
        
        settlements[refId] = Settlement({
            refId: refId,
            user: msg.sender,
            securityToken: securityToken,
            tokenAmount: tokenAmount,
            usdcAmount: minUsdcAmount,
            settlementType: SettlementType.SELL,
            timestamp: block.timestamp,
            executed: false
        });
        
        userPendingSettlements[msg.sender].push(refId);
        
        emit SettlementCreated(refId, msg.sender, securityToken, SettlementType.SELL, tokenAmount, minUsdcAmount);
    }

    // ──────────────────────────── Settlement Functions ─────────────

    /// @notice Execute a BUY settlement: deliver tokens to user, take USDC to treasury
    /// @param refId Settlement reference ID
    /// @param actualUsdcAmount Actual USDC amount (must be <= maxUsdcAmount)
    function executeBuy(
        bytes32 refId,
        uint256 actualUsdcAmount
    ) external onlySettlement whenNotPaused nonReentrant {
        Settlement storage s = settlements[refId];
        if (s.user == address(0)) revert SettlementNotFound();
        if (s.executed) revert SettlementAlreadyExecuted();
        if (s.settlementType != SettlementType.BUY) revert InvalidSettlementType();
        if (actualUsdcAmount > s.usdcAmount) revert InsufficientEscrow();
        
        s.executed = true;
        
        // Refund excess USDC to user
        uint256 refund = s.usdcAmount - actualUsdcAmount;
        if (refund > 0) {
            escrowBalance -= refund;
            usdc.safeTransfer(s.user, refund);
        }
        
        // Send actual payment to treasury
        escrowBalance -= actualUsdcAmount;
        usdc.safeTransfer(treasury, actualUsdcAmount);
        
        // Mint and deliver security tokens to user
        _mintSecurityToken(s.securityToken, s.user, s.tokenAmount);
        
        emit SettlementExecuted(refId, s.user, s.securityToken, SettlementType.BUY);
    }

    /// @notice Execute a SELL settlement: take tokens, deliver USDC to user
    /// @param refId Settlement reference ID
    /// @param actualUsdcAmount Actual USDC amount (must be >= minUsdcAmount)
    function executeSell(
        bytes32 refId,
        uint256 actualUsdcAmount
    ) external onlySettlement whenNotPaused nonReentrant {
        Settlement storage s = settlements[refId];
        if (s.user == address(0)) revert SettlementNotFound();
        if (s.executed) revert SettlementAlreadyExecuted();
        if (s.settlementType != SettlementType.SELL) revert InvalidSettlementType();
        if (actualUsdcAmount < s.usdcAmount) revert InsufficientTreasury();
        
        s.executed = true;
        
        // Burn the security tokens
        _burnSecurityToken(s.securityToken, s.tokenAmount);
        
        // Pay user from treasury
        usdc.safeTransferFrom(treasury, s.user, actualUsdcAmount);
        
        emit SettlementExecuted(refId, s.user, s.securityToken, SettlementType.SELL);
    }

    /// @notice Tokenize an off-chain position: mint tokens to user (no USDC movement)
    /// @dev Called when user wants to withdraw their position as tokens
    function executeTokenize(
        address user,
        address securityToken,
        uint256 tokenAmount,
        bytes32 refId
    ) external onlySettlement whenNotPaused nonReentrant {
        _validateToken(securityToken, tokenAmount);
        if (settlements[refId].user != address(0)) revert DuplicateRefId();
        
        settlements[refId] = Settlement({
            refId: refId,
            user: user,
            securityToken: securityToken,
            tokenAmount: tokenAmount,
            usdcAmount: 0,
            settlementType: SettlementType.TOKENIZE,
            timestamp: block.timestamp,
            executed: true
        });
        
        // Mint tokens directly to user
        _mintSecurityToken(securityToken, user, tokenAmount);
        
        emit SettlementCreated(refId, user, securityToken, SettlementType.TOKENIZE, tokenAmount, 0);
        emit SettlementExecuted(refId, user, securityToken, SettlementType.TOKENIZE);
    }

    /// @notice Detokenize: user deposits tokens to convert back to off-chain position
    /// @dev Called when user deposits tokens back to the platform
    function executeDetokenize(
        address user,
        address securityToken,
        uint256 tokenAmount,
        bytes32 refId
    ) external onlySettlement whenNotPaused nonReentrant {
        _validateToken(securityToken, tokenAmount);
        if (settlements[refId].user != address(0)) revert DuplicateRefId();
        
        // Take tokens from user
        IERC20(securityToken).safeTransferFrom(user, address(this), tokenAmount);
        
        settlements[refId] = Settlement({
            refId: refId,
            user: user,
            securityToken: securityToken,
            tokenAmount: tokenAmount,
            usdcAmount: 0,
            settlementType: SettlementType.DETOKENIZE,
            timestamp: block.timestamp,
            executed: true
        });
        
        // Burn the tokens
        _burnSecurityToken(securityToken, tokenAmount);
        
        emit SettlementCreated(refId, user, securityToken, SettlementType.DETOKENIZE, tokenAmount, 0);
        emit SettlementExecuted(refId, user, securityToken, SettlementType.DETOKENIZE);
    }

    /// @notice Cancel a pending settlement and refund user
    function cancelSettlement(bytes32 refId, string calldata reason) external onlySettlement {
        Settlement storage s = settlements[refId];
        if (s.user == address(0)) revert SettlementNotFound();
        if (s.executed) revert SettlementAlreadyExecuted();
        
        s.executed = true; // Mark as processed (cancelled)
        
        if (s.settlementType == SettlementType.BUY) {
            // Refund USDC from escrow
            escrowBalance -= s.usdcAmount;
            usdc.safeTransfer(s.user, s.usdcAmount);
        } else if (s.settlementType == SettlementType.SELL) {
            // Return security tokens
            IERC20(s.securityToken).safeTransfer(s.user, s.tokenAmount);
        }
        
        emit SettlementCancelled(refId, reason);
    }

    // ──────────────────────────── Admin Functions ──────────────────

    function registerSecurityToken(
        address tokenAddress,
        bytes32 symbolId,
        uint256 minOrderSize,
        uint256 maxOrderSize,
        uint256 dailyMintLimit
    ) external onlyAdmin {
        securityTokens[tokenAddress] = SecurityTokenConfig({
            exists: true,
            enabled: true,
            tokenAddress: tokenAddress,
            symbolId: symbolId,
            minOrderSize: minOrderSize,
            maxOrderSize: maxOrderSize,
            dailyMintLimit: dailyMintLimit,
            dailyMinted: 0,
            lastMintDay: 0
        });
        
        emit SecurityTokenRegistered(tokenAddress, symbolId);
    }

    function setSecurityTokenEnabled(address tokenAddress, bool enabled) external onlyAdmin {
        if (!securityTokens[tokenAddress].exists) revert TokenNotRegistered();
        securityTokens[tokenAddress].enabled = enabled;
        emit SecurityTokenEnabled(tokenAddress, enabled);
    }

    function pause() external onlyAdmin { _pause(); }
    function unpause() external onlyAdmin { _unpause(); }
    function setSettlement(address _settlement) external onlyAdmin { settlement = _settlement; }
    function setMinter(address _minter) external onlyAdmin { minter = _minter; }
    function setTreasury(address _treasury) external onlyAdmin { treasury = _treasury; }
    function setAdmin(address _admin) external onlyAdmin { admin = _admin; }

    // ──────────────────────────── Internal ─────────────────────────

    function _validateToken(address token, uint256 amount) internal view {
        SecurityTokenConfig storage cfg = securityTokens[token];
        if (!cfg.exists) revert TokenNotRegistered();
        if (!cfg.enabled) revert TokenDisabled();
        if (amount < cfg.minOrderSize) revert OrderTooSmall();
        if (amount > cfg.maxOrderSize) revert OrderTooLarge();
    }

    function _mintSecurityToken(address token, address to, uint256 amount) internal {
        SecurityTokenConfig storage cfg = securityTokens[token];
        
        // Check daily mint limit
        uint256 today = block.timestamp / 1 days;
        if (cfg.lastMintDay != today) {
            cfg.dailyMinted = 0;
            cfg.lastMintDay = today;
        }
        if (cfg.dailyMinted + amount > cfg.dailyMintLimit) revert DailyMintLimitExceeded();
        cfg.dailyMinted += amount;
        
        // Call mint on the token (assumes IMintable interface)
        IMintable(token).mint(to, amount);
    }

    function _burnSecurityToken(address token, uint256 amount) internal {
        // Call burn on the token (assumes IBurnable interface)
        IBurnable(token).burn(amount);
    }
}

// ──────────────────────────── Interfaces ───────────────────────────

interface IMintable {
    function mint(address to, uint256 amount) external;
}

interface IBurnable {
    function burn(uint256 amount) external;
}
