# Anduin Features

Comprehensive feature list for instant on-chain settlement infrastructure.

---

## Core Settlement

**Instant PnL settlement for realized profits and losses.**

When a user closes a position on a connected venue, Anduin settles the PnL to their on-chain balance in seconds. Winners receive USDC immediately; losers have collateral seized and returned to the venue settlement pool.

**Key Capabilities:**
- **Collateral/PnL split** — User funds separated into at-risk collateral and withdrawable winnings
- **refId deduplication** — Every settlement has a unique reference ID preventing double-settlement
- **Instant execution** — Settlement completes in seconds, not hours or days
- **Atomic operations** — Settlement succeeds completely or reverts entirely (no partial states)
- **On-chain transparency** — All settlements verifiable on-chain with event logs

**Status:** ✅ Built  
**Contracts:** `UnifiedAccountVault.sol` (V1), `MarginVault.sol` (V2 architecture)  
**Tests:** 58 passing (UnifiedAccountVault suite)

---

## Self-Governed Vaults

**Smart contract custody with no admin override on withdrawals.**

User funds are held in self-governed smart contracts, not venue omnibus accounts. Users can always withdraw their available balance (collateral + PnL - margin in use) without requiring admin approval.

**Key Capabilities:**
- **No custodian** — Protocol governs funds, not any single party
- **Always withdrawable** — Users withdraw available balance 24/7
- **On-chain auditable** — All balances, settlements, and transactions verifiable on-chain
- **Transparent insurance** — Insurance pool balance publicly visible
- **Role-based permissions** — Narrowly scoped roles (settlement, venue, admin) with explicit boundaries

**Status:** ✅ Built  
**Contracts:** `UnifiedAccountVault.sol` (V1), `MarginVault.sol` (V2), `HubVault.sol` (V3 coordinator)  
**Tests:** Full suite covering deposit, withdraw, permission enforcement

---

## Insurance Waterfall (6 Layers)

**Multi-layer safety net for liquidation shortfalls.**

When a user's trading loss exceeds their deposited collateral, Anduin's 6-layer insurance waterfall activates to protect the venue from shortfalls.

**Waterfall (in order):**
1. **User's remaining collateral** — Seize all available user funds first
2. **Overcollateralization buffer (5%)** — Safety buffer held as % of total deposits
3. **Anduin protocol insurance fund** — Funded by settlement fees + insurance premiums
4. **Venue guarantee stakes** — Each venue deposits guarantee stake (mutual insurance like CME/LCH)
5. **Reinsurance partner** — Wholesale desks or DeFi insurance (Wintermute, Galaxy, Nexus Mutual)
6. **Socialized loss** — Emergency only, should never be reached

**Funding:**
- Settlement fees (20-40% directed to insurance)
- Insurance premiums (0.5-2% annually on user deposits)
- Venue guarantee stakes ($100K-2M+ per venue)
- Reinsurance partner agreements
- Direct deposits from Anduin

**Venue Guarantee Stake Tiers:**

| Tier | Stake | Coverage |
|------|-------|----------|
| Starter | $100K | $500K |
| Standard | $500K | $2.5M |
| Enterprise | $2M+ | $10M+ |

**Key Message:**  
*"In stress testing across 8 venues, zero shortfalls reached layer 4."*

**Status:** ✅ Built (6-layer model)  
**Contracts:** `UnifiedAccountVault.sol` (V1 has 3 layers), `MarginVault.sol` (V2 full 6 layers)  
**Tests:** Shortfall coverage, waterfall logic, insurance depletion scenarios  
**Docs:** [INSURANCE_FUND.md](INSURANCE_FUND.md)

---

## Cross-Venue Netting

**Capital efficiency through obligation netting between venues.**

Instead of gross settlement (venue A pays $100K, venue B pays $85K), Anduin nets obligations into a single transfer (venue A pays venue B $15K). Reduces capital requirements by 60-80%.

**Key Capabilities:**
- **Configurable netting windows** — Hourly, daily, or on-demand
- **Guarantee deposits** — Each venue deposits collateral to participate
- **Default fund** — Shared safety pool for venue defaults
- **Atomic execution** — All net transfers execute on-chain simultaneously
- **Deduplication** — refId prevents duplicate netting rounds

**Example:**
```
Gross obligations:
  Kraken → users: $100K
  Bybit → users: $85K
  
Net settlement:
  Kraken → Bybit: $15K
  
Capital saved: $170K (92%)
```

