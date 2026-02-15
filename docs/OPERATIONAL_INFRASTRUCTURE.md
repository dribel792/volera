# Operational Infrastructure Documentation

Complete guide to the Anduin settlement infrastructure, including API server, keeper service, admin panel, and dashboard.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [API Server](#api-server)
3. [Keeper Service](#keeper-service)
4. [Admin Panel](#admin-panel)
5. [Dashboard](#dashboard)
6. [Deployment Guide](#deployment-guide)
7. [Database Schema](#database-schema)
8. [Security Considerations](#security-considerations)

---

## Architecture Overview

```
┌─────────────┐      ┌──────────────┐      ┌─────────────────┐
│   Clients   │◄────►│  API Server  │◄────►│  Smart Contracts│
│  (Web UI)   │      │   (Express)  │      │   (Base Chain)  │
└─────────────┘      └──────┬───────┘      └─────────────────┘
                           │                        ▲
                           │                        │
                           ▼                        │
                     ┌──────────┐                   │
                     │ Database │                   │
                     │ (SQLite) │                   │
                     └──────────┘                   │
                                                    │
                     ┌──────────────┐               │
                     │Keeper Service│───────────────┘
                     │  (Automated) │
                     └──────────────┘
```

### Components

- **API Server**: REST API for client management, settlement submission, and data queries
- **Keeper Service**: Automated bot that monitors position closes and executes settlements
- **Database**: SQLite for persistent storage of clients, settlements, and audit logs
- **Admin Panel**: Web UI for system administration and client onboarding
- **Dashboard**: Public dashboard for monitoring settlements and system health

---

## API Server

The API server is an Express.js application that provides REST endpoints for interacting with the settlement system.

### Starting the Server

```bash
cd services/api
npm install
npm run dev
```

Production:
```bash
npm run build
npm start
```

Server runs on `http://localhost:3000`

### Configuration

Set environment variables in `services/api/.env`:

```env
# Network
NETWORK=testnet
RPC_URL=https://sepolia.base.org

# Private Keys
KEEPER_PRIVATE_KEY=0x...

# Contract Addresses
CONTRACT_USDC=0x...
CONTRACT_UNIFIED_VAULT=0x...
CONTRACT_BATCH_VAULT=0x...
CONTRACT_PRIVATE_VAULT=0x...
CONTRACT_SECURITY_VAULT=0x...

# Server
PORT=3000
```

### API Endpoints

#### Client Management

**Create Client**
```http
POST /api/clients
Content-Type: application/json

{
  "address": "0x...",
  "name": "Hedge Fund Alpha",
  "vault": "unified"
}
```

Response:
```json
{
  "id": "CLI-...",
  "address": "0x...",
  "name": "Hedge Fund Alpha",
  "vaultAddress": "0x...",
  "createdAt": 1703275200000
}
```

**Get All Clients**
```http
GET /api/clients
```

Response:
```json
[
  {
    "id": "CLI-...",
    "address": "0x...",
    "name": "Hedge Fund Alpha",
    "vaultAddress": "0x...",
    "balance": "1000.50",
    "createdAt": 1703275200000
  }
]
```

**Get Client by ID**
```http
GET /api/clients/:id
```

#### Settlement Management

**Create Settlement**
```http
POST /api/settlements
Content-Type: application/json

{
  "clientId": "0x...",
  "vaultAddress": "0x...",
  "amount": "100.50",
  "type": "credit",
  "venue": "binance",
  "positionId": "12345"
}
```

Response:
```json
{
  "id": "STL-...",
  "clientId": "0x...",
  "vaultAddress": "0x...",
  "amount": "100.50",
  "type": "credit",
  "status": "pending",
  "refId": "0x...",
  "createdAt": 1703275200000
}
```

**Get Settlements**
```http
GET /api/settlements?status=pending&clientId=0x...
```

**Get Settlement by ID**
```http
GET /api/settlements/:id
```

#### Insurance Fund

**Get Insurance Fund Balance**
```http
GET /api/insurance/balance
```

Response:
```json
{
  "insuranceFund": "50000.00",
  "brokerPool": "10000.00",
  "socializedLoss": "0.00"
}
```

**Deposit to Insurance Fund** (Admin only)
```http
POST /api/insurance/deposit
Content-Type: application/json

{
  "amount": "1000.00"
}
```

**Withdraw from Insurance Fund** (Admin only)
```http
POST /api/insurance/withdraw
Content-Type: application/json

{
  "amount": "500.00"
}
```

**Get Insurance Events**
```http
GET /api/insurance/events
```

#### System Controls

**Get System Status**
```http
GET /api/system/status
```

Response:
```json
{
  "unifiedVault": "Active",
  "batchVault": "Active",
  "privateVault": "Active",
  "keeper": "Running"
}
```

**Pause System** (Admin only)
```http
POST /api/system/pause
```

**Unpause System** (Admin only)
```http
POST /api/system/unpause
```

#### Audit Log

**Get Audit Log**
```http
GET /api/audit?limit=50&offset=0
```

---

## Keeper Service

Automated service that monitors for position closes and executes settlements on-chain.

### Starting the Keeper

```bash
cd services/keeper
npm install
npm run dev
```

Production:
```bash
npm run build
npm start
```

### How It Works

1. **Monitor**: Polls exchange adapters for new position close events
2. **Calculate PnL**: Computes profit/loss for closed positions
3. **Generate Settlement**: Creates settlement with refId = keccak256(venue, positionId)
4. **Execute On-Chain**: Calls `creditPnl` or `seizeCollateral` on vault contract
5. **Retry Logic**: Exponential backoff for failed transactions
6. **Health Monitoring**: Checks keeper balance and alerts if low

### Configuration

Set environment variables in `services/keeper/.env`:

```env
# Same as API server
NETWORK=testnet
RPC_URL=https://sepolia.base.org
KEEPER_PRIVATE_KEY=0x...

# Keeper-specific
POLL_INTERVAL=10000
MAX_RETRIES=3
```

### Contract Interactions

The keeper calls these functions on `UnifiedAccountVault`:

**Credit PnL**
```solidity
function creditPnl(
  address user,
  uint256 amount,
  bytes32 refId
) external onlySettlement
```

**Seize Collateral**
```solidity
function seizeCollateral(
  address user,
  uint256 amount,
  bytes32 refId
) external onlySettlement
```

### Logs

```
🤖 Settlement Keeper Starting...
   Network: testnet
   Keeper address: 0x...
   Poll interval: 10000ms

💰 Keeper balance: 0.5 ETH
📊 Pending settlements: 0
📦 Latest block: 12345678

📊 Position closed: { clientId: '0x...', symbol: 'BTCUSD', ... }
💰 Settlement created: STL-... - credit 150.25 USDC
🔄 Executing settlement STL-...
   Gas estimate: 0.002 ETH
   Transaction hash: 0x...
✅ Settlement STL-... executed successfully
   Block: 12345679
```

---

## Admin Panel

Web-based admin interface for managing clients, insurance fund, and system controls.

### Accessing the Panel

1. Start the API server (must be running)
2. Open `services/admin/index.html` in a browser
3. Or serve with:
   ```bash
   cd services/admin
   python3 -m http.server 8080
   ```
4. Navigate to `http://localhost:8080`

### Features

#### Client Management
- Onboard new clients
- View all registered clients
- View client collateral balances
- Track client activity

#### Insurance Fund
- View insurance fund balance
- Deposit/withdraw funds (admin only)
- View insurance event history
- Monitor socialized losses

#### System Controls
- Pause/unpause all vaults
- View system status
- Emergency controls

#### Audit Log
- View all admin actions
- Filter by actor, entity type
- Track system changes

### Screenshots

**Client Onboarding**
```
┌────────────────────────────────────────┐
│ Client Onboarding                      │
├────────────────────────────────────────┤
│ Client Address: [0x...              ] │
│ Client Name:    [Optional            ] │
│ Vault:          [▼ Select vault...   ] │
│                                        │
│               [Onboard Client]         │
└────────────────────────────────────────┘
```

---

## Dashboard

Public dashboard for monitoring settlements and system health.

### Accessing the Dashboard

```bash
cd services/dashboard
python3 -m http.server 8080
```

Navigate to `http://localhost:8080`

### Pages

**Home** (`index.html`)
- System overview
- Key metrics
- Recent activity

**Clients** (`clients.html`)
- Client directory
- Collateral balances
- Client activity stats

**Settlements** (`settlements.html`)
- Settlement explorer
- Search/filter settlements
- View transaction details

---

## Deployment Guide

### Prerequisites

- Node.js 18+
- Forge (Foundry)
- Base Sepolia ETH for keeper
- USDC for testing

### Step 1: Deploy Contracts

```bash
cd contracts
forge build

# Deploy to Base Sepolia
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify

# Note the deployed addresses
```

### Step 2: Configure Services

Update `.env` files in `services/api/` and `services/keeper/`:

```env
CONTRACT_USDC=0x... (from deployment)
CONTRACT_UNIFIED_VAULT=0x... (from deployment)
CONTRACT_BATCH_VAULT=0x... (from deployment)
# etc.
```

### Step 3: Initialize Database

```bash
cd services/api
npm install
npm run dev  # Automatically initializes database
```

Database created at `data/anduin.db`

### Step 4: Start Services

**API Server**
```bash
cd services/api
npm start
```

**Keeper**
```bash
cd services/keeper
npm start
```

### Step 5: Deploy Frontends

**Admin Panel**
```bash
cd services/admin
# Copy to web server or use:
python3 -m http.server 8080
```

**Dashboard**
```bash
cd services/dashboard
# Copy to web server or use:
python3 -m http.server 8081
```

---

## Database Schema

SQLite database with the following tables:

### clients
```sql
CREATE TABLE clients (
  id TEXT PRIMARY KEY,
  address TEXT UNIQUE NOT NULL,
  name TEXT,
  vault_address TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  metadata TEXT
);
```

### settlements
```sql
CREATE TABLE settlements (
  id TEXT PRIMARY KEY,
  client_id TEXT NOT NULL,
  vault_address TEXT NOT NULL,
  amount TEXT NOT NULL,
  type TEXT CHECK(type IN ('credit', 'debit')),
  status TEXT CHECK(status IN ('pending', 'confirmed', 'failed')),
  transaction_hash TEXT,
  ref_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  confirmed_at INTEGER,
  metadata TEXT,
  FOREIGN KEY (client_id) REFERENCES clients(id)
);
```

### netting_rounds
```sql
CREATE TABLE netting_rounds (
  id TEXT PRIMARY KEY,
  batch_id TEXT NOT NULL,
  merkle_root TEXT NOT NULL,
  vault_address TEXT NOT NULL,
  status TEXT CHECK(status IN ('pending', 'submitted', 'finalized', 'failed')),
  transaction_hash TEXT,
  created_at INTEGER NOT NULL,
  submitted_at INTEGER,
  finalized_at INTEGER,
  settlement_count INTEGER NOT NULL,
  total_credit TEXT NOT NULL,
  total_debit TEXT NOT NULL,
  metadata TEXT
);
```

### insurance_events
```sql
CREATE TABLE insurance_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  event_type TEXT CHECK(event_type IN ('deposit', 'withdrawal', 'socialized_loss')),
  amount TEXT NOT NULL,
  vault_address TEXT NOT NULL,
  transaction_hash TEXT,
  created_at INTEGER NOT NULL,
  metadata TEXT
);
```

### audit_log
```sql
CREATE TABLE audit_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  action TEXT NOT NULL,
  actor TEXT,
  entity_type TEXT,
  entity_id TEXT,
  details TEXT,
  created_at INTEGER NOT NULL
);
```

---

## Security Considerations

### Private Key Management

- Never commit private keys to git
- Use environment variables or secure vaults
- Rotate keeper keys regularly
- Keep keeper wallets funded but not over-funded

### Access Control

- Admin endpoints should be behind authentication
- Use HTTPS in production
- Implement rate limiting
- Validate all inputs

### Blockchain Security

- All settlement functions require `onlySettlement` modifier
- Use circuit breakers for large withdrawals
- Monitor for unusual activity
- Test extensively on testnet

### Database Security

- SQLite file permissions should be restricted
- Back up database regularly
- Sanitize all user inputs
- Use prepared statements (already implemented)

---

## Monitoring & Alerts

### Keeper Health

Monitor keeper balance:
```bash
# If balance < 0.01 ETH, alert admin
```

Monitor pending settlements:
```bash
# If pending > 100, investigate
```

### System Health

- Check vault paused status
- Monitor insurance fund balance
- Track failed settlements
- Watch for high socialized losses

---

## Troubleshooting

### Keeper not executing settlements

1. Check keeper balance: `keeper.ts` logs balance
2. Verify keeper address is set as settlement admin in vault
3. Check RPC connection
4. Review keeper logs for errors

### Settlements failing

1. Check client has sufficient collateral for debits
2. Verify vault is not paused
3. Check refId is unique (no duplicate settlements)
4. Review transaction revert reason on BaseScan

### Database locked

SQLite uses WAL mode for concurrency. If locked:
1. Check for long-running queries
2. Restart API server
3. Delete `anduin.db-wal` and `anduin.db-shm` files

---

## API Integration Examples

### Submit a Settlement (JavaScript)

```javascript
const response = await fetch('http://localhost:3000/api/settlements', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    clientId: '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb',
    vaultAddress: '0x...',
    amount: '150.50',
    type: 'credit',
    venue: 'binance',
    positionId: 'trade-12345'
  })
});

const settlement = await response.json();
console.log('Settlement created:', settlement.id);
```

### Poll for Settlement Status

```javascript
async function waitForConfirmation(settlementId) {
  while (true) {
    const response = await fetch(`http://localhost:3000/api/settlements/${settlementId}`);
    const settlement = await response.json();
    
    if (settlement.status === 'confirmed') {
      console.log('Settlement confirmed!', settlement.transactionHash);
      return settlement;
    } else if (settlement.status === 'failed') {
      throw new Error('Settlement failed');
    }
    
    await new Promise(resolve => setTimeout(resolve, 5000));
  }
}
```

---

For questions or issues, contact the Anduin team or open an issue on GitHub.
