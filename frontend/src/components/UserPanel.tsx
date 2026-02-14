"use client";

import { useState, useCallback } from "react";
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { usePolling } from "@/hooks/usePolling";
import { api } from "@/lib/api";
import { formatUSDC, parseUSDC } from "@/lib/utils";
import { VAULT_ABI, ERC20_ABI } from "@/constants/abis";
import { VAULT_ADDRESS, USDC_ADDRESS } from "@/constants/config";
import toast from "react-hot-toast";

function ActionInput({
  label,
  buttonLabel,
  color,
  onSubmit,
  isPending,
}: {
  label: string;
  buttonLabel: string;
  color: string;
  onSubmit: (amount: string) => void;
  isPending: boolean;
}) {
  const [value, setValue] = useState("");
  return (
    <div className="space-y-2">
      <label className="text-sm text-gray-400">{label}</label>
      <div className="flex gap-2">
        <input
          type="number"
          step="0.01"
          min="0"
          placeholder="0.00"
          value={value}
          onChange={(e) => setValue(e.target.value)}
          className="flex-1 rounded-lg bg-dark-900 border border-dark-600 px-3 py-2 text-sm text-white placeholder-gray-500 focus:outline-none focus:border-accent-blue"
        />
        <button
          onClick={() => {
            onSubmit(value);
            setValue("");
          }}
          disabled={isPending || !value || parseFloat(value) <= 0}
          className={`px-4 py-2 rounded-lg text-sm font-medium text-white transition-colors disabled:opacity-50 disabled:cursor-not-allowed ${color}`}
        >
          {isPending ? "…" : buttonLabel}
        </button>
      </div>
    </div>
  );
}

export function UserPanel() {
  const { address, isConnected } = useAccount();

  const fetcher = useCallback(() => {
    if (!address) return Promise.resolve({ collateral: 0, pnl: 0 });
    return api.getUserBalances(address);
  }, [address]);

  const { data: balances, loading } = usePolling(fetcher, 5000);

  const { writeContract: writeApprove, data: approveTxHash, isPending: approvePending } = useWriteContract();
  const { writeContract: writeVault, data: vaultTxHash, isPending: vaultPending } = useWriteContract();

  const { isLoading: approveConfirming } = useWaitForTransactionReceipt({
    hash: approveTxHash,
  });
  const { isLoading: vaultConfirming } = useWaitForTransactionReceipt({
    hash: vaultTxHash,
  });

  const handleDeposit = async (amount: string) => {
    const parsed = parseUSDC(amount);
    if (parsed <= BigInt(0)) return;
    try {
      // First approve
      writeApprove(
        {
          address: USDC_ADDRESS,
          abi: ERC20_ABI,
          functionName: "approve",
          args: [VAULT_ADDRESS, parsed],
        },
        {
          onSuccess: () => {
            toast.success("USDC approved! Depositing…");
            // Then deposit
            writeVault(
              {
                address: VAULT_ADDRESS,
                abi: VAULT_ABI,
                functionName: "depositCollateral",
                args: [parsed],
              },
              {
                onSuccess: () => toast.success("Deposit submitted!"),
                onError: (e) => toast.error(`Deposit failed: ${e.message.slice(0, 80)}`),
              }
            );
          },
          onError: (e) => toast.error(`Approve failed: ${e.message.slice(0, 80)}`),
        }
      );
    } catch (e) {
      toast.error("Transaction failed");
    }
  };

  const handleWithdrawCollateral = (amount: string) => {
    const parsed = parseUSDC(amount);
    if (parsed <= BigInt(0)) return;
    writeVault(
      {
        address: VAULT_ADDRESS,
        abi: VAULT_ABI,
        functionName: "withdrawCollateral",
        args: [parsed],
      },
      {
        onSuccess: () => toast.success("Withdrawal submitted!"),
        onError: (e) => toast.error(`Withdraw failed: ${e.message.slice(0, 80)}`),
      }
    );
  };

  const handleWithdrawPnL = (amount: string) => {
    const parsed = parseUSDC(amount);
    if (parsed <= BigInt(0)) return;
    writeVault(
      {
        address: VAULT_ADDRESS,
        abi: VAULT_ABI,
        functionName: "withdrawPnL",
        args: [parsed],
      },
      {
        onSuccess: () => toast.success("PnL withdrawal submitted!"),
        onError: (e) => toast.error(`Withdraw failed: ${e.message.slice(0, 80)}`),
      }
    );
  };

  if (!isConnected) {
    return (
      <div className="rounded-xl border border-dark-600 bg-dark-800 p-6">
        <h2 className="text-lg font-semibold text-white mb-4">Your Account</h2>
        <p className="text-gray-400 text-sm">Connect wallet to view balances</p>
      </div>
    );
  }

  const isPending = approvePending || vaultPending || approveConfirming || vaultConfirming;

  return (
    <div className="rounded-xl border border-dark-600 bg-dark-800 p-6 space-y-5">
      <h2 className="text-lg font-semibold text-white">Your Account</h2>

      <div className="grid grid-cols-2 gap-4">
        <div className="rounded-lg bg-dark-900 p-4">
          <p className="text-xs text-gray-400 mb-1">Collateral</p>
          <p className="text-xl font-bold text-accent-blue">
            {loading ? (
              <span className="skeleton inline-block h-6 w-20" />
            ) : (
              `$${formatUSDC(balances?.collateral ?? 0)}`
            )}
          </p>
        </div>
        <div className="rounded-lg bg-dark-900 p-4">
          <p className="text-xs text-gray-400 mb-1">PnL Balance</p>
          <p className="text-xl font-bold text-accent-green">
            {loading ? (
              <span className="skeleton inline-block h-6 w-20" />
            ) : (
              `$${formatUSDC(balances?.pnl ?? 0)}`
            )}
          </p>
        </div>
      </div>

      <div className="space-y-4">
        <ActionInput
          label="Deposit Collateral"
          buttonLabel="Deposit"
          color="bg-accent-blue hover:bg-blue-600"
          onSubmit={handleDeposit}
          isPending={isPending}
        />
        <ActionInput
          label="Withdraw Collateral"
          buttonLabel="Withdraw"
          color="bg-accent-blue hover:bg-blue-600"
          onSubmit={handleWithdrawCollateral}
          isPending={isPending}
        />
        <ActionInput
          label="Withdraw PnL"
          buttonLabel="Withdraw"
          color="bg-accent-green hover:bg-emerald-600"
          onSubmit={handleWithdrawPnL}
          isPending={isPending}
        />
      </div>

      {isPending && (
        <div className="flex items-center gap-2 text-sm text-accent-yellow">
          <div className="h-3 w-3 rounded-full border-2 border-accent-yellow border-t-transparent animate-spin" />
          Transaction pending…
        </div>
      )}
    </div>
  );
}
