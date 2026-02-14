# Batch Settlements — Architecture & Design

## Problem

Current settlement is **trade-by-trade** (one transaction per settlement):
- **Expensive**: $0.001-0.01 gas per tx × thousands of trades = $$$ 
- **Slow**: Mempool delays, 2s block time
- **Doesn't scale**: HFT traders make 1000+ trades/day
- **Bad UX**: Users wait for individual tx confirmations

**Example:**
- HFT trader makes 500 trades in 1 hour
- Current: 500 separate transactions = $5-50 in gas
- **Batch**: 1 transaction every 5 minutes = ~$0.10 total

---

## Design Goals

1. **Net settlements** over a time window (e.g., 5 minutes)
2. **Single transaction** per batch per user
3. **Integrity guarantee**: Provable that batch == sum of individual trades
4. **Backwards compatible**: Non-HFT users can still settle trade-by-trade
5. **Low gas**: Target <100k gas per batch (vs 50k × N trades)

---

## Proposed Solution: Off-Chain Netting with Merkle Proof

### Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                  BROKER / OFF-CHAIN                          │
│                                                              │
│  Window: 14:00:00 - 14:05:00                                 │
│                                                              │
│  User A settlements:                                         │
│  - trade1: +$100                                             │
│  - trade2: -$50                                              │
│  - trade3: +$200                                             │
│  - trade4: -$30                                              │
│  NET: +$220                                                  │
│                                                              │
│  User B settlements:                                         │
│  - trade1: -$150                                             │
│  - trade2: +$80                                              │
│  NET: -$70                                                   │
│                                                              │
│  Build Merkle Tree:                                          │
│  - Leaf(A) = hash(userA, +220, nonce)                        │
│  - Leaf(B) = hash(userB, -70, nonce)                         │
│  - Root = hash(Leaf(A), Leaf(B))                             │
│                                                              │
│  Submit to chain: BatchSettlement(root, window, userCount)   │
└──────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────────┐
│                    ON-CHAIN                                  │
│                                                              │
│  Contract stores:                                            │
│  - batchId: keccak256(window_start, window_end)             │
│  - merkleRoot: bytes32                                       │
│  - userCount: uint16                                         │
│  - executed: mapping(address => bool)                        │
│                                                              │
│  User claims settlement:                                     │
│  claimBatchSettlement(                                       │
│    batchId,                                                  │
│    amount,         // net amount                             │
│    merkleProof     // proof user is in batch                 │
│  )                                                           │
│                                                              │
│  Contract verifies:                                          │
│  1. Merkle proof valid                                       │
│  2. User hasn't claimed yet                                  │
│  3. Execute settlement (credit/seize)                        │
└──────────────────────────────────────────────────────────────┘
```

### How It Works

#### 1. **Off-Chain Netting (Bridge Service)**

Every 5 minutes, bridge:
1. Fetches all settlements in window
2. Nets settlements per user
3. Builds Merkle tree of netted settlements
4. Submits root to chain

```typescript
interface NettedSettlement {
  user: address;
  netAmount: int256;  // positive = credit, negative = seize
  nonce: bytes32;     // window identifier
}

