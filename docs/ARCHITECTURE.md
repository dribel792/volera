# Anduin Architecture

## Overview

Anduin is instant on-chain settlement infrastructure for crypto exchanges and brokers. The core product is **single-venue settlement**: users deposit USDC into a self-governed smart contract (MarginVault), trade on a venue, and their PnL settles instantly on-chain. No custodian, no delays, no trust required.

Cross-venue portfolio margin is an **additional feature** that can be layered on top once multiple venues are operating with Anduin settlement.

**Core Principle:** Venues maintain their existing margin engines and liquidation systems. Anduin provides instant settlement infrastructure and insurance coverage for shortfalls.

---

## Core Product: Single-Venue Settlement (V2)

This is what venues onboard with. This is what we sell first.

### Architecture

Each venue gets its own **MarginVault** contract:

```
┌──────────┐         ┌──────────────────────┐
│   User   │ deposits│    MarginVault       │
│  Wallet  │────────▶│      (Kraken)        │
│          │  $50K   │                      │
└──────────┘         │  Self-governed SC    │
                     │  collateral: $50K    │
                     │  insurance: $100K    │
                     └──────────┬───────────┘
                                │
                     User trades on Kraken
                     with own margin engine
                                │
                     ┌──────────┴──────────┐
                     │                     │
                     ▼                     ▼
              Position opened      Position closed
              (Kraken manages)     (Settle PnL)
                                          │
                                          ▼
                               ┌────────────────┐
                               │ Instant Settle │
                               │                │
                               │ Win → Credit   │
                               │ Loss → Seize   │
                               └────────────────┘
```

### The Flow

#### 1. Deposit
User deposits $50K USDC into MarginVault (Kraken).  
Funds are held in self-governed smart contract.  
Kraken's risk engine sees $50K available collateral.

#### 2. Trade
User opens position on Kraken: Long 1 BTC ($10K margin).  
Kraken's own margin engine checks: user has $50K, needs $10K → APPROVED.  
Trade executes using Kraken's existing liquidation system.

#### 3. Settlement
Position closes with +$5K profit.  
Anduin settles instantly:
- Credits user PnL balance: +$5K (withdrawable immediately)
- Kraken pays $5K from settlement pool
- On-chain event emitted with refId deduplication

If loss: seize collateral, return to Kraken settlement pool.

#### 4. Withdrawal
User withdraws available balance anytime.  
No admin approval required.  
Available = collateral + PnL - margin in use.

### Key Benefits for Venues

**Why venues want single-venue settlement:**

1. **No custody risk** — Funds in self-governed smart contract, not your omnibus account
2. **Instant settlement** — Users get profits in seconds, not hours
3. **Insurance coverage** — Shortfalls covered by 6-layer insurance waterfall
4. **Easy integration** — Keep your existing margin engine and liquidation system
5. **User acquisition** — Traders prefer instant settlement and transparent accounting
6. **Compliance** — All settlements on-chain and auditable

**What you provide:**
- Settlement webhook when positions close
- Collateral requirements per user/position
- Liquidation notifications

**What Anduin handles:**
- Smart contract custody
- Instant PnL settlement
- Insurance waterfall for shortfalls
- On-chain transparency
- Deduplication and reconciliation

### Insurance Waterfall (6 Layers)

When a venue liquidates a user and there's a shortfall, the insurance waterfall activates:

```
┌──────────────────────────────────────────────────────┐
│  INSURANCE WATERFALL (6 LAYERS)                      │
├──────────────────────────────────────────────────────┤
│                                                      │
│  Layer 1: User's Remaining Collateral                │
│           └─ Seize all available user funds first   │
│                                                      │
│  Layer 2: Overcollateralization Buffer (5%)          │
│           └─ 5% of deposits held as safety buffer   │
│                                                      │
│  Layer 3: Anduin Protocol Insurance Fund             │
│           └─ Funded by settlement fees + premiums   │
│                                                      │
│  Layer 4: Venue Guarantee Stakes                     │
│           └─ Each venue deposits guarantee stake    │
│               (mutual insurance, like CME/LCH)      │
│                                                      │
│  Layer 5: Reinsurance Partner                        │
│           └─ Wholesale desks or DeFi protocols      │
│               (Wintermute, Galaxy, Nexus Mutual)    │
│                                                      │
│  Layer 6: Socialized Loss (Emergency Only)           │
│           └─ Last resort, should never be reached   │
│                                                      │
└──────────────────────────────────────────────────────┘
```

