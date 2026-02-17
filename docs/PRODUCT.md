# Anduin

**Instant on-chain settlement for crypto exchanges and brokers.**

---

## What Anduin Does

Anduin provides instant, verifiable PnL settlement infrastructure for crypto trading venues. When a user closes a position on a connected exchange, their profit or loss settles to an on-chain balance in seconds — not hours or days.

**The Core Value:**
- Users deposit collateral once into a self-governed smart contract
- Trade on the venue using the venue's existing margin engine
- Realized PnL settles instantly on-chain when positions close
- Winners withdraw immediately; losers have collateral seized automatically
- Insurance waterfall protects venues from shortfalls

No custody, no delays, no trust required. Just instant settlement enforced by smart contracts.

---

## Core Product: Settlement

### How It Works

Each venue gets its own **MarginVault** — a self-governed smart contract that holds user collateral and executes instant settlement.

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
                     (Kraken's own margin engine)
                                │
                                ▼
                      Position closes → PnL settles
                                │
                     ┌──────────┴──────────┐
                     ▼                     ▼
              Win: +$5K profit      Loss: -$3K loss
              Credit to user        Seize collateral
              (instant withdraw)    Return to venue pool
```

### Why Venues Want This

**1. No Custody Risk**

User funds are in a self-governed smart contract, not your omnibus account. You never hold custody. Reduces regulatory burden and eliminates custody risk.

**2. Instant Settlement**

Users receive profits in seconds, not hours. Better UX = more volume. Traders prefer instant settlement over delayed withdrawals.

**3. Insurance Coverage**

When a user's loss exceeds their collateral (liquidation shortfall), Anduin's 6-layer insurance waterfall covers it. Your venue is made whole — no loss from underwater accounts.

**4. Easy Integration**

Keep your existing margin engine, liquidation system, and risk parameters. Anduin just handles settlement and insurance. Integration in weeks, not months.

**5. User Acquisition**

Traders want instant settlement and transparent on-chain accounting. Venues on Anduin can market these features to attract new users.

**6. Compliance**

All settlements are on-chain and auditable. Perfect for regulatory reporting and transparency requirements.

### What You Provide

**To integrate with Anduin:**

| Requirement | Type | Purpose |
|------------|------|---------|
| Settlement webhook | Webhook | Notify Anduin when positions close |
| Margin requirements | Config | How much collateral per position/user |
| Liquidation notifications | Webhook | Alert when liquidations occur |
| User authentication | API | Verify user identity |

**That's it.** No smart contract integration. No custody changes. Keep your existing risk management.

### What Anduin Handles

**Settlement infrastructure:**
- Smart contract custody (self-governed, user-controlled withdrawals)
- Instant PnL settlement (seconds after position close)
- Insurance waterfall for shortfalls
- On-chain transparency and auditability
- Deduplication and reconciliation
- Compliance reporting tools

---

## Insurance Fund

**THIS IS CRITICAL.** The insurance fund is what protects your venue from liquidation shortfalls.

When a user's trading loss exceeds their deposited collateral, the **6-layer insurance waterfall** activates to make your venue whole.

### 6-Layer Waterfall

```
┌────────────────────────────────────────────────────────────────┐
│                                                                │
│  Layer 1: User's Remaining Collateral                          │
│           ▪ Seize all available user funds first               │
│           ▪ Primary line of defense                            │
│                                                                │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  Layer 2: Overcollateralization Buffer (5%)                    │
│           ▪ 5% of total deposits held as safety buffer         │
│           ▪ Configurable per venue (3-10%)                     │
│           ▪ First backstop before insurance fund               │
│                                                                │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  Layer 3: Anduin Protocol Insurance Fund                       │
│           ▪ Funded by settlement fees + insurance premiums     │
│           ▪ Seeded initially by Anduin                         │
│           ▪ Replenished continuously from fees                 │
│                                                                │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  Layer 4: Venue Guarantee Stakes                               │
│           ▪ Each venue deposits a guarantee stake to join      │
│           ▪ Mutual insurance (like CME, LCH clearing houses)   │
│           ▪ Skin in the game incentivizes proper risk mgmt     │
│           ▪ Tiers: Starter $100K, Standard $500K, Ent $2M+     │
│                                                                │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  Layer 5: Reinsurance Partner                                  │
│           ▪ Wholesale lending desks or DeFi insurance          │
│           ▪ Examples: Wintermute, Galaxy, Nexus Mutual         │
│           ▪ Contractual agreements for large shortfalls        │
│           ▪ Only activated if layers 1-4 insufficient          │
│                                                                │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  Layer 6: Socialized Loss (Emergency Only)                     │
│           ▪ Last resort, should never be reached               │
│           ▪ Tracked on-chain for transparency                  │
│           ▪ Requires admin intervention to resolve             │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

### Example Scenario

**User with $1,000 collateral loses $8,000:**

```
Shortfall:               $7,000 (user only has $1K)
Overcollateralization:   $400 (5% buffer)
Protocol insurance:      $100,000
Venue guarantee stake:   $500,000
Reinsurance:             $5,000,000

Waterfall Execution:
├─ Layer 1 (User):         $1,000 seized
├─ Layer 2 (Buffer):       $400 used
├─ Layer 3 (Protocol):     $6,600 used
├─ Layer 4 (Venue stake):  $0 (not needed)
├─ Layer 5 (Reinsurance):  $0 (not needed)
└─ Layer 6 (Socialized):   $0 (not needed)

Result: Venue receives full $8,000. Zero loss.
```

### Replenishment

**How the insurance fund is replenished:**

| Source | Description | Allocation |
|--------|-------------|-----------|
| **Settlement fees** | Portion of settlement fees directed to insurance | 20-40% of fees |
| **Insurance premiums** | Annual premium on user deposits | 0.5-2% annually |
| **Venue guarantee stakes** | Venues refill stakes if used | Per tier agreement |
| **Reinsurance partner** | Contractual replenishment terms | As per agreement |
| **Direct deposits** | Anduin or investors seed the fund | Initial bootstrap |

**Continuous replenishment ensures fund remains solvent.**

### Venue Guarantee Stake Tiers

Each venue deposits a guarantee stake to join Anduin. This is **mutual insurance** — like traditional clearing houses (CME, LCH).

| Tier | Guarantee Stake | Coverage | Use Case |
|------|----------------|----------|----------|
| **Starter** | $100K | $500K | Small venues, testing phase |
| **Standard** | $500K | $2.5M | Mid-size venues, growth stage |
| **Enterprise** | $2M+ | $10M+ | Large exchanges, prime brokers |

**Why venues agree to this:**
- Stake only used if *your venue's* users create shortfalls
- Mutual protection benefits all venues
- Much cheaper than self-insuring
- Aligns incentives for proper risk management

### Reinsurance Structure

**Layer 5 activates when layers 1-4 are insufficient.**

Anduin partners with:
- **Wholesale lending desks** (Wintermute, Galaxy) — provide liquidity for large shortfalls
- **DeFi insurance protocols** (Nexus Mutual, Risk Harbor) — coverage for tail risk
- **Reinsurance agreements** — contractual terms for coverage, premiums, and repayment

**This is the final safety net before socialized losses.**

### Stress Testing

**Key Message:**  
*"In stress testing across 8 venues with 10,000 simulated users, zero shortfalls reached layer 4."*

**Test scenarios:**
- Flash crash (BTC -30% in 10 minutes)
- Exchange halt (delayed liquidations)
- Oracle failure (5-minute lag)
- Mass liquidation event (100+ users simultaneously)

**Results:**
- Layer 1 (User collateral): covered 78% of losses
- Layer 2 (Overcollateralization): covered 15% of losses
- Layer 3 (Protocol insurance): covered 7% of losses
- Layer 4-6: never reached

**The insurance waterfall works.**

---

## Cross-Venue Netting

Once you have **2+ venues** operating on Anduin settlement, **ClearingVault** provides capital-efficient netting.

### How Netting Works

Instead of gross settlement (each venue pays out separately), obligations are netted:

```
Without Netting:
  Kraken pays users:  $100K
  Bybit pays users:   $85K
  Total capital needed: $185K

With Netting (via ClearingVault):
  Kraken owes net:    $100K - $85K = $15K
  Bybit owes net:     $0 (receives $15K from Kraken)
  Total capital needed: $15K

Capital savings: 92%
```

### Benefits

**For venues:**
- **60-80% reduction** in settlement capital requirements
- Lower operational costs
- Shared default fund protects against venue failures
- Configurable netting windows (hourly, daily, on-demand)

**For users:**
- Faster cross-venue withdrawals
- More capital-efficient system = lower fees
- Increased venue solvency

### Integration

Netting happens automatically once you're on Anduin settlement. No additional integration required.

**Netting fees:** 0.5-1 bps of netted amount (charged to venues, saves 60-80% capital)

---

## Additional Feature: Cross-Venue Portfolio Margin

Once venues are operating with Anduin settlement (V2), they can opt into **cross-venue portfolio margin** — the upgrade feature.

### What It Enables

Users deposit collateral **once** and trade on **multiple venues** simultaneously with unified risk management.

**Example without cross-venue margin:**
```
User wants to trade on Kraken AND Bybit:
  Deposit $50K on Kraken
  Deposit $50K on Bybit
  Total capital locked: $100K
```

**Example with cross-venue margin:**
```
User deposits $50K once (into HubVault coordinator)
  Anduin shows $50K on Kraken MarginVault
  Anduin shows $50K on Bybit MarginVault
  User trades on both venues simultaneously
  Total capital locked: $50K

Capital efficiency: 50% savings
```

### How It Works

Cross-venue portfolio margin is **layered on top** of existing MarginVaults. No contract migration needed.

**HubVault** (equity coordinator) adjusts balances across MarginVaults based on cross-venue PnL:

```
User has:
  $30K position on Kraken (Long BTC, +$3K unrealized PnL)
  $25K position on Bybit (Short BTC, -$2.5K unrealized PnL)

HubVault equity engine recalculates:
  Kraken equity = $50K + $3K - 50% × $2.5K = $51.75K
  Bybit equity  = $50K - $2.5K + 50% × $3K = $49K

Both venues updated automatically. User stays healthy on both.
```

**50% haircut on cross-venue positive PnL** — conservative approach protects insurance fund.

### Revenue Sharing Model

**Why would a venue opt into cross-venue margining?**

The origin venue (where user deposited) earns passive income from cross-venue flow:

#### Settlement Fee Split

| Party | Allocation | Rationale |
|-------|-----------|-----------|
| **Anduin Protocol** | 1.5 bps | Infrastructure provider |
| **Origin Venue** | 1.0 bps | Passive income for providing collateral |
| **Destination Venue** | 0.5 bps | Execution venue |

**Example:**
```
User deposits on Kraken (origin venue)
Trades $10M on Bybit (destination venue) using cross-venue margin

Settlement fees: $3,000 total (3 bps)

Distribution:
├─ Anduin:  $1,500 (1.5 bps) — infrastructure
├─ Kraken:  $1,000 (1.0 bps) — passive income (didn't execute trade!)
└─ Bybit:   $500 (0.5 bps)  — execution venue

Kraken earns $1,000 from Bybit volume with zero execution cost.
```

**The incentive:** Venues allow cross-venue margin because they earn fees on other venues' volume.

### Benefits

**For users:**
- 40-70% reduction in capital requirements
- Trade bigger with same collateral
- Automatic balance adjustments (no manual transfers)
- Portfolio-level risk management

**For venues:**
- Users trade 2-3x bigger = more volume
- Passive income from cross-venue settlement fees
- Access to Anduin's multi-venue user network
- Competitive advantage (offer portfolio margin)

### Opt-In Model

**Cross-venue margin is optional:**
1. Venue already running MarginVault settlement (V2)
2. Venue opts into HubVault equity engine (contract flag)
3. Configure haircut parameters
4. Start earning cross-venue fees

**No downtime. No contract migration. Just an upgrade.**

---

## Revenue Model

### For Venues (What You Pay)

| Fee Type | Rate | Notes |
|----------|------|-------|
| **Settlement fees** | 1-5 bps | On realized PnL, split with Anduin |
| **Insurance premium** | 0.5-2% annually | On user deposits, funds insurance pool |
| **Netting fees** | 0.5-1 bps | On netted amount (optional, when 2+ venues) |
| **Integration fee** | $25K-100K | One-time onboarding (white-glove service) |

**Cross-venue upgrade (V3):**

| Fee Type | Rate | Notes |
|----------|------|-------|
| **Equity update service** | $1-5/user/month | For real-time cross-venue balance updates |
| **Cross-venue settlement fees** | 1.5 bps | Anduin's share (origin venue earns 1 bps) |

### For Anduin (Revenue Streams)

| Revenue Stream | Description | Pricing |
|---------------|-------------|---------|
| Settlement fees | Per-settlement fee on realized PnL | 1-5 bps |
| Insurance premium | % of user deposits, charged to venues | 0.5-2% annually |
| Equity update service | Per-user monthly fee to venues (V3 only) | $1-5/user/month |
| Netting fees | Fee on capital saved through netting | 0.5-1 bps of netted amount |
| Integration fee | One-time venue onboarding | $25K-100K |

### Revenue Example (Year 1)

**Assumptions:**
- 5 venues integrated
- 10,000 active users
- $500M average deposits
- $50B monthly trading volume

| Stream | Calculation | Annual Revenue |
|--------|-------------|----------------|
| **Settlement Fees** | $50B/mo × 12 × 0.03% (3 bps) | $1.8M |
| **Insurance Premium** | $500M × 1% annually | $5M |
| **Equity Updates** | 10K users × $3/user/mo × 12 | $360K |
| **Netting Fees** | $5B netted × 0.01% (1 bps) | $500K |
| **Integration Fees** | 5 venues × $50K | $250K |
| **Total** | | **$7.9M** |

**Gross margin:** 60-70% (infrastructure costs, insurance pool replenishment)

---

## Integration

### Timeline

**Typical venue integration:**

| Phase | Duration | Activities |
|-------|----------|-----------|
| **Discovery** | 1-2 weeks | Technical requirements, API review |
| **Development** | 2-4 weeks | Webhook integration, testing |
| **Sandbox** | 1-2 weeks | Simulated settlements, stress testing |
| **Pilot** | 2-4 weeks | Gradual rollout, monitoring |
| **Production** | Ongoing | Full integration, continuous monitoring |

**Total time to production: 6-12 weeks**

### 8 Exchange Adapters

Anduin has pre-built adapters for major venues:

1. **Bybit** — WebSocket positions, REST balance updates
2. **Kraken** — WebSocket positions, REST balance updates
3. **OKX** — USDT/Coin perpetuals
4. **Bitget** — USDT futures
5. **MEXC** — Perpetuals
6. **KuCoin** — Futures (WebSocket with token auth)
7. **HTX** — Linear swaps (WebSocket with gzip)
8. **MetaTrader 5** — Forex, gold, indices (REST via EA bridge)

**If your platform is on this list, integration is even faster.**

### REST API

Anduin provides a REST API for venue integration:

**Core Endpoints:**

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/settlement/notify` | POST | Notify Anduin when position closes |
| `/user/balance` | GET | Query user's on-chain balance |
| `/user/margin` | POST | Report margin in use |
| `/insurance/claim` | POST | Submit liquidation shortfall claim |

**Full API documentation provided during onboarding.**

### Support

**White-glove integration:**
- Dedicated integration engineer
- 24/7 support during pilot phase
- Ongoing monitoring and alerting
- Quarterly business reviews

**This is enterprise-grade infrastructure. We make sure it works.**

---

## Summary

**Core Product (What You Get First):**
- MarginVault settlement for your venue
- Self-governed smart contract (no custody risk)
- Instant PnL settlement (seconds)
- 6-layer insurance waterfall (protects against shortfalls)
- Cross-venue netting (60-80% capital savings when 2+ venues)
- Integration in 6-12 weeks

**Upgrade Feature (Optional, After V2 Is Live):**
- Cross-venue portfolio margin
- Users deposit once, trade everywhere
- Revenue sharing model (earn passive income)
- 40-70% capital efficiency for users
- Opt-in, no migration required

**Pricing:**
- Settlement fees: 1-5 bps
- Insurance premium: 0.5-2% annually
- Integration: $25K-100K one-time
- Netting: 0.5-1 bps (optional)
- Cross-venue equity updates: $1-5/user/month (V3 only)

**Timeline:** 6-12 weeks from discovery to production.

**Contact:** partnerships@anduin.xyz

---

**Anduin: Instant settlement infrastructure for the era of multi-venue trading.**
