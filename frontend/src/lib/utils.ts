import { USDC_DECIMALS } from "@/constants/config";

export function formatUSDC(raw: string | number | bigint): string {
  const num = Number(raw) / 10 ** USDC_DECIMALS;
  return num.toLocaleString("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
}

export function parseUSDC(amount: string): bigint {
  const num = parseFloat(amount);
  if (isNaN(num)) return BigInt(0);
  return BigInt(Math.round(num * 10 ** USDC_DECIMALS));
}

export function truncateAddress(addr: string): string {
  if (!addr) return "";
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

export function truncateHash(hash: string): string {
  if (!hash) return "";
  return `${hash.slice(0, 10)}…${hash.slice(-4)}`;
}

export function formatTimestamp(ts: number | string): string {
  const d = new Date(typeof ts === "number" ? ts * 1000 : ts);
  return d.toLocaleTimeString("en-US", {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  });
}

export function cn(...classes: (string | false | undefined | null)[]): string {
  return classes.filter(Boolean).join(" ");
}
