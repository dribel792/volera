import { createPublicClient, http, formatUnits, type Log } from "viem";
import { baseSepolia, foundry } from "viem/chains";
import { config } from "./config.js";
import { vaultAbi } from "./abi.js";
import { getDb } from "./db.js";

const chain = config.chainId === 84532 ? baseSepolia : foundry;

const publicClient = createPublicClient({
  chain,
  transport: http(config.rpcUrl),
});

const EVENT_NAMES = [
  "CollateralDeposited",
  "CollateralWithdrawn",
  "PnLCredited",
  "PnLWithdrawn",
  "CollateralSeized",
  "BrokerDeposited",
  "BrokerWithdrawn",
] as const;

type EventName = (typeof EVENT_NAMES)[number];

interface ParsedEvent {
  type: EventName;
  user: string | null;
  amount: string;
  refId: string | null;
  txHash: string;
  blockNumber: number;
  logIndex: number;
  timestamp: number;
}

function parseEventLog(log: Log, timestamp: number): ParsedEvent | null {
  try {
    // Decode using viem
    const decoded = publicClient.chain; // We need to manually match topics
    // The first topic is the event signature
    const topic0 = log.topics[0];
    if (!topic0) return null;

    // Match event by topic0
    // We'll use a simpler approach: try each event
    const eventSignatures: Record<string, EventName> = {
      // keccak256 of event signatures
      "0x0b0aab87422bd6eaf1da890853ccf3bef9e8eb3c04a7623218dae23fdd68e8c7": "CollateralDeposited",
      "0x4a1dde0bacd1c08a5ee7b55dee777c482e6e6484e14e9e1e0dc8e85da6759a5c": "CollateralWithdrawn",
      "0x0c86e06e5c7a98a5e0ed14c99fe01218d8b18c7e1fbc14c27e7f6b0bc0be6a06": "PnLCredited",
      "0x12aed22da625a0b8af6f5403db9a30f5eb4c5eb8c11660aec4e15bdd6c3c9a4c": "PnLWithdrawn",
      "0x2ee62e95a8e78e17adb4fb3481cd4563880041ab6cf457c596e12d9e3e8a0b1f": "CollateralSeized",
      "0x79f444139e3ebb4ac07a5cd7a38e1e25e1e4753c4cb04af1ffabf6c4847a3946": "BrokerDeposited",
      "0x3be4f24e922ea1a0e64c4d2e30c8b44a6fc3a771a26f07baaf9a1fcfce8e2a6a": "BrokerWithdrawn",
    };

    // For robustness, we'll parse from ABI events directly
    // Use a different approach: parse all vault events from log
    for (const eventName of EVENT_NAMES) {
      try {
        const abiEvent = vaultAbi.find((e) => e.type === "event" && e.name === eventName);
        if (!abiEvent) continue;

        // Check if this log matches by examining indexed params count
        const indexedCount = abiEvent.inputs.filter((i) => "indexed" in i && i.indexed).length;
        if (log.topics.length !== indexedCount + 1) continue;

        // Parse based on event structure
        let user: string | null = null;
        let amount = "0";
        let refId: string | null = null;

        if (eventName === "BrokerDeposited" || eventName === "BrokerWithdrawn") {
          // No indexed params, amount in data
          if (log.topics.length !== 1) continue;
          amount = log.data ? BigInt(log.data).toString() : "0";
        } else if (eventName === "PnLCredited") {
          // user indexed, refId indexed, amount in data
          if (log.topics.length !== 3) continue;
          user = ("0x" + log.topics[1]!.slice(26)).toLowerCase();
          refId = log.topics[2] ?? null;
          amount = log.data ? BigInt(log.data).toString() : "0";
        } else {
          // user indexed, amount in data
          if (log.topics.length !== 2) continue;
          user = ("0x" + log.topics[1]!.slice(26)).toLowerCase();
          amount = log.data ? BigInt(log.data).toString() : "0";
        }

        return {
          type: eventName,
          user,
          amount,
          refId,
          txHash: log.transactionHash!,
          blockNumber: Number(log.blockNumber),
          logIndex: Number(log.logIndex),
          timestamp,
        };
      } catch {
        continue;
      }
    }
    return null;
  } catch {
    return null;
  }
}

function updateUserBalance(userAddress: string) {
  const db = getDb();
  const events = db
    .prepare("SELECT type, amount FROM events WHERE user_address = ?")
    .all(userAddress) as { type: string; amount: string }[];

  let collateral = 0n;
  let pnlBalance = 0n;

  for (const e of events) {
    const amt = BigInt(e.amount);
    switch (e.type) {
      case "CollateralDeposited":
        collateral += amt;
        break;
      case "CollateralWithdrawn":
        collateral -= amt;
        break;
      case "CollateralSeized":
        collateral -= amt;
        break;
      case "PnLCredited":
        pnlBalance += amt;
        break;
      case "PnLWithdrawn":
        pnlBalance -= amt;
        break;
    }
  }

  db.prepare(`
    INSERT INTO user_balances (address, collateral, pnl, updated_at)
    VALUES (?, ?, ?, ?)
    ON CONFLICT(address) DO UPDATE SET
      collateral = ?,
      pnl = ?,
      updated_at = ?
  `).run(
    userAddress,
    collateral.toString(),
    pnlBalance.toString(),
    Date.now(),
    collateral.toString(),
    pnlBalance.toString(),
    Date.now()
  );
}