async function netSettlements(windowStart: number, windowEnd: number) {
  const settlements = await fetchSettlements(windowStart, windowEnd);
  
  // Group by user and net
  const netted = settlements.reduce((acc, s) => {
    if (!acc[s.wallet]) acc[s.wallet] = 0;
    acc[s.wallet] += s.pnl_usdc;
    return acc;
  }, {});
  
  // Build Merkle tree
  const leaves = Object.entries(netted).map(([user, amount]) => ({
    user,
    netAmount: amount,
    nonce: keccak256(encodePacked(['uint256', 'uint256'], [windowStart, windowEnd]))
  }));
  
  const tree = new MerkleTree(
    leaves.map(l => keccak256(encodePacked(['address', 'int256', 'bytes32'], [l.user, l.netAmount, l.nonce])))
  );
  
  // Submit root on-chain
  await vault.submitBatch(
    tree.getRoot(),
    windowStart,
    windowEnd,
    leaves.length
  );
  
  // Store leaves + proofs in DB for users to claim
  for (const leaf of leaves) {
    const proof = tree.getProof(leaf);
    await db.storeBatchClaim(windowStart, leaf.user, leaf.netAmount, proof);
  }
}
```

#### 2. **On-Chain Verification**

Contract:
```solidity
contract BatchSettlementVault {
    struct Batch {
        bytes32 merkleRoot;
        uint256 windowStart;
        uint256 windowEnd;
        uint16 userCount;
        uint16 claimedCount;
        bool finalized;
    }
    
    mapping(bytes32 => Batch) public batches;
    mapping(bytes32 => mapping(address => bool)) public claimed;
    
    function submitBatch(
        bytes32 merkleRoot,
        uint256 windowStart,
        uint256 windowEnd,
        uint16 userCount
    ) external onlySettlement {
        bytes32 batchId = keccak256(abi.encodePacked(windowStart, windowEnd));
        require(batches[batchId].merkleRoot == bytes32(0), "Batch exists");
        
        batches[batchId] = Batch({
            merkleRoot: merkleRoot,
            windowStart: windowStart,
            windowEnd: windowEnd,
            userCount: userCount,
            claimedCount: 0,
            finalized: false
        });
        
        emit BatchSubmitted(batchId, merkleRoot, userCount);
    }
    
    function claimBatchSettlement(
        bytes32 batchId,
        int256 netAmount,
        bytes32[] calldata merkleProof
    ) external nonReentrant {
        Batch storage batch = batches[batchId];
        require(batch.merkleRoot != bytes32(0), "Batch not found");
        require(!claimed[batchId][msg.sender], "Already claimed");
        
        // Verify Merkle proof
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, netAmount, batchId));
        require(MerkleProof.verify(merkleProof, batch.merkleRoot, leaf), "Invalid proof");
        
        // Mark claimed
        claimed[batchId][msg.sender] = true;
        batch.claimedCount++;
        
        // Execute settlement
        if (netAmount > 0) {
            // Credit PnL
            uint256 amount = uint256(netAmount);
            require(brokerPool >= amount, "Insufficient pool");
            brokerPool -= amount;
            pnl[msg.sender] += amount;
            emit PnLCredited(msg.sender, amount, batchId);
        } else if (netAmount < 0) {
            // Seize collateral
            uint256 amount = uint256(-netAmount);
            require(collateral[msg.sender] >= amount, "Insufficient collateral");
            collateral[msg.sender] -= amount;
            brokerPool += amount;
            emit CollateralSeized(msg.sender, amount, batchId);
        }
        // netAmount == 0: no-op (user broke even)
    }
    
    // Finalize batch (marks it immutable)
    function finalizeBatch(bytes32 batchId) external onlySettlement {
        Batch storage batch = batches[batchId];
        require(!batch.finalized, "Already finalized");
        batch.finalized = true;
        emit BatchFinalized(batchId, batch.claimedCount, batch.userCount);
    }
}
```

#### 3. **User Claims Settlement**

Frontend:
```typescript
async function claimBatchSettlement(batchId: string) {
  // Fetch user's claim data from API
  const { netAmount, merkleProof } = await api.getBatchClaim(batchId, userAddress);
  
  // Submit claim
  const tx = await vault.claimBatchSettlement(batchId, netAmount, merkleProof);
  await tx.wait();
  
  console.log(`Claimed ${netAmount > 0 ? '+' : ''}${netAmount} USDC from batch ${batchId}`);
}
```

---

## Gas Cost Analysis

### Current (Trade-by-Trade)

| Scenario | Trades | Gas per Tx | Total Gas | Cost @ $0.02/100k |
|----------|--------|------------|-----------|-------------------|
| HFT trader | 500/day | 50k | 25M | **$5.00** |
| Active trader | 50/day | 50k | 2.5M | $0.50 |

### Batch Settlement

| Scenario | Batches/day | Gas per batch | Total Gas | Cost |
|----------|-------------|---------------|-----------|------|
| HFT trader | 12 (every 2h) | 80k | 960k | **$0.19** (-96%) |
| Active trader | 4 (every 6h) | 80k | 320k | $0.06 (-88%) |

**Savings: 88-96% for active traders**

---

## Features

### 1. **Flexible Windows**

Batch windows configurable per user tier:
- **HFT tier**: 5-minute windows (12/hour)
- **Active tier**: 1-hour windows (24/day)
- **Standard tier**: Trade-by-trade (no batching)

### 2. **Automatic Netting**

Bridge automatically nets:
```
+100, -50, +200, -30, +75 → +295 (single settlement)
```

User sees:
- Individual trades in UI
- Single net settlement on-chain
- Full audit trail off-chain

### 3. **Lazy Claiming**

Users don't have to claim immediately:
- Batch submitted with Merkle root
- Users claim when convenient (within 7 days)
- Unclaimed settlements roll into next batch

### 4. **Dispute Resolution**

User disputes batch:
```typescript
// User: "I should have +$500, not +$300"
// Broker provides proof of individual trades that sum to +$300
const trades = [
  { refId: "0x...", amount: +100, timestamp: ... },
  { refId: "0x...", amount: +200, timestamp: ... },
  // Sum = +300
];

