import express from "express";
import { v4 as uuidv4 } from "uuid";
import { config } from "./config.js";

export interface Settlement {
  refId: string;
  userId: string;
  wallet: string;
  pnl_usdc: number;
  timestamp: number;
  status: "pending" | "realized";
}

const settlements: Settlement[] = [];

function generateSettlement(wallet?: string, pnlUsdc?: number): Settlement {
  const w = wallet ?? config.mockWallets[Math.floor(Math.random() * config.mockWallets.length)];
  const pnl = pnlUsdc ?? (Math.random() > 0.5 ? 1 : -1) * Math.round(Math.random() * 500 * 100) / 100;
  const s: Settlement = {
    refId: uuidv4(),
    userId: `user-${w.slice(0, 8).toLowerCase()}`,
    wallet: w,
    pnl_usdc: pnl,
    timestamp: Date.now(),
    status: "realized",
  };
  settlements.push(s);
  console.log(`[mock-broker] Generated settlement: ${s.refId} wallet=${s.wallet} pnl=${s.pnl_usdc}`);
  return s;
}

export function createMockBrokerApp() {
  const app = express();
  app.use(express.json());

  app.get("/pnl", (req, res) => {
    let result = [...settlements];

    const from = req.query.from ? Number(req.query.from) : undefined;
    const to = req.query.to ? Number(req.query.to) : undefined;
    const status = req.query.status as string | undefined;

    if (from) result = result.filter((s) => s.timestamp >= from);
    if (to) result = result.filter((s) => s.timestamp <= to);
    if (status) result = result.filter((s) => s.status === status);

    res.json(result);
  });

  app.post("/pnl/generate", (req, res) => {
    const { wallet, pnl_usdc } = req.body ?? {};
    const s = generateSettlement(wallet, pnl_usdc);
    res.json(s);
  });

  return app;
}

export function startMockBroker() {
  const app = createMockBrokerApp();
  const server = app.listen(config.mockBrokerPort, () => {
    console.log(`[mock-broker] Listening on port ${config.mockBrokerPort}`);
  });

  // Auto-generate settlements
  let autoInterval: ReturnType<typeof setInterval> | null = null;
  if (config.mockAuto) {
    console.log(`[mock-broker] Auto-generation enabled every ${config.mockAutoIntervalMs}ms`);
    autoInterval = setInterval(() => {
      generateSettlement();
    }, config.mockAutoIntervalMs);
  }

  return { app, server, autoInterval };
}

// Run standalone
if (process.argv[1]?.endsWith("mock-broker.ts") || process.argv[1]?.endsWith("mock-broker.js")) {
  startMockBroker();
}
