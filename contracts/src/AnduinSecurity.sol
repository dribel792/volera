// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title AnduinSecurity
/// @notice ERC20 security token with mint/burn capabilities for tokenized securities.
///         Each instance represents one security (e.g., vAAPL, vTSLA, vGOLD).
contract AnduinSecurity is ERC20, ERC20Burnable, AccessControl {
    
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    
    /// @notice Security metadata
    string public securitySymbol;    // e.g., "AAPL"
    string public securityName;      // e.g., "Apple Inc."
    string public isin;              // ISIN code if applicable
    address public issuer;           // Issuing entity address
    
    /// @notice Token decimals (usually 8 for securities to match share fractions)
    uint8 private immutable _decimals;

    // ──────────────────────────── Events ───────────────────────────

    event SecurityMinted(address indexed to, uint256 amount);
    event SecurityBurned(address indexed from, uint256 amount);

    // ──────────────────────────── Constructor ──────────────────────

    constructor(
        string memory tokenName,
        string memory tokenSymbol,
        string memory _securitySymbol,
        string memory _securityName,
        string memory _isin,
        address _issuer,
        address admin,
        address minter,
        uint8 decimals_
    ) ERC20(tokenName, tokenSymbol) {
        securitySymbol = _securitySymbol;
        securityName = _securityName;
        isin = _isin;
        issuer = _issuer;
        _decimals = decimals_;
        
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, minter);
        _grantRole(BURNER_ROLE, minter);  // Same role can burn
    }

    // ──────────────────────────── ERC20 Overrides ──────────────────

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    // ──────────────────────────── Minting ──────────────────────────

    /// @notice Mint new security tokens (only minter role)
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
        emit SecurityMinted(to, amount);
    }

    // ──────────────────────────── Burning ──────────────────────────

    /// @notice Burn security tokens (only burner role or token holder)
    function burn(uint256 amount) public virtual override {
        // Allow either the holder or a burner role to burn
        if (!hasRole(BURNER_ROLE, _msgSender())) {
            // If not burner role, must be burning own tokens
            require(balanceOf(_msgSender()) >= amount, "Insufficient balance");
        }
        _burn(_msgSender(), amount);
        emit SecurityBurned(_msgSender(), amount);
    }

    /// @notice Burn from another address (for settlement vault)
    function burnFrom(address account, uint256 amount) public virtual override {
        if (!hasRole(BURNER_ROLE, _msgSender())) {
            _spendAllowance(account, _msgSender(), amount);
        }
        _burn(account, amount);
        emit SecurityBurned(account, amount);
    }

    // ──────────────────────────── Admin ────────────────────────────

    function setIssuer(address _issuer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        issuer = _issuer;
    }

    function setIsin(string calldata _isin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        isin = _isin;
    }
}
