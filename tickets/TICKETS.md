# Anduin Settlement — Full Ticket Backlog

## Status Legend
- 🔴 **CRITICAL** — Must fix before production
- 🟠 **HIGH** — Important for MVP
- 🟡 **MEDIUM** — Should have
- 🟢 **DONE** — Implemented and tested
- ⚪ **TODO** — Not started
- 🔵 **MVP** — Part of initial €250k deliverable

---

## CRITICAL BUGS (Must Fix Before Production)

### VS-C001: seizeCollateral Missing refId — Double-Seize Risk 🔴
**Priority:** CRITICAL | **Estimate:** 0.5 day | **Status:** TODO

**Problem:**
`seizeCollateral` has no refId parameter, unlike `creditPnl`. Bridge retries can double-seize user funds on transient failures.

**Impact:**
- User loses collateral twice for same trade
- Silent data corruption
- Reconciliation breaks

**Fix:**
1. Add `refId` parameter to `seizeCollateral`
2. Add `usedRefIds` dedup mapping (same pattern as `creditPnl`)
3. Update bridge to pass `refIdToBytes32(refId)`
4. Add tests for retry scenarios

**Files:**
- `contracts/src/UnifiedAccountVault.sol`
- `services/src/bridge.ts`
- `contracts/test/UnifiedAccountVault.t.sol`

---

### VS-C002: OracleGuard and TradingHoursGuard Not Wired In 🔴
**Priority:** CRITICAL | **Estimate:** 1 day | **Status:** TODO

**Problem:**
Contracts exist but aren't integrated into settlement flow. Settlement can execute:
- Outside trading hours
- During halts
- With stale/manipulated prices

**Impact:**
- Regulatory violation (trading during halts)
- Price manipulation risk
- Loss of funds from bad pricing

**Fix:**
1. Deploy OracleGuard and TradingHoursGuard
2. Add guard addresses to UnifiedAccountVault and SecurityTokenVault
3. Add `requireTradingAllowed(symbolId)` check in settlement functions
4. Add `requireValidPrice(symbolId, price)` check
5. Update bridge to:
   - Check `TradingHoursGuard.canTrade()` before settlement
   - Fetch price from `OracleGuard.getValidatedPrice()`
   - Queue settlements during market closed
6. Write integration tests

**Files:**
- `contracts/src/UnifiedAccountVault.sol`
- `contracts/src/SecurityTokenVault.sol`
- `services/src/bridge.ts`
- New: `contracts/test/Integration.t.sol`

---

### VS-C003: SecurityTokenVault Has Zero Tests 🔴
**Priority:** CRITICAL | **Estimate:** 1.5 days | **Status:** TODO

**Problem:**
SecurityTokenVault handles DVP (delivery vs payment) for tokenized securities. Contract is written but completely untested. This handles real money and securities — cannot deploy without comprehensive tests.

**Fix:**
Write Foundry test suite covering:
1. **BUY flow:** User locks USDC → receives security token
2. **SELL flow:** User locks token → receives USDC
3. **TOKENIZE flow:** Off-chain position → token delivered (no payment)
4. **DETOKENIZE flow:** Token locked → off-chain position restored
5. **Edge cases:** insufficient balance, disabled tokens, daily limits
6. **Access control:** only settlement role can execute
7. **Idempotency:** duplicate refId handling
8. **Cancellations:** refund flows
9. **Pause:** all flows blocked when paused

**Files:**
- New: `contracts/test/SecurityTokenVault.t.sol`

---

## HIGH PRIORITY ISSUES

### VS-H001: Services Only Support UnifiedAccountVault 🟠
**Priority:** HIGH | **Estimate:** 1 day | **Status:** TODO

**Problem:**
Bridge, indexer, recon only work with UnifiedAccountVault (PnL settlement). No off-chain infrastructure for SecurityTokenVault (DVP).

**Fix:**
1. Create `services/src/security-bridge.ts` for DVP settlements
2. Update indexer to listen to SecurityTokenVault events
3. Update recon to compare broker DVP records vs on-chain
4. Add API endpoints for security token balances and settlements

**Files:**
- New: `services/src/security-bridge.ts`
- `services/src/indexer.ts`
- `services/src/recon.ts`
- `services/src/api.ts`

---

### VS-H002: Indexer Has Dead Hardcoded Topic0 Hashes 🟠
**Priority:** HIGH | **Estimate:** 0.25 day | **Status:** TODO

