# Anduin

**Cross-Venue Portfolio Margin Infrastructure**

## Overview

Anduin enables traders to use a single pool of collateral across multiple crypto exchanges and trading venues, while protecting venues from cross-venue risk. Users deposit once into Anduin's self-governed smart contract, and their equity appears on all connected venues. When they profit on one venue and lose on another, Anduin automatically adjusts balances to reflect portfolio-level risk—reducing margin requirements by 40-70% compared to siloed collateral.

## Core Features

### 1. **HubVault** — Self-Governed Smart Contract
- Single global vault holding all user funds
- Deposit/withdraw USDC anytime (no admin override on withdrawals)
- Per-user collateral accounting
- On-chain transparency and auditability
- Insurance pool for shortfall coverage

### 2. **Cross-Venue Equity Engine** — Portfolio Margin
- Aggregates positions across all connected venues in real-time
- Calculates equity with configurable haircuts (default 50% on cross-venue positive PnL)
- Event-driven updates triggered by:
  - Price moves exceeding thresholds (e.g., BTC >1%, Gold >0.5%)
  - Position opens/closes on any venue
  - Deposits/withdrawals
  - Heartbeat fallback (every 5 minutes)
  - Manual triggers
- Overspend detection and automatic intervention

### 3. **Venue Credit Propagation** — Balance Management
- Propagates deposits to all connected venues via API
- Updates equity on venues after each recalculation
- Reduces balances to trigger venue's own liquidation when user overspends
- Freezes new orders when user approaches limits
- Venues keep their existing margin engines and liquidation systems

### 4. **Reinsurance Pool** — Shortfall Coverage
- Covers venue liquidation shortfalls via insurance waterfall:
  1. User's remaining collateral (across all venues)
  2. Insurance pool
  3. Socialized loss (if both insufficient)
- Funded by insurance premiums, settlement fees, and direct deposits
- Transparent on-chain balance

### 5. **Cross-Venue Netting** — Capital Efficiency
- Nets obligations between venues via ClearingVault
- Reduces gross settlement volume by 60-80%
- Configurable netting windows
- Atomic on-chain execution with deduplication

### 6. **Settlement Engine** — PnL Settlement
- Instant intra-venue settlement
- Netted cross-venue settlement
- All settlements deduplicated by refId

### 7. **Portfolio Dashboard** — User Interface
- Cross-venue portfolio view
- Real-time equity, positions, and PnL
- Margin health indicator
- One-click deposit/withdraw

### 8. **Venue Dashboard** — Exchange Interface
- List of users connected via Anduin
- Settlement status and history
- Insurance claims tracking
- API health monitoring

### 9. **Admin Panel** — Operations
- Venue onboarding and removal
- Insurance pool management
- Risk parameter configuration (haircuts, thresholds, max allocations)
- Emergency controls

### 10. **Alerting System**
- User margin warnings (email/push notifications)
- Venue balance update failures
- Insurance pool depletion alerts
- Keeper service health monitoring

## Target Customers

### Primary
- **Crypto Exchanges** (Kraken, Bybit, Binance, etc.)
  - Reduce user margin requirements → more volume
  - Insurance against liquidation shortfalls → less counterparty risk
  - Access Anduin's user network → new customers

- **CFD Brokers** (leveraged trading platforms)
  - Offer multi-asset portfolio margin
  - Reinsurance for client losses
  - Competitive advantage vs. single-venue brokers

- **OTC Desks** (Prime brokers, market makers)
  - Cross-venue credit lines
  - Reduced capital requirements
  - Netting across counterparties

### Secondary
- **Institutional Traders** (prop firms, hedge funds)
  - Trade on multiple venues with unified risk management
  - Reduce locked collateral by 40-70%
  - Simplified treasury operations

## How Venues Integrate

### What Venues Provide

| Component | Type | Description |
|-----------|------|-------------|
| Balance API | REST | Endpoint to set/update user balance |
| Position Feed | WebSocket | Real-time position data stream |
| Order Freeze API | REST | Endpoint to stop new orders for a user |
| Settlement Callback | Webhook | Notify Anduin of liquidations |
| API Credentials | Auth | Secure communication keys |

### What Venues Get

| Benefit | Impact |
|---------|--------|
| **More Volume** | Users trade 2-3x bigger on portfolio margin |
| **Less Risk** | Insurance covers liquidation shortfalls |
| **New Users** | Access Anduin's network of cross-venue traders |
| **Capital Efficiency** | Cross-venue netting reduces settlement obligations |
| **Zero Infrastructure** | No smart contract integration required—just REST APIs |

### Integration Process

1. **Onboarding** — Submit API documentation, receive Anduin adapter
2. **Sandbox Testing** — Test balance propagation with mock positions
3. **Integration Verification** — Checklist of required endpoints
4. **Go-Live** — Gradual rollout with monitoring

## Revenue Model

| Revenue Stream | Description | Pricing |
|---------------|-------------|---------|
| **Settlement Fees** | Per-settlement fee on realized PnL | 1-5 bps |
| **Insurance Premium** | Annual fee on user deposits (charged to venues) | 0.5-2% |
| **Equity Update Service** | Per-user monthly fee to venues for balance updates | $1-5/user/month |
| **Netting Fees** | Fee on capital saved through cross-venue netting | 0.5-1 bps of netted amount |
| **Integration Fee** | One-time venue onboarding (white-glove service) | $25K-100K |

**Revenue Example (Year 1):**
- 5 venues integrated
- 10,000 active users
- $500M average deposits
- $50B monthly trading volume