**Example:**
```
User collateral:         $1,000
Trading loss:            $8,000
Overcollateralization:   $400 (5% of $8K obligation)
Protocol insurance:      $100,000
Venue guarantee stake:   $500,000

Result:
├─ Layer 1 (User):         $1,000 seized
├─ Layer 2 (Overcolat):    $400 used
├─ Layer 3 (Protocol):     $6,600 used
├─ Layer 4 (Venue stake):  $0 (not needed)
├─ Layer 5 (Reinsurance):  $0 (not needed)
└─ Layer 6 (Socialized):   $0 (not needed)

Venue is made whole: receives full $8,000
```

**Replenishment:**
- Settlement fees (portion directed to insurance)
- Insurance premiums on deposits (0.5-2% annually)
- Venue guarantee stakes (refilled by venues)
- Reinsurance partner agreements

**Venue Guarantee Stakes:**

| Tier | Guarantee Stake | Coverage |
|------|----------------|----------|
| Starter | $100K | $500K coverage |
| Standard | $500K | $2.5M coverage |
| Enterprise | $2M+ | $10M+ coverage |

This is mutual insurance — like traditional clearing houses (CME, LCH). Venues with skin in the game protect each other.

**Key Message:**  
*"In stress testing across 8 venues, zero shortfalls reached layer 4."*

### Cross-Venue Netting (When 2+ Venues Are Live)

Once you have multiple venues on Anduin settlement, **ClearingVault** provides capital-efficient netting:

```
Accumulated obligations:
  Kraken owes users:  $100K (aggregate from all users)
  Bybit owes users:   $85K
  
  Net via ClearingVault: $15K transfer
  
  Gross settlement: $185K → Net settlement: $15K
  Capital savings: 92%
```

**How it works:**
- Each venue maintains guarantee deposit in ClearingVault
- Configurable netting windows (hourly, daily, on-demand)
- Atomic on-chain execution
- Deduplication prevents double-settlement

**Benefits:**
- 60-80% reduction in settlement volume
- Lower capital requirements
- Shared default fund protects against venue failures

This is the natural next step once multiple venues are operating Anduin V2.

---

## Additional Feature: Cross-Venue Portfolio Margin

Once 2+ venues are running single-venue settlement, venues can opt into **cross-venue portfolio margin** — the upgrade offer.

### How It Works

Cross-venue portfolio margin is **layered on top** of existing MarginVaults. No contract migration needed.

**HubVault** (equity engine coordinator) sits above the venue-specific MarginVaults:

```
                     ┌──────────────────────┐
                     │      HubVault        │
                     │ (Equity Coordinator) │
                     │                      │
                     │  User collateral:    │
                     │  $50K (total)        │
                     └──────────┬───────────┘
                                │
                     Equity engine moves balances
                     between existing vaults
                                │
                     ┌──────────┴──────────┐
                     ▼                     ▼
              ┌─────────────┐      ┌─────────────┐
              │MarginVault  │      │MarginVault  │
              │  (Kraken)   │      │   (Bybit)   │
              │             │      │             │
              │ Balance: var│      │ Balance: var│
              │ (adjusted)  │      │ (adjusted)  │
              └─────────────┘      └─────────────┘
```

### Equity Engine

**Instead of** user depositing $50K on each venue (capital inefficient):
- User deposits $50K once into HubVault
- HubVault shows $50K on both MarginVaults initially
- As user trades, equity engine recalculates balances:

**Example:**
```
User deposits $50K total
Opens $30K position on Kraken (Long BTC)
Opens $25K position on Bybit (Short BTC)

BTC moves 10%:
  Kraken unrealized PnL: +$3K
  Bybit unrealized PnL:  -$2.5K

Equity engine recalculates:
  Kraken equity = $50K + $3K - 50% × $2.5K = $51.75K
  Bybit equity  = $50K - $2.5K + 50% × $3K = $49K

Both venues stay healthy automatically.
```

### 50% Haircut on Cross-Venue PnL

**Why haircut positive PnL from other venues?**

- Price could reverse before next equity update
- Latency between venues (prices not perfectly synced)
- Execution risk on liquidation
- Conservative approach protects insurance pool

Haircut is **configurable** — start at 50%, adjust per asset/venue/volatility.

### Revenue Sharing Incentive

**Why would a venue opt into cross-venue margining?**

Origin venue earns passive income from cross-venue flow:

| Settlement Fee Split | Allocation |
|---------------------|-----------|
| Anduin protocol | 1.5 bps |
| Origin venue | 1.0 bps |
| Destination venue | 0.5 bps |

**Example:**
- User deposits on Kraken
- Trades $10M on Bybit using cross-venue margin
- Settlement fees: $3,000 total
  - Kraken earns: $1,000 (passive income)
  - Anduin earns: $1,500
  - Bybit earns: $500

Kraken earns fees on Bybit volume — incentive to allow cross-venue flow.

### Upgrade Path

**V2 → V3 migration is seamless:**

