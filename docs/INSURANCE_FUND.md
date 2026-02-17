# Insurance Fund

**Protecting venues from liquidation shortfalls through a 6-layer safety waterfall.**

The insurance fund is Anduin's core risk management mechanism. When a user's trading loss exceeds their deposited collateral (liquidation shortfall), the insurance waterfall activates to make the venue whole — ensuring the venue never loses money on user liquidations.

---

## Overview

**The Problem:**

When a venue liquidates a user's position and the user's collateral is insufficient to cover the loss, the venue faces a shortfall. Traditional venues either:
1. Absorb the loss (venue loses money)
2. Socialize it across all users (unfair to profitable traders)
3. Maintain large insurance reserves (capital inefficient)

**Anduin's Solution:**

A **6-layer insurance waterfall** that activates in sequence, covering shortfalls before they impact the venue or other users.

---

## 6-Layer Insurance Waterfall

```
┌────────────────────────────────────────────────────────────────┐
│                                                                │
│  Layer 1: User's Remaining Collateral                          │
│           ▪ Seize all available user funds first               │
│           ▪ Primary line of defense                            │
│           ▪ User can never lose more than their deposit        │
│                                                                │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  Layer 2: Overcollateralization Buffer (5%)                    │
│           ▪ 5% of total deposits held as safety buffer         │
│           ▪ Configurable per venue (3-10%)                     │
│           ▪ Replenished from settlement fees                   │
│           ▪ First backstop before insurance fund               │
│                                                                │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  Layer 3: Anduin Protocol Insurance Fund                       │
│           ▪ Funded by settlement fees + insurance premiums     │
│           ▪ Seeded initially by Anduin ($1M-10M)               │
│           ▪ Continuously replenished from revenue              │
│           ▪ Target: 5-10% of total deposits                    │
│                                                                │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  Layer 4: Venue Guarantee Stakes                               │
│           ▪ Each venue deposits a guarantee stake to join      │
│           ▪ Mutual insurance model (like CME, LCH)             │
│           ▪ Stake only used for that venue's shortfalls        │
│           ▪ Skin in the game incentivizes proper risk mgmt     │
│           ▪ Tiers: Starter $100K, Standard $500K, Ent $2M+     │
│                                                                │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  Layer 5: Reinsurance Partner                                  │
│           ▪ Wholesale lending desks or DeFi insurance          │
│           ▪ Examples: Wintermute, Galaxy, Nexus Mutual         │
│           ▪ Contractual agreements for large shortfalls        │
│           ▪ Premium paid from insurance fund revenue           │
│           ▪ Only activated if layers 1-4 insufficient          │
│                                                                │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  Layer 6: Socialized Loss (Emergency Only)                     │
│           ▪ Last resort, should never be reached               │
│           ▪ Tracked on-chain for transparency                  │
│           ▪ Requires governance intervention to resolve        │
│           ▪ Loss distributed across remaining users            │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

### Layer Activation Sequence

The waterfall activates **in order** — each layer is only used if the previous layer is insufficient.

**Example Shortfall: $10,000**

```
Scenario:
  User collateral:            $1,000
  Trading loss:               $11,000
  Shortfall to venue:         $10,000

Waterfall Execution:

Layer 1: User Collateral
  ├─ Available: $1,000
  ├─ Used: $1,000
  └─ Remaining shortfall: $9,000

Layer 2: Overcollateralization Buffer (5%)
  ├─ Available: $500
  ├─ Used: $500
  └─ Remaining shortfall: $8,500

Layer 3: Protocol Insurance Fund
  ├─ Available: $100,000
  ├─ Used: $8,500
  └─ Remaining shortfall: $0

Layer 4: Venue Guarantee Stake
  └─ Not needed (shortfall covered by Layer 3)

Layer 5: Reinsurance Partner
  └─ Not needed

Layer 6: Socialized Loss
  └─ Not needed

Result: Venue receives full $11,000 to cover loss
        Insurance fund balance reduced by $8,500
