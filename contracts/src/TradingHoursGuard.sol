// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title TradingHoursGuard
/// @notice Enforces trading hours, market halts, and earnings blackouts per symbol.
///         Used by settlement to reject or delay settlements outside valid windows.
contract TradingHoursGuard {
    
    // ──────────────────────────── State ────────────────────────────

    address public admin;
    address public operator; // Can update hours/halts without timelock
    
    /// @notice Symbol trading configuration
    struct SymbolConfig {
        bool exists;
        bool halted;                    // Manual halt (corporate action, circuit breaker)
        uint8 marketOpenHourUTC;        // e.g., 14 for NYSE (9:30 AM ET = 14:30 UTC)
        uint8 marketOpenMinuteUTC;
        uint8 marketCloseHourUTC;       // e.g., 21 for NYSE (4:00 PM ET = 21:00 UTC)
        uint8 marketCloseMinuteUTC;
        uint8 tradingDays;              // Bitmask: bit 0 = Sunday, bit 1 = Monday, etc.
        uint256 earningsBlackoutStart;  // Unix timestamp (0 = no blackout)
        uint256 earningsBlackoutEnd;
    }
    
    mapping(bytes32 => SymbolConfig) public symbols;
    
    /// @notice Global halt - stops ALL trading
    bool public globalHalt;
    
    // ──────────────────────────── Events ───────────────────────────

    event SymbolConfigured(bytes32 indexed symbolId, uint8 openHour, uint8 closeHour, uint8 tradingDays);
    event SymbolHalted(bytes32 indexed symbolId, bool halted, string reason);
    event EarningsBlackoutSet(bytes32 indexed symbolId, uint256 start, uint256 end);
    event GlobalHaltSet(bool halted, string reason);
    
    // ──────────────────────────── Errors ───────────────────────────

    error Unauthorized();
    error SymbolNotConfigured();
    error MarketClosed();
    error SymbolHaltedError();
    error EarningsBlackout();
    error GlobalHaltActive();
    
    // ──────────────────────────── Modifiers ────────────────────────

    modifier onlyAdmin() {
        if (msg.sender != admin) revert Unauthorized();
        _;
    }
    
    modifier onlyOperator() {
        if (msg.sender != operator && msg.sender != admin) revert Unauthorized();
        _;
    }

    // ──────────────────────────── Constructor ──────────────────────

    constructor(address _admin, address _operator) {
        admin = _admin;
        operator = _operator;
    }

    // ──────────────────────────── View Functions ───────────────────

    /// @notice Check if trading is allowed for a symbol right now
    /// @return allowed True if trading allowed
    /// @return reason Revert reason if not allowed (empty if allowed)
    function canTrade(bytes32 symbolId) external view returns (bool allowed, string memory reason) {
        if (globalHalt) return (false, "Global halt active");
        
        SymbolConfig storage cfg = symbols[symbolId];
        if (!cfg.exists) return (false, "Symbol not configured");
        if (cfg.halted) return (false, "Symbol halted");
        
        // Check earnings blackout
        if (cfg.earningsBlackoutStart > 0 && 
            block.timestamp >= cfg.earningsBlackoutStart && 
            block.timestamp <= cfg.earningsBlackoutEnd) {
            return (false, "Earnings blackout");
        }
        
        // Check trading hours
        if (!_isWithinTradingHours(cfg)) {
            return (false, "Market closed");
        }
        
        return (true, "");
    }
    
    /// @notice Revert if trading not allowed (for use in modifiers)
    function requireCanTrade(bytes32 symbolId) external view {
        if (globalHalt) revert GlobalHaltActive();
        
        SymbolConfig storage cfg = symbols[symbolId];
        if (!cfg.exists) revert SymbolNotConfigured();
        if (cfg.halted) revert SymbolHaltedError();
        
        if (cfg.earningsBlackoutStart > 0 && 
            block.timestamp >= cfg.earningsBlackoutStart && 
            block.timestamp <= cfg.earningsBlackoutEnd) {
            revert EarningsBlackout();
        }
        
        if (!_isWithinTradingHours(cfg)) {
            revert MarketClosed();
        }
    }

    // ──────────────────────────── Admin Functions ──────────────────

    /// @notice Configure a symbol's trading hours
    /// @param symbolId Keccak256 hash of symbol string (e.g., keccak256("AAPL"))
    /// @param openHour Market open hour UTC (0-23)
    /// @param openMinute Market open minute UTC (0-59)
    /// @param closeHour Market close hour UTC (0-23)
    /// @param closeMinute Market close minute UTC (0-59)
    /// @param tradingDays Bitmask of trading days (bit 1 = Mon, bit 5 = Fri for US stocks)
    function configureSymbol(
        bytes32 symbolId,
        uint8 openHour,
        uint8 openMinute,
        uint8 closeHour,
        uint8 closeMinute,
        uint8 tradingDays
    ) external onlyAdmin {
        symbols[symbolId] = SymbolConfig({
            exists: true,
            halted: false,
            marketOpenHourUTC: openHour,
            marketOpenMinuteUTC: openMinute,
            marketCloseHourUTC: closeHour,
            marketCloseMinuteUTC: closeMinute,
            tradingDays: tradingDays,
            earningsBlackoutStart: 0,
            earningsBlackoutEnd: 0
        });
        
        emit SymbolConfigured(symbolId, openHour, closeHour, tradingDays);
    }
    
    /// @notice Halt/unhalt a specific symbol
    function setSymbolHalt(bytes32 symbolId, bool halted, string calldata reason) external onlyOperator {
        if (!symbols[symbolId].exists) revert SymbolNotConfigured();
        symbols[symbolId].halted = halted;
        emit SymbolHalted(symbolId, halted, reason);
    }
    
    /// @notice Set earnings blackout window for a symbol
    function setEarningsBlackout(bytes32 symbolId, uint256 start, uint256 end) external onlyOperator {
        if (!symbols[symbolId].exists) revert SymbolNotConfigured();
        symbols[symbolId].earningsBlackoutStart = start;
        symbols[symbolId].earningsBlackoutEnd = end;
        emit EarningsBlackoutSet(symbolId, start, end);
    }
    
    /// @notice Set global halt (emergency)
    function setGlobalHalt(bool halted, string calldata reason) external onlyOperator {
        globalHalt = halted;
        emit GlobalHaltSet(halted, reason);
    }
    
    function setOperator(address _operator) external onlyAdmin {
        operator = _operator;
    }
    
    function setAdmin(address _admin) external onlyAdmin {
        admin = _admin;
    }

    // ──────────────────────────── Internal ─────────────────────────

    function _isWithinTradingHours(SymbolConfig storage cfg) internal view returns (bool) {
        // Get current day of week (0 = Sunday, 1 = Monday, ...)
        uint256 dayOfWeek = (block.timestamp / 1 days + 4) % 7; // Jan 1, 1970 was Thursday (4)
        
        // Check if today is a trading day
        if ((cfg.tradingDays & (1 << dayOfWeek)) == 0) {
            return false;
        }
        
        // Get current hour and minute UTC
        uint256 secondsIntoDay = block.timestamp % 1 days;
        uint256 currentMinutes = secondsIntoDay / 60;
        
        uint256 openMinutes = uint256(cfg.marketOpenHourUTC) * 60 + cfg.marketOpenMinuteUTC;
        uint256 closeMinutes = uint256(cfg.marketCloseHourUTC) * 60 + cfg.marketCloseMinuteUTC;
        
        return currentMinutes >= openMinutes && currentMinutes < closeMinutes;
    }
}