1. Venue already running MarginVault (V2)
2. Deploy HubVault coordinator
3. Opt into equity engine (flag in contract)
4. Existing MarginVault continues operating
5. HubVault adjusts balances based on cross-venue PnL

**No contract migration. No downtime. Just an upgrade flag.**

---

## Smart Contracts

### MarginVault.sol (Per Venue) — Core Contract

One MarginVault per venue. Self-governed, no custodian.

**State:**
```solidity
mapping(address => uint256) public collateral;        // user deposits
mapping(address => uint256) public pnl;               // user winnings
uint256 public insurancePool;                         // venue insurance
uint256 public totalDeposits;                         // sum of all user collateral
mapping(bytes32 => bool) public processedSettlements; // deduplication
```

**User Functions:**
```solidity
depositCollateral(uint256 amount)
  → User deposits USDC. Always allowed.
  → Funds held in self-governed contract.

withdrawAvailable(uint256 amount)
  → User withdraws available balance.
  → Available = collateral + pnl - marginInUse.
  → NO admin can block this.
```

**Settlement Functions (onlySettlement):**
```solidity
creditPnL(address user, uint256 amount, bytes32 refId)
  → Credit realized profit to user's PnL balance.
  → Deduped by refId.

seizeCollateral(address user, uint256 amount, bytes32 refId)
  → Seize collateral on loss.
  → If user collateral insufficient → insurance waterfall.
  → Deduped by refId.
```

**Insurance Functions:**
```solidity
depositInsurance(uint256 amount) → venue deposits to insurance pool
processShortfall(address user, uint256 amount) → activate waterfall
```

**Governance (timelocked):**
```solidity
setSettlementRole(address settlement)
setInsuranceTiers(...)
pause() / unpause()
```

### ClearingVault.sol (Cross-Venue Netting)

Tracks net obligations between venues:

```solidity
mapping(address => mapping(address => uint256)) public obligations;
// obligations[venueA][venueB] = amount venueA owes venueB

mapping(address => uint256) public guaranteeDeposits;
// Each venue's stake in clearing fund

function settleNet() external {
  // Calculate net obligations
  // Execute atomic transfers
  // Emit NettingCompleted event
}
```

### HubVault.sol (Equity Engine Coordinator) — V3 Layer, Optional

**Only deployed when cross-venue margin is activated.**

Manages equity updates across multiple MarginVaults:

```solidity
mapping(address => uint256) public totalCollateral;  // user's total collateral
mapping(address => mapping(address => uint256)) public venueAllocations;
// venueAllocations[user][venue] = equity shown on that venue

function updateVenueEquity(
  address user,
  address venue,
  uint256 newEquity
) external onlyKeeper {
  // Update MarginVault balance for user
  MarginVault(venue).setEquity(user, newEquity);
}
```

**Key Design:**
- HubVault coordinates equity
- MarginVaults still handle actual settlement
- Venues can opt out of cross-venue features
- Backwards compatible with V2-only operation

### UnifiedAccountVault.sol (Legacy Single-Venue MVP)

Early prototype for single-venue settlement. Being replaced by MarginVault architecture.

**Migration path:** UnifiedAccountVault → MarginVault (simpler, more modular)

### Supporting Contracts

- **OracleGuard.sol** — Price validation, oracle failover
- **TradingHoursGuard.sol** — Trading hours enforcement, halts
- **SecurityTokenVault.sol** — DVP for tokenized securities
- **BatchSettlementVault.sol** — Merkle-proof netting (HFT)
- **PrivateSettlementVault.sol** — Commitment-based privacy

---

## Security Model

### Self-Governance

**MarginVault:**
- Users always withdraw available balance (no admin override)
- Insurance pool balance transparent on-chain
- All settlements deduplicated by refId
- Event logs for complete auditability

### Venue Trust

**What venues control:**
- Margin requirements for their users
- Liquidation triggers and execution
- Position limits and risk parameters

**What venues CANNOT do:**
- Withdraw user funds from MarginVault
- Block user withdrawals
- Modify settlement records
- Access insurance pool directly

### Insurance Pool Security

**Layer 4 (Venue Guarantee Stakes):**
- Each venue deposits guarantee stake to join
- Mutual insurance model like traditional clearing houses
- Stake slashed only if venue's users create shortfalls
- Incentivizes venues to maintain proper risk management

**Layer 5 (Reinsurance Partner):**
- Wholesale lending desks or DeFi insurance protocols
- Contractual agreements for coverage
- Examples: Wintermute, Galaxy, Nexus Mutual
- Activated only if layers 1-4 insufficient

### Risk Parameters

**Per Venue:**
- Overcollateralization buffer (default: 5%)
- Insurance pool minimum (5-10% of deposits)
- Maximum user leverage
- Haircut on cross-venue PnL (default: 50%)

