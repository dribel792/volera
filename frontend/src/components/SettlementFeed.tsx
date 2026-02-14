"use client";

import { useCallback } from "react";
import { api } from "@/lib/api";
import { formatUSDC, truncateAddress, truncateHash, formatTimestamp } from "@/lib/utils";
import { usePolling } from "@/hooks/usePolling";
import { Skeleton } from "./Skeleton";

export function SettlementFeed() {
  const fetcher = useCallback(() => api.getSettlements(20), []);
  const { data, loading } = usePolling(fetcher, 5000);

  return (
    <div className="rounded-xl border border-dark-600 bg-dark-800 p-6">
      <h2 className="text-lg font-semibold text-white mb-4">Settlement Feed</h2>

      {loading ? (
        <div className="space-y-3">
          {Array.from({ length: 5 }).map((_, i) => (
            <Skeleton key={i} className="h-8 w-full" />
          ))}
        </div>
      ) : !data || data.length === 0 ? (
        <p className="text-gray-400 text-sm text-center py-8">
          No settlements yet
        </p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="text-gray-400 text-xs border-b border-dark-600">
                <th className="text-left pb-2 pr-3">Time</th>
                <th className="text-left pb-2 pr-3">User</th>
                <th className="text-left pb-2 pr-3">Type</th>
                <th className="text-right pb-2 pr-3">Amount</th>
                <th className="text-left pb-2 pr-3">RefId</th>
                <th className="text-left pb-2">TxHash</th>
              </tr>
            </thead>
            <tbody>
              {data.map((s) => (
                <tr
                  key={s.id}
                  className="border-b border-dark-700/50 hover:bg-dark-700/30 transition-colors"
                >
                  <td className="py-2 pr-3 text-gray-300 whitespace-nowrap">
                    {formatTimestamp(s.timestamp)}
                  </td>
                  <td className="py-2 pr-3 text-gray-300 font-mono text-xs">
                    {truncateAddress(s.user)}
                  </td>
                  <td className="py-2 pr-3">
                    <span
                      className={`inline-block px-2 py-0.5 rounded-full text-xs font-medium ${
                        s.type === "credit"
                          ? "bg-green-500/20 text-accent-green"
                          : "bg-red-500/20 text-accent-red"
                      }`}
                    >
                      {s.type}
                    </span>
                  </td>
                  <td
                    className={`py-2 pr-3 text-right font-mono ${
                      s.type === "credit"
                        ? "text-accent-green"
                        : "text-accent-red"
                    }`}
                  >
                    ${formatUSDC(s.amount)}
                  </td>
                  <td className="py-2 pr-3 text-gray-400 font-mono text-xs">
                    {truncateHash(s.refId)}
                  </td>
                  <td className="py-2 font-mono text-xs">
                    {s.txHash ? (
                      <a
                        href={`https://sepolia.basescan.org/tx/${s.txHash}`}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="text-accent-blue hover:underline"
                      >
                        {truncateHash(s.txHash)}
                      </a>
                    ) : (
                      <span className="text-gray-500">—</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
