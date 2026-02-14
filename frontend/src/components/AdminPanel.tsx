"use client";

import { useState } from "react";
import { useAccount } from "wagmi";
import { ADMIN_ADDRESS } from "@/constants/config";
import { api } from "@/lib/api";
import toast from "react-hot-toast";

export function AdminPanel() {
  const { address } = useAccount();
  const [isPaused, setIsPaused] = useState(false);
  const [pauseLoading, setPauseLoading] = useState(false);
  const [mockWallet, setMockWallet] = useState("");
  const [mockAmount, setMockAmount] = useState("");
  const [mockLoading, setMockLoading] = useState(false);

  const isAdmin =
    address && address.toLowerCase() === ADMIN_ADDRESS.toLowerCase();

  if (!isAdmin) return null;

  const handlePauseToggle = async () => {
    setPauseLoading(true);
    try {
      if (isPaused) {
        await api.unpause();
        toast.success("System unpaused");
      } else {
        await api.pause();
        toast.success("System paused");
      }
      setIsPaused(!isPaused);
    } catch (e) {
      toast.error("Failed to toggle pause");
    } finally {
      setPauseLoading(false);
    }
  };

  const handleGenerate = async () => {
    if (!mockWallet || !mockAmount) return;
    setMockLoading(true);
    try {
      await api.generateMock(mockWallet, parseFloat(mockAmount));
      toast.success(
        `Mock settlement generated: ${parseFloat(mockAmount) > 0 ? "+" : ""}${mockAmount} USDC`
      );
      setMockWallet("");
      setMockAmount("");
    } catch (e) {
      toast.error("Failed to generate mock settlement");
    } finally {
      setMockLoading(false);
    }
  };

  return (
    <div className="rounded-xl border border-accent-yellow/30 bg-dark-800 p-6">
      <div className="flex items-center gap-2 mb-4">
        <span className="text-lg">⚙️</span>
        <h2 className="text-lg font-semibold text-white">Admin Panel</h2>
        <span className="text-xs bg-accent-yellow/20 text-accent-yellow px-2 py-0.5 rounded-full">
          Admin
        </span>
      </div>

      {/* Pause Toggle */}
      <div className="mb-6">
        <button
          onClick={handlePauseToggle}
          disabled={pauseLoading}
          className={`w-full py-2.5 rounded-lg font-medium text-sm transition-colors disabled:opacity-50 ${
            isPaused
              ? "bg-accent-green hover:bg-emerald-600 text-white"
              : "bg-accent-red hover:bg-red-600 text-white"
          }`}
        >
          {pauseLoading
            ? "Processing…"
            : isPaused
            ? "▶ Unpause System"
            : "⏸ Pause System"}
        </button>
      </div>

      {/* Mock Settlement */}
      <div className="space-y-3">
        <h3 className="text-sm font-medium text-gray-400">
          Generate Mock Settlement
        </h3>
        <input
          type="text"
          placeholder="Wallet address (0x…)"
          value={mockWallet}
          onChange={(e) => setMockWallet(e.target.value)}
          className="w-full rounded-lg bg-dark-900 border border-dark-600 px-3 py-2 text-sm text-white placeholder-gray-500 focus:outline-none focus:border-accent-blue"
        />
        <input
          type="number"
          placeholder="Amount (+ win, - loss)"
          value={mockAmount}
          onChange={(e) => setMockAmount(e.target.value)}
          className="w-full rounded-lg bg-dark-900 border border-dark-600 px-3 py-2 text-sm text-white placeholder-gray-500 focus:outline-none focus:border-accent-blue"
        />
        <button
          onClick={handleGenerate}
          disabled={mockLoading || !mockWallet || !mockAmount}
          className="w-full py-2.5 rounded-lg bg-accent-blue hover:bg-blue-600 text-white font-medium text-sm transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {mockLoading ? "Generating…" : "Generate Settlement"}
        </button>
      </div>
    </div>
  );
}