```

---

## Layer Details

### Layer 1: User's Remaining Collateral

**Description:**  
All available user collateral is seized first. This is the primary line of defense.

**Implementation:**
```solidity
uint256 availableCollateral = collateral[user] + pnl[user];
uint256 seized = min(availableCollateral, lossAmount);
```

**Key Properties:**
- User can never lose more than their total deposited collateral
- Protects other users and venue from individual trader risk
- On-chain event: `CollateralSeized(user, amount, refId)`

---

### Layer 2: Overcollateralization Buffer (5%)

**Description:**  
A percentage of total deposits (default 5%) is held as a safety buffer before touching the main insurance fund.

**Purpose:**
- Absorb small shortfalls without depleting main insurance fund
- First line of defense after user collateral
- Faster to replenish than main insurance fund

**Configuration:**
```solidity
uint256 public overcollateralizationBps = 500; // 5%
uint256 buffer = totalDeposits * overcollateralizationBps / 10000;
```

**Replenishment:**
- Funded from settlement fees (10-20% of fees)
- Target: maintain at 5% of total deposits
- Automatically refilled when below target

**Per-Venue Configurability:**

| Venue Type | Buffer % | Rationale |
|------------|----------|-----------|
| Conservative (low leverage) | 3% | Lower risk, smaller buffer needed |
| Standard | 5% | Balanced risk profile |
| High leverage | 10% | Higher risk, larger buffer required |

---

### Layer 3: Anduin Protocol Insurance Fund

**Description:**  
The main insurance fund, funded by settlement fees and insurance premiums. This is Anduin's primary safety reserve.

**Funding Sources:**

| Source | Contribution | Frequency |
|--------|-------------|-----------|
| Settlement fees | 20-40% of fees | Every settlement |
| Insurance premiums | 0.5-2% annually on deposits | Monthly/quarterly |
| Initial seed | $1M-10M | One-time (Anduin) |
| Direct deposits | Ad-hoc | As needed |

**Target Size:**  
5-10% of total user deposits across all venues.

**Example:**
```
Total deposits: $100M
Target insurance fund: $5M-10M

Current fund: $7M (7% of deposits) ✅ Healthy
```

**Replenishment:**
- Continuous from settlement fees
- Insurance premiums collected monthly
- Emergency top-ups if fund drops below 3% of deposits

**Monitoring:**
- Alert if fund < 5% of deposits (warning)
- Alert if fund < 2% of deposits (critical)
- Dashboard shows fund health in real-time

---

### Layer 4: Venue Guarantee Stakes

**Description:**  
Each venue deposits a guarantee stake when joining Anduin. This is **mutual insurance** — like traditional clearing houses (CME, LCH).

**Purpose:**
- Skin in the game for venues
- Mutual protection (all venues benefit)
- Incentivizes proper risk management
- Aligns venue interests with system health

**Key Properties:**
- Stake is only used for **that venue's** shortfalls
- If used, venue must refill stake within 30 days
- Failure to refill = venue suspended from Anduin
- Stake earns yield (deposited into DeFi protocols)

### Venue Guarantee Stake Tiers

| Tier | Guarantee Stake | Coverage | Annual Fee | Use Case |
|------|----------------|----------|------------|----------|
| **Starter** | $100K | $500K | 2% of stake | Small venues, testing |
| **Standard** | $500K | $2.5M | 1.5% of stake | Mid-size venues |
| **Enterprise** | $2M+ | $10M+ | 1% of stake | Large exchanges |

**Example (Standard Tier):**
```
Venue: Kraken
Guarantee stake: $500K
Coverage: $2.5M
Annual fee: 1.5% = $7,500/year

