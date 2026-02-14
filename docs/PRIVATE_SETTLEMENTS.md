# Private Settlements — Architecture & Design

## Problem

All settlements are currently **publicly visible on-chain**:
- Settlement amounts
- User addresses (pseudonymous but traceable)
- Trade direction (win/loss)
- Timestamp

**Why this matters:**
- **Large traders** don't want competitors seeing their positions
- **Institutional clients** have regulatory privacy requirements
- **Retail users** deserve financial privacy
- **Front-running risk**: MEV bots can see large settlements and trade against them

## Design Goals

1. **Hide settlement amounts** from public view
2. **Keep user addresses pseudonymous** (already are)
3. **Maintain auditability** for regulators and users
4. **Pragmatic MVP** — not a full ZK rollup (too complex/expensive)
5. **Backwards compatible** — old settlements still work

## Proposed Solution: Commitment-Based Settlements with Encrypted Memos

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  PUBLIC ON-CHAIN                            │
│                                                             │
│  Settlement Event:                                          │
│  - user: 0x...                                              │
│  - commitmentHash: keccak256(amount + salt + refId)         │
│  - refId: bytes32                                           │
│  - encryptedMemo: encrypted(amount, direction, metadata)    │
│  - timestamp: uint256                                       │
│                                                             │
│  ❌ Amount NOT visible                                      │
│  ❌ Direction (win/loss) NOT visible                        │
│  ✅ Commitment hash IS visible (for verification)          │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│              OFF-CHAIN (User + Broker)                      │
│                                                             │
│  User receives reveal data:                                 │
│  - amount: uint256                                          │
│  - salt: bytes32                                            │
│  - refId: bytes32                                           │
│  - decryption key                                           │
│                                                             │
│  User can verify:                                           │
│  keccak256(amount, salt, refId) == commitmentHash           │
└─────────────────────────────────────────────────────────────┘
```

### How It Works

#### 1. **Commitment Phase (On-Chain)**

Broker bridge generates:
```solidity
bytes32 salt = keccak256(block.timestamp, refId, secret);
bytes32 commitment = keccak256(abi.encodePacked(amount, salt, refId));
bytes memory encryptedMemo = encryptMemo(amount, direction, user.publicKey);
```

Settlement contract stores:
```solidity
struct PrivateSettlement {
    address user;
    bytes32 commitmentHash;
    bytes32 refId;
    bytes encryptedMemo;
    uint256 timestamp;
}
```

**What's public:**
- Commitment hash (meaningless without reveal)
- Encrypted memo (encrypted with user's public key)
- User address (already pseudonymous)
- Timestamp

**What's hidden:**
- Settlement amount
- Win/loss direction

#### 2. **Reveal Phase (Off-Chain to User)**

Broker sends user (via API/websocket):
```json
{
  "refId": "0x...",
  "amount": 1500000000,
  "salt": "0x...",
  "direction": "credit",
  "decryptionKey": "user_private_key"
}
```

User verifies locally:
```javascript
const commitment = keccak256(amount, salt, refId);
assert(commitment === on_chain_commitment);

const decrypted = decrypt(encryptedMemo, userPrivateKey);
assert(decrypted.amount === amount);
```

#### 3. **Audit/Dispute (On-Demand)**

If user disputes, they can prove settlement on-chain:
```solidity
function verifySettlement(
    bytes32 refId,
    uint256 amount,
    bytes32 salt
) external view returns (bool) {
    PrivateSettlement storage s = settlements[refId];
    bytes32 computed = keccak256(abi.encodePacked(amount, salt, refId));
    return computed == s.commitmentHash;
}
```

Regulator can request reveal data from broker for compliance.

---

## Implementation Plan

### Smart Contract Changes

#### New Contract: `PrivateSettlementVault`

```solidity
contract PrivateSettlementVault {
    struct PrivateSettlement {
        address user;
        bytes32 commitmentHash;
        bytes32 refId;
        bytes encryptedMemo;
        uint256 timestamp;
        bool executed;
    }
    
    mapping(bytes32 => PrivateSettlement) public settlements;
    
    // Settlement with commitment (private amount)
    function settlePrivate(
        address user,
        bytes32 commitmentHash,
        bytes32 refId,
        bytes calldata encryptedMemo,
        bool isCredit  // true = credit PnL, false = seize collateral
    ) external onlySettlement {
        // Store commitment
        settlements[refId] = PrivateSettlement({
            user: user,
            commitmentHash: commitmentHash,
            refId: refId,
            encryptedMemo: encryptedMemo,
            timestamp: block.timestamp,
            executed: false
        });
        
        // Emit minimal event
        emit PrivateSettlementCommitted(user, refId, commitmentHash);
    }
    
    // Execute settlement (amount hidden, settled internally)
    function executePrivateSettlement(
        bytes32 refId,
        uint256 amount,
        bytes32 salt
    ) external onlySettlement {
        PrivateSettlement storage s = settlements[refId];
        require(!s.executed, "Already executed");
        
        // Verify commitment
        bytes32 computed = keccak256(abi.encodePacked(amount, salt, refId));
        require(computed == s.commitmentHash, "Invalid reveal");
        
        // Execute actual settlement (update balances)
        // ... (standard settlement logic)
        
        s.executed = true;
        emit PrivateSettlementExecuted(refId);
    }
    
    // User verification (doesn't reveal amount publicly)
    function verifySettlement(
        bytes32 refId,
        uint256 amount,
        bytes32 salt
    ) external view returns (bool valid) {
        PrivateSettlement storage s = settlements[refId];
        bytes32 computed = keccak256(abi.encodePacked(amount, salt, refId));
        return computed == s.commitmentHash;
    }
}
```

### Bridge Service Changes

```typescript
async function settlePrivate(settlement: Settlement): Promise<void> {
  const { refId, wallet, pnl_usdc } = settlement;
  
  // Generate commitment
  const salt = keccak256(encodePacked(['bytes32', 'uint256'], [refId, Date.now()]));
  const commitment = keccak256(encodePacked(
    ['uint256', 'bytes32', 'bytes32'],
    [Math.abs(pnl_usdc), salt, refId]
  ));
  
  // Encrypt memo with user's public key
  const userPublicKey = await getUserPublicKey(wallet);
  const memo = {
    amount: Math.abs(pnl_usdc),
    direction: pnl_usdc > 0 ? 'credit' : 'debit',
    refId,
    timestamp: Date.now()
  };
  const encryptedMemo = encrypt(JSON.stringify(memo), userPublicKey);
  
  // Submit commitment
  const tx = await vault.settlePrivate(
    wallet,
    commitment,
    refId,
    encryptedMemo,
    pnl_usdc > 0  // isCredit
  );
  
  // Send reveal data to user off-chain (API, websocket, encrypted email)
  await sendRevealToUser(wallet, {
    refId,
    amount: Math.abs(pnl_usdc),
    salt,
    direction: pnl_usdc > 0 ? 'credit' : 'debit'
  });
  
  // Execute settlement (in same tx or later)
  await vault.executePrivateSettlement(refId, Math.abs(pnl_usdc), salt);
}
```

### Frontend Changes

```typescript
// User dashboard shows private settlements
const { commitment } = usePrivateSettlement(refId);