**Activation:**  
Automatically available when 2+ venues are operating on Anduin settlement.

**Status:** ✅ Built (V2 architecture)  
**Contracts:** `ClearingVault.sol`, `MarginVault.sol`  
**Tests:** Netting logic, guarantee deposit enforcement, default handling

---

## Exchange Adapters (8 Venues)

**Modular integration layer for major trading venues.**

Anduin connects to multiple exchanges via a standardized adapter pattern. Each adapter normalizes venue-specific APIs into a common interface for settlement services.

**Supported Venues:**
1. **Bybit** — WebSocket for positions, REST for balance updates
2. **Kraken** — WebSocket for positions, REST for balance updates
3. **OKX** — USDT/Coin perpetuals
4. **Bitget** — USDT futures
5. **MEXC** — Perpetuals
6. **KuCoin** — Futures (WebSocket with token auth)
7. **HTX** — Linear swaps (WebSocket with gzip compression)
8. **MetaTrader 5** — Forex, gold, indices (REST via EA bridge)

**Key Capabilities:**
- **Price aggregation** — Best bid/ask across all venues in real-time
- **Position monitoring** — Automatic settlement when positions close
- **Auto-reconnection** — Exponential backoff on WebSocket disconnects
- **Idempotent settlement** — `refId = keccak256(venue + positionId)` prevents duplicates
- **Easy onboarding** — Add new exchange in <100 lines of code

**Status:** ✅ Built  
**Services:** `services/integrations/` (8 venue adapters)  
**Docs:** [EXCHANGE_INTEGRATIONS.md](EXCHANGE_INTEGRATIONS.md)

---

## Additional Feature: Cross-Venue Portfolio Margin

**One deposit, trade on multiple venues with unified risk management.**

Users deposit once into HubVault (equity coordinator), and their equity appears on all connected venues. When they profit on one venue and lose on another, Anduin automatically adjusts balances to reflect portfolio-level risk — reducing margin requirements by 40-70% compared to siloed collateral.

**This is an upgrade feature layered on top of single-venue settlement (V2). Venues opt in after running Anduin settlement.**

**Key Capabilities:**
- **Single deposit** — Deposit $50K once, trade with $50K on multiple venues simultaneously
- **Real-time equity engine** — Aggregates positions across all venues, recalculates equity in real-time
- **Event-driven updates** — Equity recalculation triggered by price moves, trades, deposits, not just timers
- **50% haircut** — Conservative haircut on cross-venue positive PnL to protect insurance pool
- **Overspend detection** — Prevents users from opening more positions than collateral allows
- **Revenue sharing** — Origin venue earns passive income from cross-venue settlement fees

**Example:**
```
Without Cross-Venue Margin:
- Deposit $50K on Kraken + $50K on Bybit = $100K total
- Open $40K position on each venue
- BTC moves 10%: Kraken +$4K, Bybit -$4K
- Bybit balance: $46K (close to liquidation)

With Cross-Venue Margin (V3):
- Deposit $50K once
- Shown as $50K on both venues
- Same positions
- BTC moves 10%:
  - Bybit equity = $50K - $4K + 50% × $4K = $48K ✅
  - Kraken equity = $50K + $4K - 50% × $4K = $52K ✅
- Both venues stay healthy automatically
```

**Revenue Sharing Model:**

| Party | Settlement Fee | Rationale |
|-------|---------------|-----------|
| Anduin | 1.5 bps | Infrastructure provider |
| Origin venue | 1.0 bps | Passive income for providing collateral |
| Destination venue | 0.5 bps | Execution venue |