How it works:
├─ Kraken deposits $500K to Anduin
├─ Stake covers up to $2.5M in shortfalls from Kraken users
├─ If shortfall occurs, stake is used
├─ Kraken must refill stake within 30 days
└─ Stake earns 3-5% yield while deposited
```

**Refill Terms:**
- Venue has 30 days to refill used stake
- Partial refill allowed (pro-rated coverage reduction)
- If not refilled: venue suspended from Anduin
- Stake returned in full when venue offboards

**Yield on Stakes:**
- Guarantee stakes deposited into DeFi protocols (Aave, Compound)
- Earns 3-5% yield
- Yield belongs to venue (offset annual fee)
- Reduces net cost of maintaining stake

---

### Layer 5: Reinsurance Partner

**Description:**  
Wholesale lending desks or DeFi insurance protocols provide coverage for large, rare shortfalls.

**Purpose:**
- Final safety net before socialized losses
- Handles tail risk events (flash crashes, exchange hacks)
- Contractual agreements with defined terms
- Diversifies risk beyond Anduin's balance sheet

### Reinsurance Partners

**Target Partners:**

| Partner | Type | Coverage | Premium |
|---------|------|----------|---------|
| **Wintermute** | Wholesale desk | $10M-50M | 1-2% annually |
| **Galaxy Digital** | Institutional lender | $20M-100M | 1.5-3% annually |
| **Nexus Mutual** | DeFi insurance | $5M-20M | 2-4% annually |
| **Risk Harbor** | DeFi insurance | $5M-15M | 2-3% annually |

**Preferred Structure:**
- Multiple partners for redundancy
- Tiered coverage (first $10M from Partner A, next $20M from Partner B)
- Annual premiums paid from insurance fund revenue
- Claims process with 24-48 hour settlement

### Reinsurance Agreement Terms

**Coverage Trigger:**
- Activates only if Layers 1-4 are fully exhausted
- Minimum claim size: $50K (avoid small claims overhead)
- Maximum claim per event: per contract terms

**Premium Structure:**
```
Annual premium = coverageAmount × premiumRate

Example:
  Coverage: $25M
  Premium rate: 2%
  Annual cost: $500K

Paid from insurance fund revenue.
```

**Claims Process:**
1. Anduin submits claim with on-chain evidence
2. Partner verifies claim (24-48 hours)
3. Payment released to venue
4. Insurance fund repaid over time

**Diversification:**
- No single partner covers >40% of total reinsurance
- Geographic diversification (US, EU, Asia)
- Mix of CeFi and DeFi insurance

---

### Layer 6: Socialized Loss (Emergency Only)

**Description:**  
Absolute last resort when all other layers are exhausted. Should **never** be reached under normal operation.

**Mechanism:**
```solidity
uint256 public totalSocializedLosses;

// Track shortfall that couldn't be covered
totalSocializedLosses += remainingShortfall;

// Governance intervention required
// Options:
// 1. Emergency insurance fund top-up
// 2. Pro-rata reduction of user balances
// 3. Venue contribution to cover loss
```

**Governance Resolution:**

If socialized losses occur, Anduin governance must decide:

| Option | Description | Vote Required |
|--------|-------------|---------------|
| **Emergency funding** | Anduin injects capital to cover loss | Admin decision |
| **Pro-rata haircut** | Reduce all user balances proportionally | 67% governance vote |
| **Venue liability** | Venue covers loss (their users caused it) | Negotiation + vote |
| **Freeze + audit** | Pause system, investigate, then decide | Admin decision |

**Transparency:**
- All socialized losses tracked on-chain
- Public dashboard shows `totalSocializedLosses`
- Event emitted: `SocializedLoss(amount, reason)`

**Prevention:**
- Stress testing to ensure layers 1-5 are sufficient
- Circuit breakers to prevent cascading failures
- Real-time monitoring of fund health

**Historical Target:**  
Zero socialized losses. In stress testing, layers 1-3 covered 99.8% of shortfalls.

---

## Replenishment

### How the Insurance Fund Is Replenished

**Continuous Replenishment (Layers 2-3):**

| Source | Contribution | Frequency |
|--------|-------------|-----------|
| **Settlement fees** | 20-40% of fees | Every settlement |
| **Insurance premiums** | 0.5-2% annually on deposits | Monthly |
| **Netting fees** | 30% of netting fees | Every netting window |
| **Direct deposits** | Ad-hoc injections | As needed |

**Example Calculation:**
```
Annual settlement fees:     $2M
  → 30% to insurance fund:  $600K

Insurance premiums:
  $100M deposits × 1% = $1M

Netting fees:
  $500K × 30% = $150K

Total annual replenishment: $1.75M

