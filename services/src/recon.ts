import { config } from "./config.js";
import { getDb } from "./db.js";

const BREAK_THRESHOLD_MS = 5 * 60 * 1000; // 5 minutes

export interface ReconResult {
  refId: string;
  status: "OK" | "PENDING" | "FAILED" | "BREAK";
  brokerPnl: number | null;
  chainAmount: string | null;
  chainType: string | null;
  brokerTs: number | null;
  chainTs: number | null;
}

function runRecon(): void {
  const db = getDb();
  const now = Date.now();

  // Get all broker settlements from bridge_processed
  const bridgeRecords = db
    .prepare("SELECT * FROM bridge_processed")
    .all() as {
    ref_id: string;
    tx_hash: string | null;
    status: string;
    attempts: number;
    last_attempt: number | null;
    created_at: number;
    error: string | null;
  }[];

  // Get all broker settlements from mock broker (stored when bridge fetched them)
  // We need to check on-chain events matched by refId

  // Get all PnLCredited events (which have refId)
  const chainEvents = db
    .prepare("SELECT * FROM events WHERE ref_id IS NOT NULL")
    .all() as {
    type: string;
    user_address: string;
    amount: string;
    ref_id: string;
    tx_hash: string;
    block_number: number;
    timestamp: number;
  }[];

  const chainByRefId = new Map<string, (typeof chainEvents)[0]>();
  for (const e of chainEvents) {
    chainByRefId.set(e.ref_id, e);
  }

  const bridgeByRefId = new Map<string, (typeof bridgeRecords)[0]>();
  for (const b of bridgeRecords) {
    bridgeByRefId.set(b.ref_id, b);
  }

  // Process all known refIds
  const allRefIds = new Set([...bridgeByRefId.keys(), ...chainByRefId.keys()]);

  const upsertRecon = db.prepare(`
    INSERT INTO recon_results (ref_id, status, broker_pnl, chain_amount, chain_type, broker_ts, chain_ts, checked_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(ref_id) DO UPDATE SET
      status = ?,
      chain_amount = ?,
      chain_type = ?,
      chain_ts = ?,
      checked_at = ?
  `);

  let counts = { OK: 0, PENDING: 0, FAILED: 0, BREAK: 0 };

  const updateAll = db.transaction(() => {
    for (const refId of allRefIds) {
      const bridge = bridgeByRefId.get(refId);
      const chain = chainByRefId.get(refId);

      let status: ReconResult["status"];

      if (bridge?.status === "confirmed" && chain) {
        status = "OK";
      } else if (bridge?.status === "failed") {
        status = "FAILED";
      } else if (bridge?.status === "pending" || (bridge && !chain)) {
        // Check if pending too long
        const age = now - (bridge?.created_at ?? now);
        status = age > BREAK_THRESHOLD_MS ? "BREAK" : "PENDING";
      } else {
        status = "PENDING";
      }

      counts[status]++;

      upsertRecon.run(
        refId,
        status,
        null, // broker_pnl - we don't store it in bridge_processed
        chain?.amount ?? null,
        chain?.type ?? null,
        bridge?.created_at ?? null,
        chain?.timestamp ?? null,
        now,
        // ON CONFLICT update params
        status,
        chain?.amount ?? null,
        chain?.type ?? null,
        chain?.timestamp ?? null,
        now
      );
    }
  });

  updateAll();

  if (allRefIds.size > 0) {
    console.log(
      `[recon] Checked ${allRefIds.size} settlements: OK=${counts.OK} PENDING=${counts.PENDING} FAILED=${counts.FAILED} BREAK=${counts.BREAK}`
    );
  }
}

export function startRecon() {
  console.log(`[recon] Starting reconciliation service, interval=${config.reconIntervalMs}ms`);

  // Initial run
  runRecon();

  const interval = setInterval(runRecon, config.reconIntervalMs);
  return { interval };
}

export function getReconSummary() {
  const db = getDb();
  const rows = db
    .prepare("SELECT status, COUNT(*) as count FROM recon_results GROUP BY status")
    .all() as { status: string; count: number }[];

  const summary: Record<string, number> = { OK: 0, PENDING: 0, FAILED: 0, BREAK: 0 };
  for (const r of rows) {
    summary[r.status] = r.count;
  }
  return summary;
}

export function getReconBreaks() {
  const db = getDb();
  return db
    .prepare("SELECT * FROM recon_results WHERE status = 'BREAK' ORDER BY checked_at DESC")
    .all();
}

if (process.argv[1]?.endsWith("recon.ts") || process.argv[1]?.endsWith("recon.js")) {
  startRecon();
}