// User verifies locally
const verified = await contract.verifySettlement(refId, amount, salt);
if (verified) {
  // Show settlement in user's private view
  setSettlements(prev => [...prev, { refId, amount, verified: true }]);
}
```

---

## Security Considerations

### 1. **Salt Randomness**

Salt must be unpredictable. Use:
```solidity
bytes32 salt = keccak256(abi.encodePacked(
    block.timestamp,
    block.difficulty,
    refId,
    msg.sender,
    SECRET_FROM_ENV
));
```

### 2. **Encryption Key Management**

- **User public keys** stored off-chain (in user profile or derived from wallet)
- **User private keys** never leave user's device
- Fallback: if user loses key, broker can provide reveal data via KYC'd support channel

### 3. **MEV Protection**

**Important caveat:** The `executePrivateSettlement` call passes the plaintext `amount` as calldata, which is visible in the mempool before inclusion. To get true MEV protection:
- Use Flashbots/private mempool for execution transactions
- Or batch multiple executions together (combine with batch settlements)
- The commit-reveal split alone does NOT hide amounts from MEV searchers who watch pending txs

The privacy benefit is primarily **post-settlement** — once confirmed, observers see only the commitment hash, not the amount.

### 4. **Regulatory Compliance**

- Broker retains full plaintext records
- Regulator can request reveal data from broker
- User can always prove their settlement on-chain (with reveal)

---

## Trade-offs

### ✅ Pros
- **Privacy**: Settlement amounts hidden from public
- **Pragmatic**: No ZK circuits, no complex cryptography
- **Backwards compatible**: Existing settlements still work
- **Auditable**: Users and regulators can verify

### ❌ Cons
- **Two-step process**: Commitment then execution (adds latency)
- **Gas cost**: Slightly higher (extra hash + encrypted memo storage)
- **Trust in broker**: Broker must send reveal data (but user can verify on-chain)

---

## Alternatives Considered

### 1. **Full ZK Rollup**
- **Pros**: Maximum privacy, batch settlements, low gas
- **Cons**: Complex, expensive to build, high latency, overkill for MVP

### 2. **Private Settlement Pools**
- **Pros**: Amounts hidden in batched pools
- **Cons**: Still reveals participation, timing, harder to audit

### 3. **Encrypted Memos Only (No Commitment)**
- **Pros**: Simpler
- **Cons**: No on-chain verification, trust broker completely

---

## Next Steps

1. **Build prototype contract**: `PrivateSettlementVault.sol`
2. **Update bridge**: Add commitment generation
3. **Frontend**: Private settlement verification UI
4. **Testing**: Security audit for commitment scheme
5. **Deploy**: Separate private vault or extend existing vault

---

## Gas Cost Analysis

| Operation | Current | With Privacy | Delta |
|-----------|---------|--------------|-------|
| Settlement | ~50k gas | ~75k gas | +50% |
| Verification | N/A | ~10k gas | New |

Extra cost: ~$0.001 per settlement at current Base gas prices.

---

## Conclusion

**Commitment-based settlements with encrypted memos** provide a pragmatic privacy layer:
- Hides settlement amounts from public view
- Maintains on-chain verifiability
- No complex ZK circuits
- Backwards compatible

Recommended for **Phase 2** after MVP audit.