**Global:**
- Circuit breaker thresholds
- Oracle failover parameters
- Timelock delays for governance changes

---

## Deployment Architecture

### V2 Deployment (Single-Venue Settlement)

**Per venue:**
1. Deploy MarginVault for that venue
2. Deploy supporting contracts (OracleGuard, TradingHoursGuard)
3. Venue deposits guarantee stake
4. Anduin seeds protocol insurance fund
5. Integration testing
6. Go live

**Venues operate independently** — no dependency on other venues.

### V3 Deployment (Cross-Venue Portfolio Margin)

**Once 2+ venues are live:**
1. Deploy HubVault (coordinator)
2. Deploy ClearingVault (netting)
3. Opt-in per venue (flag in MarginVault)
4. Configure haircut parameters
5. Deploy equity engine keeper
6. Gradual rollout with monitoring

**V2 contracts remain operational** — V3 is purely additive.

---

## Product Offerings

| Product | Description | Target | Contracts |
|---------|-------------|--------|-----------|
| **V1 - UnifiedAccountVault** | Single-venue instant settlement (legacy MVP) | Early testing | UnifiedAccountVault |
| **V2 - MarginVault + ClearingVault** | Single-venue settlement with cross-venue netting | PRIMARY PRODUCT — what venues onboard with | MarginVault, ClearingVault |
| **V3 - HubVault + Equity Engine** | Cross-venue portfolio margin | UPGRADE FEATURE — optional layer on top of V2 | HubVault, MarginVault, ClearingVault |

**Current Focus:** V2 (MarginVault) is the core product. V3 is the upsell.

---

## Revenue Model

| Revenue Stream | Description | Pricing |
|---------------|-------------|---------|
| Settlement fees | Per-settlement fee on realized PnL | 1-5 bps |
| Insurance premium | Annual fee on user deposits (charged to venues) | 0.5-2% |
| Equity update service | Per-user monthly fee for cross-venue equity updates (V3 only) | $1-5/user/month |
| Netting fees | Fee on capital saved through cross-venue netting | 0.5-1 bps of netted amount |
| Integration fee | One-time venue onboarding (white-glove service) | $25K-100K |

**V2 Revenue:** Settlement fees + insurance premium + netting fees + integration fee  
**V3 Revenue:** All of V2 + equity update service + cross-venue settlement fee split

---

## Integration Requirements

### What Venues Provide

**For V2 (Single-Venue Settlement):**

| Requirement | Type | Purpose |
|------------|------|---------|
| Settlement webhook | Webhook | Notify Anduin when positions close |
| Margin requirements | Config | How much collateral per position |
| Liquidation notifications | Webhook | Alert Anduin when liquidations occur |
| User authentication | API | Verify user identity |

**For V3 (Cross-Venue Portfolio Margin) — Additional:**

| Requirement | Type | Purpose |
|------------|------|---------|
| Balance API | REST | Set/update user balance |
| Position feed | WebSocket | Real-time position data |
| Order freeze API | REST | Stop new orders for overspend |

### What Venues Get

**V2 Benefits:**
- Instant settlement infrastructure
- Insurance coverage for shortfalls
- On-chain transparency and auditability
- No custody risk
- User acquisition (traders prefer instant settlement)
- 60-80% capital savings from netting (when 2+ venues live)

**V3 Additional Benefits:**
- Users trade 2-3x bigger with portfolio margin
- Revenue sharing from cross-venue flow
- Access to Anduin's multi-venue user network
- Real-time equity updates

---

## Migration Paths

### V1 → V2

**From UnifiedAccountVault to MarginVault:**
1. Export user data from UnifiedAccountVault
2. Deploy MarginVault for venue
3. Migrate user balances
4. Update settlement service to target MarginVault
5. Retire UnifiedAccountVault

### V2 → V3

**Adding cross-venue features to existing MarginVault:**
1. MarginVault already operational (no changes needed)
2. Deploy HubVault coordinator
3. Venue opts into equity engine (contract flag)
4. Configure haircut parameters
5. Equity engine begins adjusting MarginVault balances
6. Venue earns cross-venue settlement fees

**No downtime. No contract migration. Just an upgrade.**

---

## Summary

**Core Product (V2):**
- One MarginVault per venue
- Self-governed, instant settlement
- 6-layer insurance waterfall
- Cross-venue netting (when 2+ venues live)
- **This is what venues onboard with**

**Additional Feature (V3):**
- Cross-venue portfolio margin
- Layered on top of V2 (no migration)
- Equity engine adjusts balances
- 50% haircut on cross-venue PnL
- Revenue sharing incentive
- **This is the upgrade offer**

Anduin sells **settlement first**, **cross-venue second**.
