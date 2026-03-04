"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { useState } from "react";

const PERIODS = [
  { value: "7", label: "7d" },
  { value: "14", label: "14d" },
  { value: "30", label: "30d" },
] as const;

export function AttendanceAnalyticsFilters() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const current = searchParams.get("period") ?? "30";
  const [showCustom, setShowCustom] = useState(
    current === "custom" || (current !== "7" && current !== "14" && current !== "30"),
  );
  const from = searchParams.get("from") ?? "";
  const to = searchParams.get("to") ?? "";

  const handlePeriod = (period: string) => {
    const params = new URLSearchParams();
    if (period === "custom") {
      setShowCustom(true);
      if (from) params.set("from", from);
      if (to) params.set("to", to);
      params.set("period", "custom");
    } else {
      setShowCustom(period === "custom");
      params.set("period", period);
    }
    router.push(`/attendance-analytics?${params.toString()}`);
  };

  const handleCustomSubmit = (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const form = e.currentTarget;
    const formData = new FormData(form);
    const fromVal = formData.get("from") as string;
    const toVal = formData.get("to") as string;

    const params = new URLSearchParams();
    params.set("period", "custom");
    if (fromVal) params.set("from", fromVal);
    if (toVal) params.set("to", toVal);
    router.push(`/attendance-analytics?${params.toString()}`);
  };

  const today = new Date().toISOString().slice(0, 10);
  const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);

  return (
    <div className="flex flex-wrap items-end gap-4 rounded-lg border border-border bg-surface p-4 shadow-sm">
      <div className="flex items-center gap-2">
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
                current === value && !showCustom
                  ? "bg-brand text-white"
                  : "bg-surface-elevated text-content-secondary hover:bg-bg-secondary"
              }`}
            >
              {label}
            </button>
          ))}
          <button
            type="button"
            onClick={() => handlePeriod("custom")}
            className={`rounded-lg px-3 py-1.5 text-sm font-medium transition-colors ${
              showCustom || current === "custom"
                ? "bg-brand text-white"
                : "bg-surface-elevated text-content-secondary hover:bg-bg-secondary"
            }`}
          >
            Personalizado
          </button>
        </div>
      </div>

      {showCustom && (
        <form onSubmit={handleCustomSubmit} className="flex items-end gap-3">
          <div>
            <label htmlFor="att-from" className="block text-xs font-medium text-content-secondary">
              De
            </label>
            <input
              id="att-from"
              name="from"
              type="date"
              defaultValue={from || thirtyDaysAgo}
              className="mt-1 block rounded-md border border-border px-2 py-1.5 text-sm"
            />
          </div>
          <div>
            <label htmlFor="att-to" className="block text-xs font-medium text-content-secondary">
              Até
            </label>
            <input
              id="att-to"
              name="to"
              type="date"
              defaultValue={to || today}
              className="mt-1 block rounded-md border border-border px-2 py-1.5 text-sm"
            />
          </div>
          <button
            type="submit"
            className="rounded-lg bg-surface-elevated px-3 py-1.5 text-sm font-medium text-white hover:bg-bg-secondary"
          >
            Filtrar
          </button>
        </form>
      )}
    </div>
  );
}
