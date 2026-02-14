import { API_URL } from "@/constants/config";

async function fetchJSON<T>(path: string, opts?: RequestInit): Promise<T> {
  const res = await fetch(`${API_URL}${path}`, opts);
  if (!res.ok) throw new Error(`API ${path}: ${res.status}`);
  return res.json();
}

export interface Stats {
  totalUsers: number;
  totalSettled24h: number;
  tvl: number;
  brokerPool: number;
}

export interface UserBalances {
  collateral: number;
  pnl: number;
}

export interface Settlement {
  id: number;
  user: string;
  amount: number;
  type: string;
  refId: string;
  txHash: string;
  blockNumber: number;
  timestamp: number | string;
}

export interface ReconStatus {
  ok: number;
  pending: number;
  failed: number;
  break: number;
  total: number;
}

export interface ReconBreak {
  refId: string;
  wallet: string;
  amount: number;
  status: string;
  brokerTimestamp: number;
  age: number;
}

export const api = {
  getStats: () => fetchJSON<Stats>("/api/stats"),
  getUserBalances: (address: string) =>
    fetchJSON<UserBalances>(`/api/users/${address}/balances`),
  getSettlements: (limit = 20) =>
    fetchJSON<Settlement[]>(`/api/settlements?limit=${limit}`),
  getReconStatus: () => fetchJSON<ReconStatus>("/api/recon/status"),
  getReconBreaks: () => fetchJSON<ReconBreak[]>("/api/recon/breaks"),
  pause: () =>
    fetchJSON<{ ok: boolean }>("/api/admin/pause", { method: "POST" }),
  unpause: () =>
    fetchJSON<{ ok: boolean }>("/api/admin/unpause", { method: "POST" }),
  generateMock: (wallet: string, pnl_usdc: number) =>
    fetchJSON<{ wallet: string; pnl_usdc: number }>("/api/mock/generate", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ wallet, pnl_usdc }),
    }),
};
