# Anduin Product Lines

*Source: Internal deck (Feb 2025)*

## Overview

Three product lines enabling brokers/exchanges to acquire new users:

---

## 1. Anduin Lending

**What it does:**
- In-app margin: loans to retail platforms for client leverage
- 10x margin trading without touching MIFID products
- Fully controlled through margin maintenance
- Externalizes balance sheet from partners

**Who it's for:**
- Crypto platforms
- CFD brokers

**Status:**
- ✅ Committed: Revolut
- 🎯 Prospects: Bit2Me, eToro, Axi, Baader

---

## 2. Anduin Issuance

**What it does:**
- Assets: equities, indices, commodities, precious metals, crypto-linked
- Formats: principal-protected notes, delta-one trackers, securitized perpetuals
- On-demand tokenization: mint 1:1 tokenized security when user withdraws to wallet

**Who it's for:**
- Exchanges/brokers wanting yield and equity exposure
- Without building issuer or risk desk

**Status:**
- ✅ Committed: Bitvavo, Bitget, OSL
- 🎯 Prospects: Bitmex, Young Platform, MEXC

---

## 3. Anduin Settlement

**What it does:**
- Instant PnL settlement (seconds instead of days)
- Securities trading from self-custody wallets
- Single API integration
- Instant DVP (delivery vs payment)

**Core Features (MVP):**
- UnifiedAccountVault (collateral + PnL sub-ledgers)
- SecurityTokenVault (DVP for tokenized securities)
- TradingHoursGuard (market hours, halts, earnings blackouts)
- OracleGuard (Chainlink/Pyth price validation)
- Broker bridge + indexer + reconciliation

**Phase 2 Features (Roadmap):**
- **Private Settlements:** Hide amounts via commitment schemes (see `docs/PRIVATE_SETTLEMENTS.md`)
- **Batch Settlements:** Net trades, 88-96% gas savings for HFT (see `docs/BATCH_SETTLEMENTS.md`)
- **Multi-Collateral:** Accept ETH, WBTC as collateral (see `docs/MULTI_COLLATERAL.md`)
- **Prime Layer:** Cross-venue trading, 60% margin savings (see `docs/PRIME_ARCHITECTURE.md`)

**Who it's for:**
- Platforms wanting to serve DeFi-native users
- Users who want to trade without leaving self-custody
- HFT traders needing gas-efficient settlement
- Institutional clients needing privacy

**Status:**
- 🏗️ Building (contracts written, pending testnet deployment)
- ✅ 57 tests passing (UnifiedAccountVault)
- ✅ Comprehensive SecurityTokenVault tests written
- ✅ Guards integrated (trading hours, oracle validation)
- 🎯 Prospects: TBD

**Revenue Model:**
- Setup fee: €250k per broker
- Platform fee: €10-30k MRR
- Settlement fee: 0.5-2.0 bps on notional
- Tokenization fee: Per-token DVP settlement

---

## Cross-Sell Strategy

1. **Land with Lending or Issuance** (already have traction)
2. **Expand to Settlement** (adds self-custody capability)
3. **Full stack = lock-in** (all three = hard to leave)

---

*Last updated: 2026-02-08*
