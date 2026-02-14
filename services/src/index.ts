import { config } from "./config.js";
import { startMockBroker } from "./mock-broker.js";
import { startBridge } from "./bridge.js";
import { startIndexer } from "./indexer.js";
import { startRecon } from "./recon.js";
import { startApi } from "./api.js";
import { getDb } from "./db.js";

console.log("═══════════════════════════════════════════════════");
console.log("  Volera Settlement Services");
console.log("═══════════════════════════════════════════════════");
console.log(`  RPC:    ${config.rpcUrl}`);
console.log(`  Chain:  ${config.chainId}`);
console.log(`  Vault:  ${config.vaultAddress}`);
console.log(`  DB:     ${config.dbPath}`);
console.log("═══════════════════════════════════════════════════");

// Initialize DB
getDb();
console.log("[main] Database initialized");

// Start all services
const mockBroker = startMockBroker();
console.log("[main] Mock broker started");

// Small delay to let mock broker bind
setTimeout(() => {
  const bridge = startBridge();
  console.log("[main] Bridge started");

  const indexer = startIndexer();
  console.log("[main] Indexer started");

  const recon = startRecon();
  console.log("[main] Recon started");

  const api = startApi();
  console.log("[main] API Gateway started");

  console.log("\n[main] All services running. Press Ctrl+C to stop.\n");

  // Graceful shutdown
  const shutdown = () => {
    console.log("\n[main] Shutting down...");
    clearInterval(bridge.interval);
    clearInterval(indexer.interval);
    clearInterval(recon.interval);
    mockBroker.server.close();
    if (mockBroker.autoInterval) clearInterval(mockBroker.autoInterval);
    api.server.close();
    process.exit(0);
  };

  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}, 500);
