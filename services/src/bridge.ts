import {
  createPublicClient,
  createWalletClient,
  http,
  parseUnits,
  encodeAbiParameters,
  keccak256,
  type Hash,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { baseSepolia, foundry } from "viem/chains";
import { config } from "./config.js";
import { vaultAbi } from "./abi.js";
import { getDb } from "./db.js";
import type { Settlement } from "./mock-broker.js";

const chain = config.chainId === 84532 ? baseSepolia : foundry;

const account = privateKeyToAccount(config.settlementPrivateKey);

const publicClient = createPublicClient({
  chain,
  transport: http(config.rpcUrl),
});

const walletClient = createWalletClient({
  account,
  chain,
  transport: http(config.rpcUrl),
});

function refIdToBytes32(refId: string): `0x${string}` {
  // Hash the UUID string to get a deterministic bytes32
  return keccak256(encodeAbiParameters([{ type: "string" }], [refId]));
}

async function fetchBrokerSettlements(): Promise<Settlement[]> {
  const url = `http://localhost:${config.mockBrokerPort}/pnl?status=realized`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Broker API error: ${res.status}`);
  return res.json() as Promise<Settlement[]>;
}

async function processSettlement(settlement: Settlement): Promise<void> {
  const db = getDb();
  const { refId, wallet, pnl_usdc } = settlement;

  // Check if already processed
  const existing = db.prepare("SELECT * FROM bridge_processed WHERE ref_id = ?").get(refId) as
    | { status: string; attempts: number; last_attempt: number | null; created_at: number; error: string | null }
    | undefined;

  if (existing?.status === "confirmed") return;

  const attempts = existing?.attempts ?? 0;
  const maxRetries = 5;
  if (attempts >= maxRetries) {
    console.log(`[bridge] Max retries reached for ${refId}, skipping`);
    return;
  }

  // Exponential backoff
  if (existing?.status === "failed" && attempts > 0) {
    const backoffMs = Math.min(1000 * Math.pow(2, attempts), 60000);
    const lastAttempt = existing.last_attempt ?? 0;
    if (Date.now() - lastAttempt < backoffMs) return;
  }

  // Insert/update processing record
  db.prepare(`
    INSERT INTO bridge_processed (ref_id, status, attempts, last_attempt, created_at)
    VALUES (?, 'pending', ?, ?, ?)
    ON CONFLICT(ref_id) DO UPDATE SET
      status = 'pending',
      attempts = ?,
      last_attempt = ?
  `).run(refId, attempts + 1, Date.now(), Date.now(), attempts + 1, Date.now());

  try {
    let txHash: Hash;
    const amountRaw = Math.abs(pnl_usdc);
    const amount = parseUnits(amountRaw.toString(), 6); // USDC 6 decimals

    if (pnl_usdc > 0) {
      // Credit PnL (positive settlement)
      const refBytes = refIdToBytes32(refId);
      console.log(`[bridge] creditPnl: user=${wallet} amount=${amountRaw} refId=${refId}`);
      txHash = await walletClient.writeContract({
        address: config.vaultAddress,
        abi: vaultAbi,
        functionName: "creditPnl",
        args: [wallet as `0x${string}`, amount, refBytes],
      });
    } else {
      // Seize collateral (negative settlement)
      const refBytes = refIdToBytes32(refId);
      console.log(`[bridge] seizeCollateral: user=${wallet} amount=${amountRaw} refId=${refId}`);
      txHash = await walletClient.writeContract({
        address: config.vaultAddress,
        abi: vaultAbi,
        functionName: "seizeCollateral",
        args: [wallet as `0x${string}`, amount, refBytes],
      });
    }

    // Wait for receipt
    const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });

    if (receipt.status === "success") {
      db.prepare("UPDATE bridge_processed SET status = 'confirmed', tx_hash = ? WHERE ref_id = ?").run(
        txHash,
        refId
      );
      console.log(`[bridge] ✓ Settled ${refId} tx=${txHash}`);
    } else {
      throw new Error("Transaction reverted");
    }
  } catch (err: unknown) {
    const errMsg = err instanceof Error ? err.message : String(err);
    console.error(`[bridge] ✗ Failed ${refId}: ${errMsg}`);
    db.prepare("UPDATE bridge_processed SET status = 'failed', error = ? WHERE ref_id = ?").run(
      errMsg,
      refId
    );
  }
}

async function pollOnce(): Promise<void> {
  try {
    const settlements = await fetchBrokerSettlements();
    for (const s of settlements) {
      await processSettlement(s);
    }
  } catch (err) {
    console.error("[bridge] Poll error:", err instanceof Error ? err.message : err);
  }
}

export function startBridge() {
  console.log(`[bridge] Starting bridge, polling every ${config.bridgePollIntervalMs}ms`);
  console.log(`[bridge] Settlement account: ${account.address}`);
  console.log(`[bridge] Vault: ${config.vaultAddress}`);

  // Initial poll
  pollOnce();

  const interval = setInterval(pollOnce, config.bridgePollIntervalMs);
  return { interval };
}

if (process.argv[1]?.endsWith("bridge.ts") || process.argv[1]?.endsWith("bridge.js")) {
  startBridge();
}
