// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IMarginVault.sol";

/// @title ClearingVault
/// @notice Cross-broker netting and settlement coordination.
///         Accumulates obligations during a netting window, then executes net transfers.
contract ClearingVault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ──────────────────────────── Types ────────────────────────────

    struct Obligation {
        address fromVault;
        address toVault;
        uint256 amount;
        bytes32 refId;
        uint256 timestamp;
    }

    // ──────────────────────────── State ────────────────────────────

    IERC20 public immutable usdc;
    
    // Governance (initially a multisig, later DAO)
    address public governance;
    address public settlement;  // Keeper that can record obligations
    
    // Registered broker vaults
    mapping(address => bool) public registeredVaults;
    address[] public vaultList;
    
    // Guarantee deposits per vault
    mapping(address => uint256) public guaranteeDeposits;
    mapping(address => uint256) public minimumGuarantee;
    
    // Obligations tracking
    Obligation[] public pendingObligations;
    mapping(bytes32 => bool) public settledObligations;  // Dedup
    
    // Default fund
    uint256 public defaultFund;
    
    // Netting config
    uint256 public nettingWindowSeconds;
    uint256 public lastNettingTimestamp;

    // ──────────────────────────── Events ───────────────────────────

    event VaultRegistered(address indexed vault);
    event VaultRemoved(address indexed vault);
    event GuaranteeDeposited(address indexed vault, uint256 amount);
    event GuaranteeWithdrawn(address indexed vault, uint256 amount);
    event MinimumGuaranteeSet(address indexed vault, uint256 amount);
    event ObligationRecorded(address indexed fromVault, address indexed toVault, uint256 amount, bytes32 refId);
    event NettingExecuted(uint256 obligationsCount, uint256 grossVolume, uint256 netVolume, uint256 savings);
    event ImmediateSettlement(address indexed fromVault, address indexed toVault, uint256 amount, bytes32 refId);
    event DefaultFundDeposited(uint256 amount);
    event DefaultFundUsed(address indexed vault, uint256 amount);
    event GovernanceSet(address indexed governance);
    event SettlementSet(address indexed settlement);
    event NettingWindowSet(uint256 windowSeconds);

    // ──────────────────────────── Errors ───────────────────────────

    error Unauthorized();
    error VaultNotRegistered();
    error VaultAlreadyRegistered();
    error BelowMinimumGuarantee();
    error DuplicateObligation();
    error NettingWindowNotElapsed();
    error InsufficientGuarantee();
    error ZeroAmount();
    error ZeroAddress();

    // ──────────────────────────── Modifiers ────────────────────────

    modifier onlyGovernance() {
        if (msg.sender != governance) revert Unauthorized();
        _;
    }

    modifier onlySettlement() {
        if (msg.sender != settlement) revert Unauthorized();
        _;
    }

    modifier onlyRegisteredVault() {
        if (!registeredVaults[msg.sender]) revert VaultNotRegistered();
        _;
    }

    // ──────────────────────────── Constructor ──────────────────────

    constructor(
        address _usdc,
        address _governance,
        address _settlement,
        uint256 _nettingWindowSeconds
    ) {
        if (_usdc == address(0) || _governance == address(0) || _settlement == address(0)) {
            revert ZeroAddress();
        }
        
        usdc = IERC20(_usdc);
        governance = _governance;
        settlement = _settlement;
        nettingWindowSeconds = _nettingWindowSeconds;
        lastNettingTimestamp = block.timestamp;
    }

    // ──────────────────────────── Governance Functions ─────────────

    /// @notice Register a new broker vault
    function registerVault(address vault) external onlyGovernance {
        if (vault == address(0)) revert ZeroAddress();
        if (registeredVaults[vault]) revert VaultAlreadyRegistered();

        registeredVaults[vault] = true;
        vaultList.push(vault);
        emit VaultRegistered(vault);
    }

    /// @notice Remove a broker vault
    function removeVault(address vault) external onlyGovernance {
        if (!registeredVaults[vault]) revert VaultNotRegistered();
        
        registeredVaults[vault] = false;
        
        // Remove from list
        for (uint256 i = 0; i < vaultList.length; i++) {
            if (vaultList[i] == vault) {
                vaultList[i] = vaultList[vaultList.length - 1];
                vaultList.pop();
                break;
            }
        }
        
        emit VaultRemoved(vault);
    }

    /// @notice Set minimum guarantee for a vault
    function setMinimumGuarantee(address vault, uint256 amount) external onlyGovernance {
        if (!registeredVaults[vault]) revert VaultNotRegistered();
        minimumGuarantee[vault] = amount;
        emit MinimumGuaranteeSet(vault, amount);
    }

    /// @notice Set governance address
    function setGovernance(address _governance) external onlyGovernance {
        if (_governance == address(0)) revert ZeroAddress();
        governance = _governance;
        emit GovernanceSet(_governance);
    }

    /// @notice Set settlement address
    function setSettlement(address _settlement) external onlyGovernance {
        if (_settlement == address(0)) revert ZeroAddress();
        settlement = _settlement;
        emit SettlementSet(_settlement);
    }

    /// @notice Set netting window
    function setNettingWindow(uint256 windowSeconds) external onlyGovernance {
        nettingWindowSeconds = windowSeconds;
        emit NettingWindowSet(windowSeconds);
    }

    // ──────────────────────────── Vault Functions ──────────────────

    /// @notice Deposit guarantee (required to participate in netting)
    function depositGuarantee(uint256 amount) external onlyRegisteredVault nonReentrant {
        if (amount == 0) revert ZeroAmount();
        
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        guaranteeDeposits[msg.sender] += amount;
        emit GuaranteeDeposited(msg.sender, amount);
    }

    /// @notice Withdraw guarantee (cannot go below minimum)
    function withdrawGuarantee(uint256 amount) external onlyRegisteredVault nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (guaranteeDeposits[msg.sender] < amount) revert InsufficientGuarantee();
        
        uint256 minRequired = minimumGuarantee[msg.sender];
        if (guaranteeDeposits[msg.sender] - amount < minRequired) {
            revert BelowMinimumGuarantee();
        }

        guaranteeDeposits[msg.sender] -= amount;
        usdc.safeTransfer(msg.sender, amount);
        emit GuaranteeWithdrawn(msg.sender, amount);
    }

    /// @notice Anyone can contribute to the default fund
    function depositDefaultFund(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        defaultFund += amount;
        emit DefaultFundDeposited(amount);
    }

    // ──────────────────────────── Settlement Functions ─────────────

    /// @notice Record an obligation (from keeper)
    function recordObligation(
        address fromVault,
        address toVault,
        uint256 amount,
        bytes32 refId
    ) external onlySettlement nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (!registeredVaults[fromVault] || !registeredVaults[toVault]) {
            revert VaultNotRegistered();
        }
        if (settledObligations[refId]) revert DuplicateObligation();

        settledObligations[refId] = true;
        
        pendingObligations.push(Obligation({
            fromVault: fromVault,
            toVault: toVault,
            amount: amount,
            refId: refId,
            timestamp: block.timestamp
        }));

        emit ObligationRecorded(fromVault, toVault, amount, refId);
    }

    /// @notice Execute netting — permissionless, anyone can call
    function executeNetting() external nonReentrant {
        if (block.timestamp < lastNettingTimestamp + nettingWindowSeconds) {
            revert NettingWindowNotElapsed();
        }

        if (pendingObligations.length == 0) {
            lastNettingTimestamp = block.timestamp;
            return;
        }

        uint256 grossVolume = 0;
        uint256 netVolume = 0;

        // Calculate gross volume
        for (uint256 i = 0; i < pendingObligations.length; i++) {
            grossVolume += pendingObligations[i].amount;
        }

        // Execute net transfers between each pair of vaults
        for (uint256 i = 0; i < vaultList.length; i++) {
            address vaultA = vaultList[i];
            for (uint256 j = i + 1; j < vaultList.length; j++) {
                address vaultB = vaultList[j];
                
                // Calculate net between this pair
                int256 net = 0;
                for (uint256 k = 0; k < pendingObligations.length; k++) {
                    Obligation memory ob = pendingObligations[k];
                    if (ob.fromVault == vaultA && ob.toVault == vaultB) {
                        net += int256(ob.amount);
                    } else if (ob.fromVault == vaultB && ob.toVault == vaultA) {
                        net -= int256(ob.amount);
                    }
                }
                
                if (net > 0) {
                    // vaultA owes vaultB
                    uint256 transferAmount = uint256(net);
                    netVolume += transferAmount;
                    _executeTransfer(vaultA, vaultB, transferAmount);
                } else if (net < 0) {
                    // vaultB owes vaultA
                    uint256 transferAmount = uint256(-net);
                    netVolume += transferAmount;
                    _executeTransfer(vaultB, vaultA, transferAmount);
                }
            }
        }

        uint256 savings = grossVolume > netVolume ? grossVolume - netVolume : 0;
        
        emit NettingExecuted(pendingObligations.length, grossVolume, netVolume, savings);

        // Clear pending obligations
        delete pendingObligations;
        lastNettingTimestamp = block.timestamp;
    }

    /// @notice Emergency: settle one obligation immediately (bypass netting)
    function settleImmediate(
        address fromVault,
        address toVault,
        uint256 amount,
        bytes32 refId
    ) external onlySettlement nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (!registeredVaults[fromVault] || !registeredVaults[toVault]) {
            revert VaultNotRegistered();
        }
        if (settledObligations[refId]) revert DuplicateObligation();

        settledObligations[refId] = true;
        _executeTransfer(fromVault, toVault, amount);
        
        emit ImmediateSettlement(fromVault, toVault, amount, refId);
    }

    // ──────────────────────────── View Functions ───────────────────

    /// @notice Get pending obligation count
    function pendingObligationCount() external view returns (uint256) {
        return pendingObligations.length;
    }

    /// @notice Calculate net obligation between two vaults
    function netObligation(address vaultA, address vaultB) external view returns (int256) {
        int256 net = 0;
        for (uint256 i = 0; i < pendingObligations.length; i++) {
            Obligation memory ob = pendingObligations[i];
            if (ob.fromVault == vaultA && ob.toVault == vaultB) {
                net += int256(ob.amount);
            } else if (ob.fromVault == vaultB && ob.toVault == vaultA) {
                net -= int256(ob.amount);
            }
        }
        return net;
    }

    /// @notice Total guarantee deposits across all vaults
    function totalGuaranteeDeposits() external view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < vaultList.length; i++) {
            total += guaranteeDeposits[vaultList[i]];
        }
        return total;
    }

    /// @notice Get all registered vaults
    function getVaultList() external view returns (address[] memory) {
        return vaultList;
    }

    // ──────────────────────────── Internal ─────────────────────────

    /// @notice Execute transfer from one vault to another with default waterfall
    function _executeTransfer(address fromVault, address toVault, uint256 amount) internal {
        // Try to transfer from fromVault
        try IMarginVault(fromVault).transferToClearing(amount) {
            // Success - vault sent USDC to us, now deliver to toVault
            // Approve toVault to pull the funds
            usdc.approve(toVault, amount);
            IMarginVault(toVault).receiveFromClearing(amount);
        } catch {
            // fromVault can't pay, use guarantee deposit
            uint256 fromGuarantee = guaranteeDeposits[fromVault];
            
            if (fromGuarantee >= amount) {
                // Guarantee covers it
                guaranteeDeposits[fromVault] -= amount;
                usdc.approve(toVault, amount);
                IMarginVault(toVault).receiveFromClearing(amount);
            } else {
                // Partial from guarantee, rest from default fund
                uint256 remaining = amount;
                
                if (fromGuarantee > 0) {
                    guaranteeDeposits[fromVault] = 0;
                    remaining -= fromGuarantee;
                }
                
                if (defaultFund >= remaining) {
                    defaultFund -= remaining;
                    emit DefaultFundUsed(fromVault, remaining);
                    
                    // Deliver full amount to toVault
                    usdc.approve(toVault, amount);
                    IMarginVault(toVault).receiveFromClearing(amount);
                } else {
                    // Partial settlement - deliver what we have
                    uint256 deliverable = fromGuarantee + defaultFund;
                    if (defaultFund > 0) {
                        emit DefaultFundUsed(fromVault, defaultFund);
                        defaultFund = 0;
                    }
                    
                    if (deliverable > 0) {
                        usdc.approve(toVault, deliverable);
                        IMarginVault(toVault).receiveFromClearing(deliverable);
                    }
                    
                    // Shortfall: flag for manual resolution
                    // In production, emit event for governance intervention
                }
            }
        }
    }
}