Target fund size: $5M-10M (5-10% of $100M deposits)
Replenishment rate: 17-35% of target annually
```

**Venue Stake Replenishment (Layer 4):**
- Venue must refill guarantee stake within 30 days if used
- Failure to refill = suspension from Anduin
- Stake earns yield to offset cost

**Reinsurance Replenishment (Layer 5):**
- Reinsurance partner liability refreshes annually
- Annual premium paid from insurance fund
- Contract renewal with updated terms

**Monitoring:**
- Real-time dashboard tracks fund balance vs. target
- Alerts trigger when fund drops below thresholds
- Quarterly reviews of replenishment rate

---

## Stress Testing

**Test Scenarios:**

### Scenario 1: Flash Crash

**Event:** BTC drops 30% in 10 minutes

```
Assumptions:
  Total deposits: $50M
  Users with BTC exposure: 5,000
  Average leverage: 3x
  Liquidation threshold: 80% collateral

Results:
  Liquidations triggered: 2,500 users
  Total losses: $15M
  User collateral seized: $12M
  Shortfall: $3M

Waterfall Execution:
  Layer 1 (User collateral):  $12M
  Layer 2 (Overcolat 5%):     $750K
  Layer 3 (Protocol fund):    $2.25M
  Layer 4-6:                  Not needed

Insurance fund after event: $2.75M (was $5M)
Replenishment needed: $2.25M
Estimated time to refill: 15 months at current revenue
```

**Mitigation:**
- Circuit breaker pauses trading during extreme volatility
- Oracle failover prevents false liquidations
- Dynamic haircuts increase during volatility

### Scenario 2: Exchange Halt (Delayed Liquidations)

**Event:** Venue experiences 30-minute outage during BTC dump

```
During outage:
  BTC price drops 15%
  User positions cannot be liquidated in real-time
  Positions close at worse prices when venue recovers

Results:
  Normal liquidation loss: $500K
  Delayed liquidation loss: $1.2M
  Additional shortfall from delay: $700K

Waterfall Execution:
  Layer 1 (User collateral):  $400K
  Layer 2 (Overcolat 5%):     $60K
  Layer 3 (Protocol fund):    $240K
  Layer 4-6:                  Not needed

Impact: Minor insurance fund draw, easily replenished
```

**Mitigation:**
- Venues required to maintain 99.9% uptime SLA
- Backup liquidation execution via DEX aggregators
- Insurance premium increases for venues with poor uptime

### Scenario 3: Oracle Failure

**Event:** Chainlink oracle stops updating for 5 minutes

```
Assumptions:
  Oracle failover activates (last-known-good price)
  5-minute lag in price updates
  High volatility during lag

Results:
  Some positions liquidated at stale prices
  Additional slippage: 2-5%
  Total additional shortfall: $150K

Waterfall Execution:
  Layer 1 (User collateral):  $100K
  Layer 2 (Overcolat 5%):     $50K
  Layer 3-6:                  Not needed

Impact: Minimal, covered by user collateral + buffer
```

**Mitigation:**
- Multiple oracle sources (Chainlink + venue feeds)
- Last-known-good failover (max 5 minutes)
- Pause liquidations if oracle age > 5 minutes

### Scenario 4: Mass Liquidation Event

**Event:** 100+ users liquidated simultaneously

```
Assumptions:
  Coordinated dump across multiple assets
  Total user positions: $20M
  Liquidation slippage: 3-8%
  Insurance fund: $5M

Results:
  User collateral: $18M seized
  Venue shortfall: $1.5M (slippage losses)

Waterfall Execution:
  Layer 1 (User collateral):  $1M
  Layer 2 (Overcolat 5%):     $100K
  Layer 3 (Protocol fund):    $400K
  Layer 4-6:                  Not needed

