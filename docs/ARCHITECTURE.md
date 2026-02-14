# Volera Settlement - Architecture

## Overview

Instant settlement infrastructure for crypto trading platforms. Users deposit USDC collateral on-chain; realized PnL from broker trades settles to their wallet in seconds.

**Chain:** Base (L2)
**Currency:** USDC
**Scope:** MVP

---

## System Components

```
┌─────────────────────────────────────────────────────────────────┐
│                         FRONTEND                                │
│  (React dashboard: balances, settlement history, recon status)  │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                          API SERVICE                            │
│  REST endpoints for frontend + ops                              │
│  - GET /users/:addr/balances                                    │
│  - GET /settlements                                             │
│  - GET /recon/status                                            │
│  - POST /admin/pause                                            │
└─────────────────────────────────────────────────────────────────┘
                                │
                ┌───────────────┼───────────────┐
                ▼               ▼               ▼
┌───────────────────┐ ┌─────────────────┐ ┌─────────────────────┐
│   BROKER BRIDGE   │ │    INDEXER      │ │   RECON SERVICE     │
│                   │ │                 │ │                     │
│ - Poll mock broker│ │ - Listen events │ │ - Compare broker    │
│ - Dedupe by refId │ │ - Store state   │ │   vs on-chain       │
│ - Call contracts  │ │ - Query API     │ │ - Flag breaks       │
└───────────────────┘ └─────────────────┘ └─────────────────────┘
        │                     │                     │
        └──────────┬──────────┴─────────────────────┘
                   ▼
┌─────────────────────────────────────────────────────────────────┐
│                    BASE L2 (ON-CHAIN)                           │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              UnifiedAccountVault.sol                    │    │
│  │                                                         │    │
│  │  Per-user sub-ledgers:                                  │    │
│  │  - collateral (seizable on losses)                      │    │
│  │  - pnl (winnings, never seizable)                       │    │
│  │                                                         │    │
│  │  Broker pool:                                           │    │
│  │  - brokerBalance (pays winners, receives seized funds)  │    │
│  │                                                         │    │
│  │  Functions:                                             │    │
│  │  - depositCollateral / withdrawCollateral               │    │
│  │  - withdrawPnL                                          │    │
│  │  - creditPnl (settlement role)                          │    │
│  │  - seizeCollateral (settlement role)                    │    │
│  │  - brokerDeposit / brokerWithdraw                       │    │
│  │  - pause / unpause (admin)                              │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                    MockUSDC.sol                         │    │
│  │  (Testnet only - mintable ERC20)                        │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

---

## Data Flow

### 1. User Deposits Collateral
```
User Wallet → depositCollateral(amt) → Vault
                                        └→ user.collateral += amt
                                        └→ emit CollateralDeposited
```

### 2. User Wins Trade (Positive PnL)
```
Mock Broker → realizes +$100 for user
     │
     ▼
Broker Bridge polls → sees settlement {user, +100, refId}
     │
     ▼
Bridge calls creditPnl(user, 100, refId)
     │
     ▼
Vault: brokerBalance -= 100
       user.pnl += 100
       emit PnLCredited
     │
     ▼
User can now withdrawPnL(100) → funds to wallet
```

### 3. User Loses Trade (Negative PnL)
```
Mock Broker → realizes -$50 for user
     │
     ▼
Broker Bridge polls → sees settlement {user, -50, refId}
     │
     ▼
Bridge calls seizeCollateral(user, 50)
     │
     ▼
Vault: user.collateral -= 50
       brokerBalance += 50
       emit CollateralSeized