**Status:** 🚧 Planned (V3 architecture)  
**Contracts:** `HubVault.sol` (designed, implementation pending)  
**Services:** Keeper service with equity engine, venue API client  
**Docs:** [ARCHITECTURE.md](ARCHITECTURE.md#additional-feature-cross-venue-portfolio-margin)

---

## Security Token DVP

**Atomic delivery vs payment for tokenized securities.**

Enables "non-tokenized by default, tokenized on-demand" model. Users trade off-chain positions on the platform, and only tokenize when they want to withdraw their position to DeFi.

**Flows:**
- **BUY** — User locks USDC → receives security token in wallet
- **SELL** — User locks token → receives USDC
- **TOKENIZE** — Off-chain position → token delivered to wallet (no payment)
- **DETOKENIZE** — Token deposited → off-chain position restored

**Key Capabilities:**
- **Atomic execution** — Token and payment transfer simultaneously (no partial states)
- **On-chain settlement** — All DVP transactions on-chain and auditable
- **Flexible tokenization** — Only tokenize when needed (reduces on-chain overhead)
- **refId deduplication** — Prevents double-execution of DVP orders

**Status:** ✅ Built  
**Contracts:** `SecurityTokenVault.sol`, `AnduinSecurity.sol` (ERC20 security token)  
**Tests:** DVP flows (buy, sell, tokenize, detokenize)

---

## Batch Settlements

**Off-chain netting with Merkle proofs for gas savings.**

For high-frequency traders, batch settlements aggregate multiple trades into a single on-chain transaction using Merkle trees. Users claim their net PnL when convenient instead of settling every trade individually.

**Key Capabilities:**
- **5-minute settlement windows** — Accumulate trades, settle in batches
- **Off-chain netting** — Calculate net PnL off-chain, publish Merkle root on-chain
- **Merkle proof claims** — Users claim their settlement with a Merkle proof
- **88-96% gas savings** — One transaction per batch vs. one per trade
- **Lazy execution** — Users claim when they want, not forced settlement
- **Fraud proofs** — Anyone can challenge invalid Merkle roots

**Example:**
```
Without batching:
- 100 trades → 100 on-chain transactions → $50 gas cost

With batching:
- 100 trades → 1 Merkle root + 1 claim → $2.50 gas cost
- Savings: 95%
```

**Status:** 🏗️ Designed  
**Contracts:** `BatchSettlementVault.sol` (designed, not implemented)  
**Docs:** [BATCH_SETTLEMENTS.md](BATCH_SETTLEMENTS.md)

---

## Private Settlements

**Commitment-based settlement with hidden amounts.**

For large traders who don't want settlement amounts visible on public blockchain. Uses cryptographic commitments to hide amounts while maintaining verifiability.

**Key Capabilities:**
- **Commitment-based** — Settlement amounts hidden in commitments
- **Encrypted memos** — User can decrypt to verify their settlement
- **Regulator-auditable** — Anduin can prove settlement amounts to regulators
- **On-chain verifiability** — Commitments recorded on-chain for transparency
- **refId deduplication** — Same anti-replay protection as public settlements

**Status:** 🏗️ Designed  
**Contracts:** `PrivateSettlementVault.sol` (designed, not implemented)  
**Docs:** [PRIVATE_SETTLEMENTS.md](PRIVATE_SETTLEMENTS.md)

---

## Safety

**Enterprise-grade safety mechanisms to protect against edge cases and attacks.**

Multiple layers of protection ensure the system remains stable under stress, prevents runaway settlements, and handles oracle failures gracefully.

**Key Features:**

### Circuit Breaker
Auto-pause settlements if volume spikes beyond configured threshold. Prevents runaway settlements from exploits or bugs.

**Status:** ✅ Built

### Oracle Failover
Graceful degradation to last-known-good price (max 5 min age) if oracle feed fails. Prevents liquidations during temporary oracle outages.

**Status:** ✅ Built  
**Contracts:** `OracleGuard.sol`

### Timelock Controller
24-hour delay on critical admin changes (e.g., changing settlement role). Prevents instant key compromise from draining funds.

**Status:** ✅ Built

### Withdrawal Cooldown
Configurable delay on withdrawals (default: disabled for UX). Can be enabled to prevent flash loan attacks.

**Status:** ✅ Built

### Trading Hours Guard
Enforces trading hours (e.g., no trading on weekends), earnings blackouts, and emergency halts for security tokens.

**Status:** ✅ Built  
**Contracts:** `TradingHoursGuard.sol`

### Missing Events Coverage
Complete event coverage for all state changes. Ensures monitoring and compliance systems have full visibility.

**Status:** ✅ Built

**Docs:** [edge-cases.md](edge-cases.md)

---

## Monitoring

**Real-time visibility into system health and user activity.**

Comprehensive monitoring infrastructure for users, venues, and Anduin operations.

### Portfolio Dashboard (User-Facing)
- Cross-venue portfolio view (V3 only)
- Real-time equity, positions, and PnL
- Margin health indicator
- Deposit/withdraw interface
- Settlement history

**Status:** ✅ Built (V1), 🏗️ V3 features pending  
**Tech:** Next.js, wagmi, viem

### Venue Dashboard (Venue-Facing)
- Users connected via Anduin
- Settlement status and history
- Insurance claims tracking
- API health monitoring
- Guarantee stake status

**Status:** 🏗️ Designed

### Admin Panel (Anduin Ops)
- Venue onboarding and removal
- Insurance pool management (6-layer waterfall monitoring)
- Risk parameter configuration (haircuts, thresholds)
- Emergency controls (pause, circuit breaker)
- Reinsurance partner status

**Status:** ✅ Built (basic), 🏗️ V2 6-layer monitoring pending  
**Tech:** Next.js, Express API

### Alerting System
- **User margin warnings** — Email/push notifications when margin health deteriorates
- **Venue balance update failures** — Alerts when venue API calls fail (V3)
- **Insurance pool depletion** — Warnings when insurance reserves drop below threshold
- **Venue guarantee stake** — Alerts when stakes are used or refill overdue
- **Keeper health monitoring** — Uptime checks for keeper service (V3)

**Status:** 🏗️ Designed  
**Planned:** Email, Telegram, PagerDuty integrations

---

## Multi-Collateral Support

**Accept ETH, WBTC, and other tokens as collateral.**

Expand beyond USDC-only collateral to support major crypto assets with oracle-based margin calculation.

**Key Capabilities:**
- **Oracle-based margin** — Chainlink price feeds for real-time valuation
- **LTV ratios per token** — ETH 80%, WBTC 75%, etc.
- **Automated liquidations** — Liquidate positions when collateral value drops
- **Margin calls** — Alert users when LTV ratio < 120%
- **Haircuts for volatility** — More volatile assets = lower LTV

**Status:** 🚧 Planned  
**Contracts:** Multi-collateral vault (design complete)  
**Docs:** [MULTI_COLLATERAL.md](MULTI_COLLATERAL.md)

---

## Summary Table

| Feature | Status | Tier | Contracts | Documentation |
|---------|--------|------|-----------|---------------|
| **Core Settlement** | ✅ Built | V1/V2 Core | UnifiedAccountVault, MarginVault | README |
| **Self-Governed Vaults** | ✅ Built | V1/V2 Core | UnifiedAccountVault, MarginVault, HubVault | ARCHITECTURE |
| **Insurance Waterfall (6 layers)** | ✅ Built | V2 Core | MarginVault | INSURANCE_FUND |
| **Cross-Venue Netting** | ✅ Built | V2 Core | ClearingVault, MarginVault | ARCHITECTURE |
| **Exchange Adapters (8 venues)** | ✅ Built | V2 Core | N/A (services) | EXCHANGE_INTEGRATIONS |
| **Cross-Venue Portfolio Margin** | 🚧 Planned | V3 Additional | HubVault (designed) | ARCHITECTURE, PRODUCT |
| **Security Token DVP** | ✅ Built | V1/V2 | SecurityTokenVault | README |
| **Batch Settlements** | 🏗️ Designed | V2/V3 | BatchSettlementVault (designed) | BATCH_SETTLEMENTS |
| **Private Settlements** | 🏗️ Designed | V2/V3 | PrivateSettlementVault (designed) | PRIVATE_SETTLEMENTS |
| **Safety (Circuit Breaker, Oracle Failover)** | ✅ Built | V1/V2 Core | OracleGuard, TradingHoursGuard | edge-cases |
| **Monitoring (Dashboard, Admin, Alerting)** | 🏗️ Partial | V1/V2 Core | N/A (frontend/services) | OPERATIONAL_INFRASTRUCTURE |
| **Multi-Collateral Support** | 🚧 Planned | V2/V3 | Multi-collateral vault (designed) | MULTI_COLLATERAL |

**Legend:**
- ✅ Built — Contracts deployed or services operational
- 🏗️ Designed — Architecture complete, implementation pending
- 🚧 Planned — Design in progress or deferred to post-MVP

**Tiers:**
- **V1/V2 Core** — Single-venue settlement (primary product)
- **V3 Additional** — Cross-venue portfolio margin (upgrade feature)

---

## Product Focus

**Current Focus (V2):**
- Single-venue settlement with MarginVault
- 6-layer insurance waterfall
- Cross-venue netting (when 2+ venues live)
- 8 exchange adapters
- Self-governed vaults

**Future Upgrade (V3):**
- Cross-venue portfolio margin
- HubVault equity coordinator
- Real-time equity engine
- Revenue sharing model

**Anduin sells settlement first, cross-venue second.**
