"use client";

import { useCallback } from "react";
import { api, Stats } from "@/lib/api";
import { formatUSDC } from "@/lib/utils";
import { usePolling } from "@/hooks/usePolling";
import { CardSkeleton } from "./Skeleton";

const cards = [
  {
    label: "Total TVL",
    key: "tvl" as keyof Stats,
    format: true,
    color: "text-accent-blue",
    icon: "🏦",
  },
  {
    label: "Broker Pool",
    key: "brokerPool" as keyof Stats,
    format: true,
    color: "text-accent-green",
    icon: "💰",
  },
  {
    label: "Total Users",
    key: "totalUsers" as keyof Stats,
    format: false,
    color: "text-accent-yellow",
    icon: "👥",
  },
  {
    label: "Settled (24h)",
    key: "totalSettled24h" as keyof Stats,
    format: true,
    color: "text-purple-400",
    icon: "⚡",
  },
];

export function StatCards() {
  const fetcher = useCallback(() => api.getStats(), []);
  const { data, loading } = usePolling(fetcher, 5000);

  if (loading) {
    return (
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        {cards.map((c) => (
          <CardSkeleton key={c.key} />
        ))}
      </div>
    );
  }

  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
      {cards.map((c) => {
        const val = data?.[c.key] ?? 0;
        return (
          <div
            key={c.key}
            className="rounded-xl border border-dark-600 bg-dark-800 p-5 hover:border-dark-600/80 transition-colors"
          >
            <div className="flex items-center gap-2 mb-2">
              <span className="text-lg">{c.icon}</span>
              <p className="text-sm text-gray-400">{c.label}</p>
            </div>
            <p className={`text-2xl font-bold ${c.color}`}>
              {c.format ? `$${formatUSDC(val)}` : val.toLocaleString()}
            </p>
          </div>
        );
      })}
    </div>
  );
}
