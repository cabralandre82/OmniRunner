"use client";

import { useRouter, useSearchParams } from "next/navigation";

const PERIODS = [
  { value: "7", label: "7d" },
  { value: "14", label: "14d" },
  { value: "30", label: "30d" },
] as const;

export function EngagementFilters() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const current = searchParams.get("period") ?? "30";

  const handlePeriod = (period: string) => {
    const params = new URLSearchParams(searchParams.toString());
    params.set("period", period);
    router.push(`/engagement?${params.toString()}`);
  };

  return (
    <div className="flex flex-wrap items-center gap-2 rounded-lg border border-border bg-surface p-4 shadow-sm">
      <span className="text-xs font-medium uppercase tracking-wide text-content-secondary">
        Período
      </span>
      <div className="flex gap-1">
        {PERIODS.map(({ value, label }) => (
          <button
            key={value}
            type="button"
            onClick={() => handlePeriod(value)}
            className={`rounded-lg px-3 py-1.5 text-sm font-medium transition-colors ${
              current === value
                ? "bg-brand text-white"
                : "bg-surface-elevated text-content-secondary hover:bg-bg-secondary"
            }`}
          >
            {label}
          </button>
        ))}
      </div>
    </div>
  );
}