function updateBrokerPoolBalance(blockNumber: number, timestamp: number) {
  const db = getDb();
  const events = db
    .prepare("SELECT type, amount FROM events WHERE type IN ('BrokerDeposited', 'BrokerWithdrawn', 'PnLCredited', 'CollateralSeized')")
    .all() as { type: string; amount: string }[];

  let balance = 0n;
  for (const e of events) {
    const amt = BigInt(e.amount);
    switch (e.type) {
      case "BrokerDeposited":
        balance += amt;
        break;
      case "BrokerWithdrawn":
        balance -= amt;
        break;
      case "PnLCredited":
        balance -= amt;
        break;
      case "CollateralSeized":
        balance += amt;
        break;
    }
  }

  db.prepare("INSERT INTO broker_pool_history (balance, block_number, timestamp) VALUES (?, ?, ?)").run(
    balance.toString(),
    blockNumber,
    timestamp
  );
}

async function indexBlockRange(fromBlock: bigint, toBlock: bigint): Promise<number> {
  const db = getDb();
  let eventCount = 0;

  const logs = await publicClient.getLogs({
    address: config.vaultAddress,
    fromBlock,
    toBlock,
  });

  if (logs.length === 0) return 0;

  // Get block timestamps (batch unique blocks)
  const uniqueBlocks = [...new Set(logs.map((l) => l.blockNumber!))];
  const blockTimestamps = new Map<bigint, number>();

  for (const bn of uniqueBlocks) {
    try {
      const block = await publicClient.getBlock({ blockNumber: bn });
      blockTimestamps.set(bn, Number(block.timestamp) * 1000);
    } catch {
      blockTimestamps.set(bn, Date.now());
    }
  }

  const insertStmt = db.prepare(`
    INSERT OR IGNORE INTO events (type, user_address, amount, ref_id, tx_hash, block_number, log_index, timestamp)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `);

  const affectedUsers = new Set<string>();

  const insertMany = db.transaction(() => {
    for (const log of logs) {
      const ts = blockTimestamps.get(log.blockNumber!) ?? Date.now();
      const parsed = parseEventLog(log, ts);
      if (!parsed) continue;

      insertStmt.run(
        parsed.type,
        parsed.user,
        parsed.amount,
        parsed.refId,
        parsed.txHash,
        parsed.blockNumber,
        parsed.logIndex,
        parsed.timestamp
      );
      eventCount++;

      if (parsed.user) affectedUsers.add(parsed.user);
    }
  });

  insertMany();

  // Update derived state
  for (const user of affectedUsers) {
    updateUserBalance(user);
  }

  if (eventCount > 0) {
    const lastBlock = Number(toBlock);
    const lastTs = blockTimestamps.get(toBlock) ?? Date.now();
    updateBrokerPoolBalance(lastBlock, lastTs);
  }

  return eventCount;
}

async function indexOnce(): Promise<void> {
  const db = getDb();
  const cursor = db.prepare("SELECT last_block FROM indexer_cursor WHERE id = 1").get() as {
    last_block: number;
  };

  const fromBlock = BigInt(cursor.last_block + 1);
  let toBlock: bigint;

  try {
    toBlock = await publicClient.getBlockNumber();
  } catch (err) {
    console.error("[indexer] Failed to get block number:", err instanceof Error ? err.message : err);
    return;
  }

  if (toBlock < fromBlock) return;

  // Process in chunks of 1000 blocks
  const chunkSize = 1000n;
  let current = fromBlock;

  while (current <= toBlock) {
    const end = current + chunkSize - 1n > toBlock ? toBlock : current + chunkSize - 1n;
    const count = await indexBlockRange(current, end);
    if (count > 0) {
      console.log(`[indexer] Indexed ${count} events from blocks ${current}-${end}`);
    }
    current = end + 1n;
  }

  db.prepare("UPDATE indexer_cursor SET last_block = ? WHERE id = 1").run(Number(toBlock));
}

export function startIndexer() {
  console.log("[indexer] Starting event indexer");
  console.log(`[indexer] Vault: ${config.vaultAddress}`);

  // Initial index
  indexOnce();

  // Poll for new blocks every 2 seconds
  const interval = setInterval(indexOnce, 2000);
  return { interval };
}

if (process.argv[1]?.endsWith("indexer.ts") || process.argv[1]?.endsWith("indexer.js")) {
  startIndexer();
}
