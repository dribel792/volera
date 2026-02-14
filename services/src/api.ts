import express from "express";
import cors from "cors";
import { createPublicClient, createWalletClient, http, formatUnits } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { baseSepolia, foundry } from "viem/chains";
import { config } from "./config.js";
import { vaultAbi } from "./abi.js";
import { getDb } from "./db.js";
import { getReconSummary, getReconBreaks } from "./recon.js";

const chain = config.chainId === 84532 ? baseSepolia : foundry;

const adminAccount = privateKeyToAccount(config.adminPrivateKey);

const publicClient = createPublicClient({
  chain,
  transport: http(config.rpcUrl),
});

const walletClient = createWalletClient({
  account: adminAccount,
  chain,
  transport: http(config.rpcUrl),
});

export function createApiApp() {
  const app = express();
  app.use(cors());
  app.use(express.json());

  // ── User Balances ──
  app.get("/api/users/:address/balances", (req, res) => {
    const db = getDb();
    const addr = req.params.address.toLowerCase();
    const row = db.prepare("SELECT * FROM user_balances WHERE address = ?").get(addr) as
      | { address: string; collateral: string; pnl: string; updated_at: number }
      | undefined;

    if (!row) {
      res.json({
        address: addr,
        collateral: "0",
        collateralFormatted: "0",
        pnl: "0",
        pnlFormatted: "0",
      });
      return;
    }

    res.json({
      address: row.address,
      collateral: row.collateral,
      collateralFormatted: formatUnits(BigInt(row.collateral), 6),
      pnl: row.pnl,
      pnlFormatted: formatUnits(BigInt(row.pnl), 6),
      updatedAt: row.updated_at,
    });
  });

  // ── Settlement History ──
  app.get("/api/settlements", (req, res) => {
    const db = getDb();
    const { user, from, to, limit } = req.query;

    let sql = "SELECT * FROM events WHERE type IN ('PnLCredited', 'CollateralSeized')";
    const params: unknown[] = [];

    if (user) {
      sql += " AND user_address = ?";
      params.push((user as string).toLowerCase());
    }
    if (from) {
      sql += " AND timestamp >= ?";
      params.push(Number(from));
    }
    if (to) {
      sql += " AND timestamp <= ?";
      params.push(Number(to));
    }

    sql += " ORDER BY block_number DESC, log_index DESC";

    if (limit) {
      sql += " LIMIT ?";
      params.push(Number(limit));
    } else {
      sql += " LIMIT 100";
    }

    const rows = db.prepare(sql).all(...params);
    res.json(rows);
  });

  // ── Broker Pool ──
  app.get("/api/broker-pool", (_req, res) => {
    const db = getDb();
    const history = db
      .prepare("SELECT * FROM broker_pool_history ORDER BY block_number DESC LIMIT 50")
      .all() as { balance: string; block_number: number; timestamp: number }[];

    const latest = history[0];
    res.json({
      balance: latest?.balance ?? "0",
      balanceFormatted: latest ? formatUnits(BigInt(latest.balance), 6) : "0",
      history: history.map((h) => ({
        balance: h.balance,
        balanceFormatted: formatUnits(BigInt(h.balance), 6),
        blockNumber: h.block_number,
        timestamp: h.timestamp,
      })),
    });
  });

  // ── Recon Status ──
  app.get("/api/recon/status", (_req, res) => {
    res.json(getReconSummary());
  });

  // ── Recon Breaks ──
  app.get("/api/recon/breaks", (_req, res) => {
    res.json(getReconBreaks());
  });

  // ── Stats ──
  app.get("/api/stats", (_req, res) => {
    const db = getDb();

    const userCount = db.prepare("SELECT COUNT(*) as count FROM user_balances").get() as { count: number };

    const settlementEvents = db
      .prepare(
        "SELECT COUNT(*) as count, COALESCE(SUM(CAST(amount AS INTEGER)), 0) as total FROM events WHERE type IN ('PnLCredited', 'CollateralSeized')"
      )
      .get() as { count: number; total: number };

    // TVL = sum of all collateral + pnl
    const balances = db
      .prepare(
        "SELECT COALESCE(SUM(CAST(collateral AS INTEGER)), 0) as totalCollateral, COALESCE(SUM(CAST(pnl AS INTEGER)), 0) as totalPnl FROM user_balances"
      )
      .get() as { totalCollateral: number; totalPnl: number };

    const brokerPool = db
      .prepare("SELECT balance FROM broker_pool_history ORDER BY block_number DESC LIMIT 1")
      .get() as { balance: string } | undefined;

    const tvlRaw = BigInt(balances.totalCollateral) + BigInt(balances.totalPnl) + BigInt(brokerPool?.balance ?? "0");

    res.json({
      totalUsers: userCount.count,
      totalSettlements: settlementEvents.count,
      totalSettledRaw: settlementEvents.total.toString(),
      totalSettledFormatted: formatUnits(BigInt(settlementEvents.total), 6),
      tvlRaw: tvlRaw.toString(),
      tvlFormatted: formatUnits(tvlRaw, 6),
    });
  });

  // ── Admin: Pause ──
  app.post("/api/admin/pause", async (_req, res) => {
    try {
      const txHash = await walletClient.writeContract({
        address: config.vaultAddress,
        abi: vaultAbi,
        functionName: "pause",
      });
      const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });
      res.json({ success: true, txHash, status: receipt.status });
    } catch (err: unknown) {
      res.status(500).json({ success: false, error: err instanceof Error ? err.message : String(err) });
    }
  });

  // ── Admin: Unpause ──
  app.post("/api/admin/unpause", async (_req, res) => {
    try {
      const txHash = await walletClient.writeContract({
        address: config.vaultAddress,
        abi: vaultAbi,
        functionName: "unpause",
      });
      const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });
      res.json({ success: true, txHash, status: receipt.status });
    } catch (err: unknown) {
      res.status(500).json({ success: false, error: err instanceof Error ? err.message : String(err) });
    }
  });

  // ── Mock: Generate settlement ──
  app.post("/api/mock/generate", async (req, res) => {
    try {
      const { wallet, pnl_usdc } = req.body ?? {};
      const brokerUrl = `http://localhost:${config.mockBrokerPort}/pnl/generate`;
      const resp = await fetch(brokerUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ wallet, pnl_usdc }),
      });
      const data = await resp.json();
      res.json(data);
    } catch (err: unknown) {
      res.status(500).json({ success: false, error: err instanceof Error ? err.message : String(err) });
    }
  });

  // ── Health ──
  app.get("/api/health", (_req, res) => {
    res.json({ status: "ok", timestamp: Date.now() });
  });

  return app;
}

export function startApi() {
  const app = createApiApp();
  const server = app.listen(config.apiPort, () => {
    console.log(`[api] API Gateway listening on port ${config.apiPort}`);
  });
  return { app, server };
}

if (process.argv[1]?.endsWith("api.ts") || process.argv[1]?.endsWith("api.js")) {
  startApi();
}
