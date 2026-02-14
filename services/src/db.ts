import Database from "better-sqlite3";
import { config } from "./config.js";

let _db: Database.Database | null = null;

export function getDb(): Database.Database {
  if (_db) return _db;
  _db = new Database(config.dbPath);
  _db.pragma("journal_mode = WAL");
  _db.pragma("foreign_keys = ON");
  initSchema(_db);
  return _db;
}

function initSchema(db: Database.Database) {
  db.exec(`
    -- Broker settlements from mock broker
    CREATE TABLE IF NOT EXISTS broker_settlements (
      ref_id        TEXT PRIMARY KEY,
      user_id       TEXT NOT NULL,
      wallet        TEXT NOT NULL,
      pnl_usdc      REAL NOT NULL,
      timestamp     INTEGER NOT NULL,
      status        TEXT NOT NULL DEFAULT 'realized'
    );

    -- Bridge processing state
    CREATE TABLE IF NOT EXISTS bridge_processed (
      ref_id        TEXT PRIMARY KEY,
      tx_hash       TEXT,
      status        TEXT NOT NULL DEFAULT 'pending',
      attempts      INTEGER NOT NULL DEFAULT 0,
      last_attempt  INTEGER,
      error         TEXT,
      created_at    INTEGER NOT NULL
    );

    -- On-chain events from indexer
    CREATE TABLE IF NOT EXISTS events (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      type          TEXT NOT NULL,
      user_address  TEXT,
      amount        TEXT NOT NULL,
      ref_id        TEXT,
      tx_hash       TEXT NOT NULL,
      block_number  INTEGER NOT NULL,
      log_index     INTEGER NOT NULL,
      timestamp     INTEGER NOT NULL,
      UNIQUE(tx_hash, log_index)
    );

    -- Computed user balances from indexer
    CREATE TABLE IF NOT EXISTS user_balances (
      address       TEXT PRIMARY KEY,
      collateral    TEXT NOT NULL DEFAULT '0',
      pnl           TEXT NOT NULL DEFAULT '0',
      updated_at    INTEGER NOT NULL
    );

    -- Broker pool history
    CREATE TABLE IF NOT EXISTS broker_pool_history (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      balance       TEXT NOT NULL,
      block_number  INTEGER NOT NULL,
      timestamp     INTEGER NOT NULL
    );

    -- Indexer cursor
    CREATE TABLE IF NOT EXISTS indexer_cursor (
      id            INTEGER PRIMARY KEY CHECK (id = 1),
      last_block    INTEGER NOT NULL DEFAULT 0
    );

    INSERT OR IGNORE INTO indexer_cursor (id, last_block) VALUES (1, 0);

    -- Recon results
    CREATE TABLE IF NOT EXISTS recon_results (
      ref_id        TEXT PRIMARY KEY,
      status        TEXT NOT NULL,
      broker_pnl    REAL,
      chain_amount  TEXT,
      chain_type    TEXT,
      broker_ts     INTEGER,
      chain_ts      INTEGER,
      checked_at    INTEGER NOT NULL
    );
  `);
}