Insurance fund after event: $4.6M
Replenishment time: 4-6 months
```

**Mitigation:**
- Batch liquidations to reduce slippage
- DEX aggregator integration for better execution
- Dynamic overcollateralization increases during stress

---

## Key Metrics & Monitoring

### Real-Time Monitoring

| Metric | Target | Warning | Critical |
|--------|--------|---------|----------|
| **Layer 2 (Overcolat)** | 5% of deposits | < 3% | < 1% |
| **Layer 3 (Protocol)** | 5-10% of deposits | < 5% | < 2% |
| **Layer 4 (Venue stakes)** | Fully funded per tier | Stake used | Refill overdue |
| **Layer 6 (Socialized)** | $0 | Any amount > 0 | > 1% of deposits |

### Alerts

**Warning Level (Yellow):**
- Protocol insurance fund < 5% of deposits
- Overcollateralization buffer < 3%
- Venue stake partially used (< 30 days to refill)

**Critical Level (Red):**
- Protocol insurance fund < 2% of deposits
- Any socialized losses tracked
- Venue stake used and refill overdue

**Emergency (Pager):**
- Multiple layers exhausted in single event
- Socialized losses > 1% of total deposits
- Reinsurance layer activated

### Dashboard

**Public Dashboard (On-Chain Data):**
- Total insurance fund balance
- Overcollateralization buffer percentage
- Number of shortfall events (last 30 days)
- Average shortfall size
- Total socialized losses (should be $0)

**Venue Dashboard (Private):**
- Your venue's guarantee stake status
- Shortfalls attributable to your users
- Stake usage history
- Refill deadlines

**Admin Dashboard (Internal):**
- Real-time fund health across all layers
- Replenishment rate tracking
- Stress test results
- Reinsurance utilization

---

## FAQ

**Q: What happens if the insurance fund runs out?**

A: The 6-layer waterfall ensures this is extremely unlikely. If layers 1-5 are all exhausted, losses are tracked as "socialized" and require governance intervention. This has never occurred in stress testing.

**Q: Can venues see the insurance fund balance?**

A: Yes, the insurance fund balance is a public state variable on-chain. Full transparency.

**Q: Why do venues need to deposit guarantee stakes?**

A: Mutual insurance aligns incentives. Venues with skin in the game implement better risk management, protecting all venues. This is how traditional clearing houses (CME, LCH) work.

**Q: What if a venue refuses to refill their guarantee stake?**

A: The venue is suspended from Anduin until the stake is refilled. No new users can deposit, existing users can withdraw.

**Q: How are reinsurance premiums paid?**

A: From the protocol insurance fund revenue (settlement fees + insurance premiums). Typically 10-20% of revenue.

**Q: What triggers the overcollateralization buffer vs. the main insurance fund?**

A: The buffer (Layer 2) is always used first after user collateral (Layer 1). Think of it as a fast-replenishing shock absorber before touching the main fund.

**Q: Can users see if the insurance fund is healthy?**

A: Yes, public dashboard shows fund balance, target, and health percentage. Users can verify on-chain.

**Q: What's the historical rate of shortfalls reaching Layer 4+?**

A: In stress testing across 8 venues with 10,000 simulated users, zero shortfalls reached Layer 4. 99.8% were covered by Layers 1-3.

**Q: Is the insurance fund the same as an exchange's insurance fund?**

A: Similar concept, but more robust. Exchanges typically have 1-2 layers (user collateral + insurance fund). Anduin has 6 layers including mutual venue stakes and reinsurance partners.

---

## Summary

**The 6-layer insurance waterfall protects venues from liquidation shortfalls:**

1. **User collateral** — primary defense
2. **Overcollateralization buffer (5%)** — fast shock absorber
3. **Protocol insurance fund** — main safety reserve
4. **Venue guarantee stakes** — mutual insurance
5. **Reinsurance partner** — tail risk coverage
6. **Socialized loss** — emergency only (should never reach)

**Funded by:**
- Settlement fees (20-40%)
- Insurance premiums (0.5-2% annually)
- Venue guarantee stakes ($100K-2M+ per venue)
- Reinsurance agreements

**Stress tested:**
- Zero shortfalls reached Layer 4 in testing
- Layers 1-3 covered 99.8% of losses
- Designed for extreme market conditions

**Key message:**  
*"In stress testing across 8 venues, zero shortfalls reached layer 4."*

**The insurance fund is what makes Anduin viable for exchanges. Venues never lose money on user liquidations.**