| Stream | Calculation | Annual Revenue |
|--------|-------------|----------------|
| Settlement Fees | $50B/mo × 12 × 0.03% | $1.8M |
| Insurance Premium | $500M × 1% | $5M |
| Equity Updates | 10K users × $3/user/mo × 12 | $360K |
| Netting Fees | $5B netted × 0.01% | $500K |
| Integration Fees | 5 venues × $50K | $250K |
| **Total** | | **$7.9M** |

## Comparison: Without vs. With Anduin

### Scenario: Trader with $50K USDC

**Without Anduin (Today):**
- User deposits $50K on Kraken, $50K on Bybit → **$100K total**
- Opens $40K position on Kraken (Long BTC)
- Opens $40K position on Bybit (Short BTC)
- BTC moves 10%:
  - Kraken: +$4K unrealized PnL → equity = $54K ✅
  - Bybit: -$4K unrealized PnL → equity = $46K ❌ (close to liquidation)
- User needs to manually transfer funds between venues to rebalance

**With Anduin:**
- User deposits $50K into Anduin → **$50K total** (50% capital savings)
- Anduin shows $50K on both Kraken and Bybit
- Opens same positions
- BTC moves 10%:
  - Anduin recalculates equity:
    - Kraken equity = $50K + $4K + 50% × (-$4K haircut) = $52K ✅
    - Bybit equity = $50K - $4K + 50% × (+$4K haircut) = $48K ✅
  - Both venues stay healthy automatically
- No manual rebalancing needed

**Capital Efficiency:**
- Without Anduin: $100K locked
- With Anduin: $50K locked
- **Savings: 50%**

---

## Technical Architecture

### Smart Contracts (Deployed on Ethereum/Arbitrum/Base)

1. **HubVault.sol** — Global vault, per-user accounting
2. **ClearingVault.sol** — Cross-venue netting and settlement
3. **IHubVault.sol** — Interface for external integrations

### Off-Chain Services

1. **Keeper Service** — Equity engine + venue API client
   - Price Monitor — Watches oracles and venue feeds
   - Position Monitor — Reads positions via WebSocket/REST
   - Equity Engine — Calculates portfolio equity with haircuts
   - Venue API Client — Updates balances on venues
   - On-Chain Settler — Calls HubVault functions

2. **API Gateway** — Venue adapter layer
   - Normalizes venue-specific APIs into standard interface
   - Per-venue adapter modules
   - Rate limiting and retry logic

3. **Monitoring & Alerting**
   - User margin health alerts
   - Venue API health checks
   - Insurance pool balance monitoring
   - Keeper service uptime

### Security Model

| Component | Trust Assumption | Risk Mitigation |
|-----------|------------------|-----------------|
| **HubVault** | Self-governed, no admin override on withdrawals | Users can always withdraw available balance |
| **Keeper** | Only off-chain component with write access | Keeper CANNOT withdraw user funds; actions bounded by collateral + haircut PnL |
| **Venues** | Report positions honestly | Anduin cross-checks with oracle prices; insurance covers shortfalls |
| **Insurance Pool** | Transparent on-chain balance | Publicly auditable; funded by multiple sources |

### Haircut Calibration

| Asset | Default Haircut | Rationale |
|-------|----------------|-----------|
| BTC/ETH | 50% | High volatility, 2% price moves common |
| Gold/Commodities | 40% | Lower volatility, more stable |
| Stablecoins | 10% | Minimal volatility, mostly for fees |

Haircuts are configurable per asset, per venue, and per volatility regime.

---

## Roadmap

### Phase 1: Testnet Demo (Q1 2025)
- HubVault deployed on testnet
- Mock venues (simulated APIs)
- Portfolio dashboard MVP
- Keeper service prototype

### Phase 2: Mainnet Launch (Q2 2025)
- HubVault deployed on Arbitrum
- 2-3 initial venue partners
- Full keeper service
- Insurance pool bootstrap ($1M)

### Phase 3: Scale (Q3-Q4 2025)
- 10+ venues integrated
- $100M+ deposits
- Multi-collateral support (ETH, BTC)
- Cross-chain expansion (Base, Optimism)

### Phase 4: Decentralization (2026)
- Governance token launch
- Community-governed risk parameters
- Keeper service decentralization (multiple operators)
- Open-source venue adapter SDK

---

## FAQ

**Q: What if Anduin's keeper goes down?**
A: Users can always withdraw their available balance directly from HubVault (no keeper needed). Venues continue operating with their last-known balances. Keeper downtime pauses equity updates but doesn't lock funds.

**Q: What if a venue refuses to honor Anduin's balance updates?**
A: Venue integration contracts require compliance. If a venue consistently ignores updates, Anduin governance can remove the venue from the registry.

**Q: What happens to the insurance pool if there are large losses?**
A: Insurance pool is replenished from settlement fees and premiums. If depleted, losses are socialized across remaining users (similar to exchange insurance funds).

**Q: Can venues see each other's users' positions?**
A: No. Anduin aggregates positions but doesn't share venue-specific data. Each venue only sees its own users' positions + their Anduin-managed balance.

**Q: Why would a user trust Anduin instead of keeping funds on the exchange?**
A: Anduin is a self-governed smart contract with no admin override on withdrawals. Users can verify their balance on-chain and withdraw anytime. Exchanges are custodial; Anduin is non-custodial.

---

## Contact

- **Website:** anduin.xyz (coming soon)
- **Twitter:** @AnduinFinance
- **Docs:** docs.anduin.xyz
- **Email:** partnerships@anduin.xyz

---

**Built for the era of multi-venue trading.**