// User verifies off-chain
const sum = trades.reduce((acc, t) => acc + t.amount, 0);
assert(sum === 300);  // Dispute resolved
```

---

## Edge Cases

### 1. **User Has No Net Settlement**

If user's trades perfectly net to 0:
- **Option A**: Skip user from batch (save gas)
- **Option B**: Include with netAmount = 0 (for audit completeness)

Recommended: **Option A** (skip)

### 2. **Batch Submission Fails**

If Merkle root submission reverts:
- Fall back to individual settlements
- Retry batch in next window

### 3. **User Doesn't Claim**

If user doesn't claim within 7 days:
- Settlement remains available (Merkle proof still valid)
- Optional: Auto-claim on user's next action
- Optional: Roll into next batch

---

## Migration Path

### Phase 1: Opt-In Batching
- Deploy `BatchSettlementVault` alongside existing `UnifiedAccountVault`
- Users opt-in to batching
- HFT users migrate first (biggest benefit)

### Phase 2: Default Batching
- New users default to batching
- Existing users prompted to migrate
- Keep individual settlement as fallback

### Phase 3: Batch-Only
- Deprecate individual settlements (except for disputes)
- All users on batching

---

## Implementation Checklist

### Smart Contracts
- [ ] `BatchSettlementVault.sol` — batch submission + claiming
- [ ] OpenZeppelin `MerkleProof` library integration
- [ ] Events: `BatchSubmitted`, `SettlementClaimed`, `BatchFinalized`
- [ ] Access control: settlement role can submit batches
- [ ] Tests: Merkle proof verification, netting, edge cases

### Bridge Service
- [ ] Netting engine: group settlements by window, sum per user
- [ ] Merkle tree builder
- [ ] Batch submitter (scheduled job every N minutes)
- [ ] Proof storage: DB table for user claims
- [ ] API endpoint: `GET /batches/:batchId/claim/:userAddress`

### Frontend
- [ ] Batch claim UI: "You have $500 to claim from batch xyz"
- [ ] Pending batches list
- [ ] Auto-claim on page load (optional)
- [ ] Settlement history: show individual trades + batched settlement

### DevOps
- [ ] Monitoring: batch submission success rate
- [ ] Alerts: batch failure, unclaimed settlements > 24h
- [ ] Reconciliation: verify batch root matches off-chain netting

---

## Security Considerations

### 1. **Merkle Tree Integrity**

- Use standardized Merkle tree library (OpenZeppelin)
- Leaf format: `keccak256(user, netAmount, nonce)`
- Nonce prevents replay across batches

### 2. **Double-Claim Prevention**

```solidity
mapping(bytes32 => mapping(address => bool)) public claimed;
require(!claimed[batchId][msg.sender], "Already claimed");
claimed[batchId][msg.sender] = true;
```

### 3. **Netting Correctness**

Bridge must:
- Store all individual settlements in DB
- Audit trail: batch netAmount = sum(individual settlements)
- Reconciliation: verify on-chain claims match off-chain netting

### 4. **Fallback to Individual Settlement**

If batching fails:
- Bridge falls back to individual `creditPnl` / `seizeCollateral`
- No user funds stuck

---

## Alternatives Considered

### 1. **ZK Rollup**
- **Pros**: Maximum gas savings, max throughput
- **Cons**: Complex, expensive, not needed for current volume

### 2. **Optimistic Rollup**
- **Pros**: Simpler than ZK
- **Cons**: 7-day withdrawal delay, still complex

### 3. **State Channels**
- **Pros**: Instant, free settlements
- **Cons**: Requires user interaction, liquidity locking

---

## Conclusion

**Off-chain netting with Merkle proofs** provides:
- **88-96% gas savings** for active traders
- **Simple implementation** (no rollups, no ZK)
- **Backwards compatible** (opt-in, fallback to individual)
- **Auditable** (Merkle proofs provable on-chain)

Recommended for **Phase 2** after MVP, targeting HFT users.

---

## Next Steps

1. **Prototype** `BatchSettlementVault.sol`
2. **Build netting engine** in bridge service
3. **Test** with simulated HFT load (1000 trades/min)
4. **Audit** Merkle tree implementation
5. **Deploy** to testnet, onboard HFT pilot user