**Problem:**
Indexer has hardcoded event signature hashes that will break if contract changes or if we add new events.

**Fix:**
1. Generate topic0 from ABI at runtime using viem
2. Remove hardcoded hashes
3. Make event listening dynamic based on ABI

**Files:**
- `services/src/indexer.ts`

---

### VS-H003: No .env.example File 🟠
**Priority:** HIGH | **Estimate:** 0.25 day | **Status:** TODO

**Problem:**
No `.env.example` makes setup confusing for new developers.

**Fix:**
Create `.env.example` with all required variables and comments.

**Files:**
- New: `.env.example` (root)

---

### VS-H004: No Deployment Scripts for New Contracts 🟠
**Priority:** HIGH | **Estimate:** 0.5 day | **Status:** TODO

**Problem:**
SecurityTokenVault, OracleGuard, TradingHoursGuard have no deployment scripts.

**Fix:**
Create Foundry deploy scripts for all contracts with:
1. Constructor args from env
2. Role setup
3. Initial configuration
4. Verification

**Files:**
- New: `contracts/script/DeploySecurityTokenVault.s.sol`
- New: `contracts/script/DeployOracleGuard.s.sol`
- New: `contracts/script/DeployTradingHoursGuard.s.sol`

---

### VS-H005: Mock Broker Stores Settlements in Memory 🟠
**Priority:** HIGH | **Estimate:** 0.5 day | **Status:** TODO

**Problem:**
Mock broker stores settlements in memory. Server restart = data loss.

**Fix:**
1. Add SQLite persistence to mock broker
2. Store settlements in `mock_settlements` table
3. API still returns in-memory view for speed

**Files:**
- `services/src/mock-broker.ts`

---

## NEW FEATURES

### Epic: Private Transactions

### VS-F001: Private Settlement Design & Ticket 🟡
**Priority:** MEDIUM | **Estimate:** 1 day | **Status:** TODO

**Problem:**
All settlements are publicly visible on-chain:
- Settlement amounts
- User addresses
- Counterparties
- Trade direction

