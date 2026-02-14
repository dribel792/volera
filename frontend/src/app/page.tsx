import { StatCards } from "@/components/StatCards";
import { UserPanel } from "@/components/UserPanel";
import { SettlementFeed } from "@/components/SettlementFeed";
import { ReconPanel } from "@/components/ReconPanel";
import { AdminPanel } from "@/components/AdminPanel";

export default function DashboardPage() {
  return (
    <div className="space-y-6">
      {/* Top row: Stat cards */}
      <StatCards />

      {/* Middle row: User Panel + Settlement Feed */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-1">
          <UserPanel />
        </div>
        <div className="lg:col-span-2">
          <SettlementFeed />
        </div>
      </div>

      {/* Bottom row: Recon + Admin */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <ReconPanel />
        <AdminPanel />
      </div>
    </div>
  );
}
