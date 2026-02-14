"use client";

import { useCallback } from "react";
import { api } from "@/lib/api";
import { usePolling } from "@/hooks/usePolling";
import { truncateAddress, formatUSDC } from "@/lib/utils";
import { Skeleton } from "./Skeleton";

const badges = [
  { key: "ok", label: "OK", color: "bg-green-500/20 text-accent-green" },
  { key: "pending", label: "Pending", color: "bg-yellow-500/20 text-accent-yellow" },
  { key: "failed", label: "Failed", color: "bg-red-500/20 text-accent-red" },
  { key: "break", label: "Break", color: "bg-purple-500/20 text-purple-400" },
] as const;

export function ReconPanel() {
  const statusFetcher = useCallback(() => api.getReconStatus(), []);
  const breaksFetcher = useCallback(() => api.getReconBreaks(), []);
  const { data: status, loading: statusLoading } = usePolling(statusFetcher, 5000);
  const { data: breaks, loading: breaksLoading } = usePolling(breaksFetcher, 5000);

  return (
    <div className="rounded-xl border border-dark-600 bg-dark-800 p-6">
      <h2 className="text-lg font-semibold text-white mb-4">Reconciliation</h2>

      {statusLoading ? (
        <div className="flex gap-3">
          {badges.map((b) => (
            <Skeleton key={b.key} className="h-8 w-20" />
          ))}
        </div>
      ) : (
        <>
          <div className="flex flex-wrap gap-3 mb-4">
            {badges.map((b) => (
              <div
                key={b.key}
                className={`inline-flex items-center gap-2 px-3 py-1.5 rounded-full text-sm font-medium ${b.color}`}
              >
                {b.label}
                <span className="font-bold">
                  {status?.[b.key as keyof typeof status] ?? 0}
                </span>
              </div>
            ))}
          </div>

          {(status?.break ?? 0) > 0 && !breaksLoading && breaks && breaks.length > 0 && (
            <div className="mt-4">
              <h3 className="text-sm font-medium text-gray-400 mb-2">
                Break Details
              </h3>
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="text-gray-400 text-xs border-b border-dark-600">
                      <th className="text-left pb-2 pr-3">RefId</th>
                      <th className="text-left pb-2 pr-3">Wallet</th>
                      <th className="text-right pb-2 pr-3">Amount</th>
                      <th className="text-left pb-2 pr-3">Status</th>
                      <th className="text-right pb-2">Age</th>
                    </tr>
                  </thead>
                  <tbody>
                    {breaks.map((b) => (
                      <tr
                        key={b.refId}
                        className="border-b border-dark-700/50"
                      >
                        <td className="py-2 pr-3 font-mono text-xs text-gray-300">
                          {b.refId.slice(0, 12)}…
                        </td>
                        <td className="py-2 pr-3 font-mono text-xs text-gray-300">
                          {truncateAddress(b.wallet)}
                        </td>
                        <td className="py-2 pr-3 text-right text-accent-red">
                          ${formatUSDC(b.amount)}
                        </td>
                        <td className="py-2 pr-3">
                          <span className="text-xs bg-red-500/20 text-accent-red px-2 py-0.5 rounded-full">
                            {b.status}
                          </span>
                        </td>
                        <td className="py-2 text-right text-gray-400 text-xs">
                          {Math.round(b.age / 60)}m
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}
        </>
      )}
    </div>
  );
}
