export const API_URL =
  process.env.NEXT_PUBLIC_API_URL || "http://localhost:3001";

export const VAULT_ADDRESS = (process.env.NEXT_PUBLIC_VAULT_ADDRESS ||
  "0x0000000000000000000000000000000000000000") as `0x${string}`;

export const USDC_ADDRESS = (process.env.NEXT_PUBLIC_USDC_ADDRESS ||
  "0x0000000000000000000000000000000000000000") as `0x${string}`;

export const ADMIN_ADDRESS = (
  process.env.NEXT_PUBLIC_ADMIN_ADDRESS || ""
).toLowerCase();

export const USDC_DECIMALS = 6;