This is a privacy issue for:
- Large traders (don't want competitors seeing positions)
- Institutional clients (regulatory concerns)
- Retail users (general privacy)

**Design Requirements:**
1. Settlement amounts should not be public
2. User addresses can be pseudonymous (already are)
3. Consider: commitment schemes (hash-then-reveal), encrypted memos, private settlement pools
4. Pragmatic MVP approach — not full ZK rollup (too complex/expensive)

**Deliverables:**
1. Architecture doc: `docs/PRIVATE_SETTLEMENTS.md`
2. Product description in README
3. Smart contract design
4. Implementation plan with tickets

### VS-F002: Implement Private Settlement Contracts 🟡
**Priority:** MEDIUM | **Estimate:** 2 days | **Status:** Blocked by VS-F001

Implement the design from VS-F001.

---

### Epic: Batch Settlements

### VS-F010: Batch Settlement Design & Ticket 🟡
**Priority:** MEDIUM | **Estimate:** 1 day | **Status:** TODO

**Problem:**
Current settlement is trade-by-trade (one tx per settlement). For high-frequency traders:
- Expensive (gas per tx)
- Slow (mempool delays)
- Doesn't scale

**Design Requirements:**
1. Accumulate settlements over a window (e.g., 5 minutes)
2. Net settlements per user (100 wins + 50 losses = +50 net)
3. Submit one batched transaction
4. Verify integrity (Merkle root, signature, or proof)

**Deliverables:**
1. Architecture doc: `docs/BATCH_SETTLEMENTS.md`
2. Product description in README
3. Smart contract design (BatchSettlementVault or extension to UnifiedAccountVault)
4. Off-chain netting service design
5. Implementation plan with tickets

### VS-F011: Implement Batch Settlement System 🟡
**Priority:** MEDIUM | **Estimate:** 3 days | **Status:** Blocked by VS-F010

Implement the design from VS-F010.

---

### Epic: Multi-Collateral Support

### VS-F020: Multi-Collateral Design & Ticket 🟡
**Priority:** MEDIUM | **Estimate:** 1 day | **Status:** TODO

**Problem:**
Only USDC accepted as collateral. Users want to use:
- ETH
- WBTC (wrapped Bitcoin)
- Other tokens (USDT, DAI, etc.)

**Design Requirements:**
1. Multi-token collateral system
2. LTV ratios per token (e.g., ETH = 80%, WBTC = 75%)
3. Liquidation thresholds
4. Oracle price feeds (use OracleGuard)
5. Margin calls and liquidations
6. Settlements still in USDC (or allow multi-currency settlements?)

**Deliverables:**
1. Architecture doc: `docs/MULTI_COLLATERAL.md`
2. Product description in README
3. Smart contract design (MultiCollateralVault)
4. Liquidation service design
5. Integration with OracleGuard for price validation
6. Implementation plan with tickets

### VS-F021: Implement Multi-Collateral Vault 🟡
**Priority:** MEDIUM | **Estimate:** 3 days | **Status:** Blocked by VS-F020

Implement the design from VS-F020.

---

### Epic: Prime Layer (Cross-Venue Netting)

### VS-F030: Prime Layer Architecture 🟠
**Priority:** HIGH | **Estimate:** 2 days | **Status:** TODO

**Design:**
Users have ONE funded smart contract (a "prime account"):
- Deposit collateral once
- Trade on multiple connected venues from that single account
- Pre-trade margin checks across venues
- Cross-venue position netting (long on Venue A, short on Venue B = netted exposure)
- Periodic settlement (hourly/daily) with default waterfall
- Venues share liquidity pool

**Deliverables:**
1. Full architecture doc: `docs/PRIME_ARCHITECTURE.md`
2. Product description (update README, PRODUCT_LINES.md)
3. Smart contract design (PrimeAccountVault)
4. Venue integration spec
5. Settlement waterfall logic
6. Margin calculation service

### VS-F031: Implement Prime Layer Contracts 🟡
**Priority:** MEDIUM | **Estimate:** 5 days | **Status:** Blocked by VS-F030

Implement the Prime Layer contracts.

### VS-F032: Implement Prime Layer Services 🟡
**Priority:** MEDIUM | **Estimate:** 3 days | **Status:** Blocked by VS-F030

Implement the Prime Layer off-chain services.

---

## Epic 1: Core Smart Contracts (PnL Settlement)

### VS-001: UnifiedAccountVault Contract 🟢 MVP
**Priority:** P0 | **Estimate:** 1 day | **Status:** DONE

Core vault managing per-user collateral and PnL sub-ledgers with broker pool.

**Implemented:**
- ✅ Per-user mappings: collateral, pnl
- ✅ Broker pool balance tracking
- ✅ `depositCollateral`, `withdrawCollateral`, `withdrawPnL`
- ✅ `creditPnl` (idempotent via refId)
- ✅ `seizeCollateral`
- ✅ `brokerDeposit`, `brokerWithdraw`
- ✅ `pause()` / `unpause()`
- ✅ Per-user + global daily withdrawal caps
- ✅ All events implemented
- ✅ Role-based access (admin, settlement, broker)

### VS-002: MockUSDC Contract 🟢 MVP
**Priority:** P0 | **Estimate:** 0.5 day | **Status:** DONE

- ✅ Standard ERC20 with mint function
- ✅ 6 decimals

### VS-003: Contract Tests 🟢 MVP
**Priority:** P0 | **Estimate:** 1 day | **Status:** DONE (57 tests passing)

- ✅ Happy paths (win/loss settlement)
- ✅ Idempotency tests
- ✅ Access control tests
- ✅ Cap enforcement tests
- ✅ Pause tests
- ✅ Edge case tests

### VS-004: Deployment Scripts 🟡 MVP
**Priority:** P0 | **Estimate:** 0.5 day | **Status:** Blocked (needs deployer wallet)

- ⚪ Deploy to Base Sepolia
- ⚪ Set roles from env vars
- ⚪ Mint test USDC

---

## Epic 2: Backend Services

### VS-005: Mock Broker Service 🟢 MVP
**Priority:** P0 | **Estimate:** 0.5 day | **Status:** DONE

- ✅ REST API for PnL settlement events
- ✅ Mock settlement generation

### VS-006: Broker Bridge Service 🟢 MVP
**Priority:** P0 | **Estimate:** 1 day | **Status:** DONE

- ✅ Polls broker for realized PnL
- ✅ Calls creditPnl/seizeCollateral
- ✅ Idempotent deduplication
- ✅ Retry with backoff

### VS-007: Indexer Service 🟢 MVP
**Priority:** P1 | **Estimate:** 1 day | **Status:** DONE

- ✅ Listens to vault events
- ✅ SQLite state database
- ✅ APIs for state queries

### VS-008: Recon Service 🟢 MVP
**Priority:** P1 | **Estimate:** 0.5 day | **Status:** DONE

- ✅ Broker vs on-chain comparison
- ✅ Break detection and aging

### VS-009: API Gateway 🟢 MVP
**Priority:** P1 | **Estimate:** 0.5 day | **Status:** DONE

- ✅ Unified REST API
- ✅ CORS for frontend

---

## Epic 3: Frontend

### VS-010: Dashboard Frontend 🟢 MVP
**Priority:** P1 | **Estimate:** 1.5 days | **Status:** DONE

- ✅ Vault overview panel
- ✅ User balance panel
- ✅ Deposit/withdraw actions
- ✅ Settlement feed
- ✅ Recon panel
- ✅ Admin panel
- ✅ Wallet connection (wagmi)

---

## Summary by Priority

| Priority | Count | Description |
|----------|-------|-------------|
| 🔴 CRITICAL | 3 | Must fix before production |
| 🟠 HIGH | 5 | Important for MVP |
| 🟡 MEDIUM | 10+ | Nice to have / future features |
| 🟢 DONE | 10 | Completed |

---

## Epic 4: Operational Infrastructure (NEW)

### VS-OPS001: API Routes for Admin/Insurance Operations 🟠
**Priority:** HIGH | **Estimate:** 1 day | **Status:** TODO

**Problem:**
Admin panel and dashboard exist but API routes for admin operations are missing.

**Fix:**
Create API routes in `services/api/routes/`:
1. **Admin routes** (`admin.ts`):
   - POST `/api/system/pause` — Pause all vaults
   - POST `/api/system/unpause` — Resume all vaults
   - GET `/api/system/status` — Get vault status
2. **Insurance routes** (`insurance.ts`):
   - GET `/api/insurance/balance` — Get insurance fund balance
   - POST `/api/insurance/deposit` — Admin deposit to insurance
   - POST `/api/insurance/withdraw` — Admin withdraw from insurance
   - GET `/api/insurance/events` — Get insurance event history
3. **Audit routes** (`audit.ts`):
   - GET `/api/audit` — Get audit log with pagination

Connect to database.ts for persistence.

**Files:**
- New: `services/api/routes/admin.ts`
- New: `services/api/routes/insurance.ts`
- New: `services/api/routes/audit.ts`
- Update: `services/api/server.ts` to mount routes

---

### VS-OPS002: Integrate Database into Settlement Engine 🟠
**Priority:** HIGH | **Estimate:** 0.5 day | **Status:** TODO

**Problem:**
Settlement engine still uses in-memory Maps. Need to switch to SQLite persistence.

**Fix:**
1. Update `services/api/services/settlement-engine.ts`:
   - Replace all Map operations with database calls
   - Use `settlementDb.create()`, `settlementDb.findById()`, etc.
2. Update `services/api/routes/settlements.ts`:
   - Query database instead of in-memory store
3. Update `services/api/routes/clients.ts`:
   - Query database instead of in-memory store

**Files:**
- `services/api/services/settlement-engine.ts`
- `services/api/routes/settlements.ts`
- `services/api/routes/clients.ts`

---

### VS-OPS003: Keeper Integration with Exchange Adapters 🟡
**Priority:** MEDIUM | **Estimate:** 2 days | **Status:** TODO

**Problem:**
Keeper has placeholder code for polling exchange adapters. Need real integration.

**Fix:**
1. Create exchange adapter interface in `services/keeper/adapters/`:
   - `IExchangeAdapter.ts` — Interface for all adapters
   - `BinanceAdapter.ts` — Example adapter for Binance
   - `MockAdapter.ts` — For testing
2. Update keeper to:
   - Load adapters from config
   - Poll each adapter for position closes
   - Process events into settlements
   - Handle errors gracefully

**Files:**
- New: `services/keeper/adapters/IExchangeAdapter.ts`
- New: `services/keeper/adapters/BinanceAdapter.ts`
- New: `services/keeper/adapters/MockAdapter.ts`
- Update: `services/keeper/keeper.ts`

---

### VS-OPS004: Admin Panel Authentication 🟠
**Priority:** HIGH | **Estimate:** 1 day | **Status:** TODO

**Problem:**
Admin panel has no authentication. Anyone can pause vaults, withdraw insurance funds.

**Fix:**
1. Add JWT auth to API server
2. Create login endpoint
3. Add auth middleware to admin routes
4. Add login page to admin panel
5. Store JWT in localStorage

**Files:**
- New: `services/api/middleware/auth.ts`
- New: `services/admin/login.html`
- Update: `services/admin/js/admin.js`
- Update: `services/api/server.ts`

---

### VS-OPS005: Real-time Updates via WebSockets 🟡
**Priority:** MEDIUM | **Estimate:** 1.5 days | **Status:** TODO

**Problem:**
Dashboard and admin panel need manual refresh. Want real-time updates.

**Fix:**
1. Add Socket.IO to API server
2. Emit events on:
   - New settlement
   - Settlement confirmed
   - Client onboarded
   - Insurance fund change
3. Update dashboard/admin to listen for events and auto-update

**Files:**
- Update: `services/api/server.ts`
- Update: `services/dashboard/js/*.js`
- Update: `services/admin/js/admin.js`
- Add: `socket.io-client` dependency

---

### VS-OPS006: Metrics and Monitoring 🟡
**Priority:** MEDIUM | **Estimate:** 1 day | **Status:** TODO

**Problem:**
No monitoring or alerting. Don't know when keeper is down, settlements are failing, etc.

**Fix:**
1. Add Prometheus metrics to API server:
   - Settlement count by status
   - API request latency
   - Error rates
2. Add metrics to keeper:
   - Settlements executed
   - Keeper balance
   - Failed transaction count
3. Create Grafana dashboard config
4. Add health check endpoints

**Files:**
- New: `services/api/metrics.ts`
- New: `services/keeper/metrics.ts`
- New: `monitoring/grafana-dashboard.json`
- Update: `services/api/server.ts`
- Update: `services/keeper/keeper.ts`

---

### VS-OPS007: E2E Tests for Full Settlement Flow 🟠
**Priority:** HIGH | **Estimate:** 2 days | **Status:** TODO

**Problem:**
No end-to-end tests. Need to verify full flow works.

**Fix:**
Write tests that:
1. Deploy contracts locally (Anvil)
2. Start API server
3. Start keeper
4. Submit position close via mock broker
5. Verify keeper picks it up
6. Verify settlement executes on-chain
7. Verify indexer updates state
8. Verify recon service sees it

**Files:**
- New: `services/test/e2e/settlement-flow.test.ts`
- New: `services/test/setup.ts`

---

### VS-OPS008: Production Deployment Guide 🟡
**Priority:** MEDIUM | **Estimate:** 0.5 day | **Status:** TODO

**Problem:**
Docs explain how to run locally. Need production deployment guide.

**Fix:**
Add to docs:
1. Docker Compose setup
2. Systemd service files for keeper
3. Nginx reverse proxy config
4. SSL certificate setup (Let's Encrypt)
5. Backup/restore procedures
6. Production environment variables

**Files:**
- New: `docs/PRODUCTION_DEPLOYMENT.md`
- New: `docker-compose.yml`
- New: `systemd/anduin-keeper.service`
- New: `nginx/anduin.conf`

---

## Immediate Action Items (This Week)

### Critical Path (Must Do)
1. **VS-OPS001:** Create API routes for admin/insurance operations
2. **VS-OPS002:** Integrate database into settlement engine
3. **VS-OPS004:** Add authentication to admin panel
4. **VS-C001:** Fix seizeCollateral double-seize bug
5. **VS-C002:** Wire in OracleGuard and TradingHoursGuard

### High Priority (Should Do)
6. **VS-OPS003:** Keeper integration with exchange adapters
7. **VS-OPS007:** E2E tests for full settlement flow
8. **VS-H001:** Support SecurityTokenVault in services
9. **VS-C003:** Write SecurityTokenVault tests
10. **VS-H003:** Create .env.example

### Nice to Have (Can Do)
11. **VS-OPS005:** Real-time updates via WebSockets
12. **VS-OPS006:** Metrics and monitoring
13. **VS-F001:** Design private settlements
14. **VS-F010:** Design batch settlements
15. **VS-F030:** Write Prime Layer architecture

---

*Last updated: 2026-02-15*
