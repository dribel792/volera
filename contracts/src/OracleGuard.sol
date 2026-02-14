// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title OracleGuard
/// @notice Validates prices from oracles (Pyth, Chainlink) with staleness checks and price bands.
///         Prevents settlement at stale or manipulated prices.
contract OracleGuard {
    
    // ──────────────────────────── Types ────────────────────────────

    enum OracleType { CHAINLINK, PYTH, CUSTOM }
    
    struct OracleConfig {
        bool exists;
        OracleType oracleType;
        address oracleAddress;          // Chainlink aggregator or Pyth address
        bytes32 pythPriceId;            // For Pyth: price feed ID
        uint256 maxStalenessSeconds;    // Max age of price (e.g., 300 = 5 min)
        uint256 priceBandBps;           // Max deviation from reference (e.g., 500 = 5%)
        uint256 referencePrice;         // Last known good price (for band checks)
        uint256 referencePriceTimestamp;
        uint8 decimals;
    }
    
    // ──────────────────────────── State ────────────────────────────

    address public admin;
    address public operator;
    
    mapping(bytes32 => OracleConfig) public oracles;  // symbolId => config
    
    // ──────────────────────────── Events ───────────────────────────

    event OracleConfigured(bytes32 indexed symbolId, OracleType oracleType, address oracleAddress);
    event ReferencePriceUpdated(bytes32 indexed symbolId, uint256 price, uint256 timestamp);
    event PriceBandUpdated(bytes32 indexed symbolId, uint256 bandBps);
    
    // ──────────────────────────── Errors ───────────────────────────

    error Unauthorized();
    error OracleNotConfigured();
    error PriceStale();
    error PriceOutsideBand();
    error InvalidPrice();
    error OracleCallFailed();
    
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

    /// @notice Get current price with validation
    /// @return price The validated price (scaled to 8 decimals)
    /// @return timestamp When the price was recorded
    function getValidatedPrice(bytes32 symbolId) external view returns (uint256 price, uint256 timestamp) {
        OracleConfig storage cfg = oracles[symbolId];
        if (!cfg.exists) revert OracleNotConfigured();
        
        (price, timestamp) = _fetchPrice(cfg);
        
        // Staleness check
        if (block.timestamp - timestamp > cfg.maxStalenessSeconds) {
            revert PriceStale();
        }
        
        // Price band check (if reference exists)
        if (cfg.referencePrice > 0) {
            uint256 deviation = _calculateDeviationBps(price, cfg.referencePrice);
            if (deviation > cfg.priceBandBps) {
                revert PriceOutsideBand();
            }
        }
        
        return (price, timestamp);
    }
    
    /// @notice Check if a price is valid without reverting
    function isPriceValid(bytes32 symbolId) external view returns (bool valid, string memory reason) {
        OracleConfig storage cfg = oracles[symbolId];
        if (!cfg.exists) return (false, "Oracle not configured");
        
        try this.getValidatedPrice(symbolId) returns (uint256, uint256) {
            return (true, "");
        } catch Error(string memory err) {
            return (false, err);
        } catch {
            return (false, "Oracle call failed");
        }
    }
    
    /// @notice Get raw price without validation (for monitoring)
    function getRawPrice(bytes32 symbolId) external view returns (uint256 price, uint256 timestamp) {
        OracleConfig storage cfg = oracles[symbolId];
        if (!cfg.exists) revert OracleNotConfigured();
        return _fetchPrice(cfg);
    }

    // ──────────────────────────── Admin Functions ──────────────────

    /// @notice Configure a Chainlink oracle for a symbol
    function configureChainlinkOracle(
        bytes32 symbolId,
        address aggregator,
        uint256 maxStalenessSeconds,
        uint256 priceBandBps,
        uint8 decimals
    ) external onlyAdmin {
        oracles[symbolId] = OracleConfig({
            exists: true,
            oracleType: OracleType.CHAINLINK,
            oracleAddress: aggregator,
            pythPriceId: bytes32(0),
            maxStalenessSeconds: maxStalenessSeconds,
            priceBandBps: priceBandBps,
            referencePrice: 0,
            referencePriceTimestamp: 0,
            decimals: decimals
        });
        
        emit OracleConfigured(symbolId, OracleType.CHAINLINK, aggregator);
    }
    
    /// @notice Configure a Pyth oracle for a symbol
    function configurePythOracle(
        bytes32 symbolId,
        address pythContract,
        bytes32 priceId,
        uint256 maxStalenessSeconds,
        uint256 priceBandBps
    ) external onlyAdmin {
        oracles[symbolId] = OracleConfig({
            exists: true,
            oracleType: OracleType.PYTH,
            oracleAddress: pythContract,
            pythPriceId: priceId,
            maxStalenessSeconds: maxStalenessSeconds,
            priceBandBps: priceBandBps,
            referencePrice: 0,
            referencePriceTimestamp: 0,
            decimals: 8  // Pyth uses 8 decimals
        });
        
        emit OracleConfigured(symbolId, OracleType.PYTH, pythContract);
    }
    
    /// @notice Update reference price (called periodically or on significant moves)
    function updateReferencePrice(bytes32 symbolId) external onlyOperator {
        OracleConfig storage cfg = oracles[symbolId];
        if (!cfg.exists) revert OracleNotConfigured();
        
        (uint256 price, uint256 timestamp) = _fetchPrice(cfg);
        if (price == 0) revert InvalidPrice();
        
        cfg.referencePrice = price;
        cfg.referencePriceTimestamp = timestamp;
        
        emit ReferencePriceUpdated(symbolId, price, timestamp);
    }
    
    /// @notice Update price band tolerance
    function setPriceBand(bytes32 symbolId, uint256 bandBps) external onlyOperator {
        if (!oracles[symbolId].exists) revert OracleNotConfigured();
        oracles[symbolId].priceBandBps = bandBps;
        emit PriceBandUpdated(symbolId, bandBps);
    }
    
    /// @notice Update max staleness
    function setMaxStaleness(bytes32 symbolId, uint256 maxSeconds) external onlyOperator {
        if (!oracles[symbolId].exists) revert OracleNotConfigured();
        oracles[symbolId].maxStalenessSeconds = maxSeconds;
    }
    
    function setOperator(address _operator) external onlyAdmin {
        operator = _operator;
    }
    
    function setAdmin(address _admin) external onlyAdmin {
        admin = _admin;
    }

    // ──────────────────────────── Internal ─────────────────────────

    function _fetchPrice(OracleConfig storage cfg) internal view returns (uint256 price, uint256 timestamp) {
        if (cfg.oracleType == OracleType.CHAINLINK) {
            return _fetchChainlinkPrice(cfg.oracleAddress, cfg.decimals);
        } else if (cfg.oracleType == OracleType.PYTH) {
            return _fetchPythPrice(cfg.oracleAddress, cfg.pythPriceId);
        }
        revert OracleCallFailed();
    }
    
    function _fetchChainlinkPrice(address aggregator, uint8 decimals) internal view returns (uint256, uint256) {
        // Chainlink AggregatorV3Interface
        (
            /* uint80 roundId */,
            int256 answer,
            /* uint256 startedAt */,
            uint256 updatedAt,
            /* uint80 answeredInRound */
        ) = IChainlinkAggregator(aggregator).latestRoundData();
        
        if (answer <= 0) revert InvalidPrice();
        
        // Normalize to 8 decimals
        uint256 price = uint256(answer);
        if (decimals < 8) {
            price = price * (10 ** (8 - decimals));
        } else if (decimals > 8) {
            price = price / (10 ** (decimals - 8));
        }
        
        return (price, updatedAt);
    }
    
    function _fetchPythPrice(address pythContract, bytes32 priceId) internal view returns (uint256, uint256) {
        IPyth pyth = IPyth(pythContract);
        IPyth.Price memory priceData = pyth.getPriceUnsafe(priceId);
        
        if (priceData.price <= 0) revert InvalidPrice();
        
        // Convert Pyth price (with expo) to 8 decimals
        int64 price = priceData.price;
        int32 expo = priceData.expo;
        
        uint256 normalizedPrice;
        if (expo >= 0) {
            normalizedPrice = uint256(uint64(price)) * (10 ** (8 + uint32(expo)));
        } else {
            uint32 absExpo = uint32(-expo);
            if (absExpo <= 8) {
                normalizedPrice = uint256(uint64(price)) * (10 ** (8 - absExpo));
            } else {
                normalizedPrice = uint256(uint64(price)) / (10 ** (absExpo - 8));
            }
        }
        
        return (normalizedPrice, priceData.publishTime);
    }
    
    function _calculateDeviationBps(uint256 price, uint256 refPrice) internal pure returns (uint256) {
        if (refPrice == 0) return 0;
        uint256 diff = price > refPrice ? price - refPrice : refPrice - price;
        return (diff * 10000) / refPrice;
    }
}

// ──────────────────────────── Interfaces ───────────────────────────

interface IChainlinkAggregator {
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}

interface IPyth {
    struct Price {
        int64 price;
        uint64 conf;
        int32 expo;
        uint256 publishTime;
    }
    
    function getPriceUnsafe(bytes32 id) external view returns (Price memory price);
}
