import dotenv from "dotenv";
dotenv.config();

function env(key: string, fallback?: string): string {
  const v = process.env[key] ?? fallback;
  if (v === undefined) throw new Error(`Missing env var: ${key}`);
  return v;
}

export const config = {
  // Chain
  rpcUrl: env("RPC_URL", "http://127.0.0.1:8545"),
  chainId: Number(env("CHAIN_ID", "31337")),

  // Contracts
  vaultAddress: env("VAULT_ADDRESS", "0x0000000000000000000000000000000000000000") as `0x${string}`,
  usdcAddress: env("USDC_ADDRESS", "0x0000000000000000000000000000000000000000") as `0x${string}`,

  // Wallets
  settlementPrivateKey: env(
    "SETTLEMENT_PRIVATE_KEY",
    "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
  ) as `0x${string}`,
  adminPrivateKey: env(
    "ADMIN_PRIVATE_KEY",
    "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
  ) as `0x${string}`,

  // Ports
  apiPort: Number(env("API_PORT", "3001")),
  mockBrokerPort: Number(env("MOCK_BROKER_PORT", "3002")),

  // Intervals
  bridgePollIntervalMs: Number(env("BRIDGE_POLL_INTERVAL_MS", "5000")),
  reconIntervalMs: Number(env("RECON_INTERVAL_MS", "60000")),

  // Mock broker
  mockAuto: env("MOCK_AUTO", "false") === "true",
  mockAutoIntervalMs: Number(env("MOCK_AUTO_INTERVAL_MS", "10000")),
  mockWallets: env("MOCK_WALLETS", "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266").split(",") as `0x${string}`[],

  // Database
  dbPath: env("DB_PATH", "./anduin.sqlite"),
} as const;