```

---

## Key Invariants

1. **pnl balance never decreases** except by user withdrawal
2. **collateral never increases** except by user deposit
3. **Seize cannot touch pnl** — only collateral
4. **Credit cannot touch collateral** — only pnl
5. **Sum of all balances == contract USDC balance**
6. **refId is idempotent** — same refId settles only once

---

## Security Model

### Roles
| Role | Can Do | Controlled By |
|------|--------|---------------|
| User | deposit/withdraw own funds | User wallet |
| Settlement | creditPnl, seizeCollateral | Bridge service wallet |
| Broker | brokerDeposit, brokerWithdraw | Broker wallet |
| Admin | pause, unpause, setCaps | Max (for MVP) |

### Caps & Limits (MVP)
- Per-user daily withdrawal cap: configurable
- Global daily cap: configurable
- Pause circuit: stops all settlements

---

## Tech Stack

| Component | Technology |
|-----------|------------|
| Contracts | Solidity 0.8.x, Foundry |
| Services | TypeScript, Node.js |
| Database | SQLite (MVP) → Postgres later |
| Frontend | Next.js, wagmi, viem |
| Chain | Base Sepolia (testnet) → Base Mainnet |

---

## File Structure

```
volera-settlement/
├── contracts/
│   ├── src/
│   │   ├── UnifiedAccountVault.sol
│   │   └── MockUSDC.sol
│   ├── test/
│   │   └── UnifiedAccountVault.t.sol
│   ├── scripts/
│   │   └── Deploy.s.sol
│   └── foundry.toml
├── services/
│   ├── broker-bridge/
│   │   ├── src/
│   │   │   ├── index.ts
│   │   │   ├── bridge.ts
│   │   │   └── mock-broker.ts
│   │   └── package.json
│   ├── indexer/
│   │   ├── src/
│   │   │   ├── index.ts
│   │   │   └── listener.ts
│   │   └── package.json
│   └── api/
│       ├── src/
│       │   ├── index.ts
│       │   └── routes/
│       └── package.json
├── frontend/
│   ├── src/
│   │   ├── app/
│   │   └── components/
│   └── package.json
├── docs/
│   ├── ARCHITECTURE.md
│   └── FLOWS.md
└── tickets/
    └── *.md
```

---

## Phase 2 Features (In Design)

### Private Settlements
**Problem:** All settlement amounts visible on-chain (privacy concern for large traders)
**Solution:** Commitment-based settlements with encrypted memos
**Status:** Architecture complete → `docs/PRIVATE_SETTLEMENTS.md`

### Batch Settlements
**Problem:** HFT traders pay gas per trade (expensive, slow)
**Solution:** Off-chain netting with Merkle proofs (one tx per batch)
**Status:** Architecture complete → `docs/BATCH_SETTLEMENTS.md`
**Savings:** 88-96% gas reduction for active traders

### Multi-Collateral Support
**Problem:** Only USDC accepted; users want ETH, WBTC collateral
**Solution:** Oracle-based margin with LTV ratios + liquidations
**Status:** Architecture complete → `docs/MULTI_COLLATERAL.md`

### Prime Layer (Cross-Venue Trading)
**Problem:** Liquidity fragmented across venues
**Solution:** Single deposit → trade on multiple venues with cross-venue netting
**Status:** Full architecture → `docs/PRIME_ARCHITECTURE.md`
**Benefit:** 60%+ margin savings via position netting

---

## Deployment

### Testnet (Base Sepolia)
1. Deploy MockUSDC
2. Deploy UnifiedAccountVault(mockUSDC, admin, settlement, broker)
3. Mint test USDC to users
4. Fund broker pool
5. Start services

### Mainnet (later)
1. Use real USDC (0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913 on Base)
2. Deploy UnifiedAccountVault with production roles
3. Audit before launch

---

## Environment Variables

```bash
# Chain
RPC_URL=https://sepolia.base.org
CHAIN_ID=84532

# Contracts
VAULT_ADDRESS=0x...
USDC_ADDRESS=0x...

# Wallets (private keys - NEVER commit)
DEPLOYER_PRIVATE_KEY=
SETTLEMENT_PRIVATE_KEY=
BROKER_PRIVATE_KEY=

# Services
API_PORT=3001
BRIDGE_POLL_INTERVAL_MS=5000
```
