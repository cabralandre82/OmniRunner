"use client";

import { Sparkline, BarChart } from "@/components/ui";

interface DailyBreakdown {
  label: string;
  date: string;
  sessions: number;
}

interface DashboardChartsProps {
  dailyBreakdown: DailyBreakdown[];
}

export function DashboardCharts({ dailyBreakdown }: DashboardChartsProps) {
  const sessionData = dailyBreakdown.map((d) => d.sessions);
  const barData = dailyBreakdown.map((d) => ({
    label: `${d.label} (${d.date})`,
    value: d.sessions,
  }));

  return (
    <div className="grid gap-4 lg:grid-cols-2">
      <div className="rounded-xl border border-gray-200 bg-white p-6 shadow-sm">
        <h2 className="text-sm font-semibold text-gray-900">
          Tendência — Corridas (7d)
        </h2>
        <div className="mt-4 flex justify-center">
          <Sparkline
            data={sessionData}
            width={360}
            height={80}
            color="#3b82f6"
            label="Tendência de corridas nos últimos 7 dias"
          />
        </div>
        <div className="mt-2 flex justify-between text-[10px] text-gray-400">
          <span>{dailyBreakdown[0]?.date}</span>
          <span>{dailyBreakdown[dailyBreakdown.length - 1]?.date}</span>
        </div>
      </div>

      <div className="rounded-xl border border-gray-200 bg-white p-6 shadow-sm">
        <h2 className="text-sm font-semibold text-gray-900">
          Corridas por Dia
        </h2>
        <div className="mt-4">
          <BarChart
            data={barData}
            height={18}
            barColor="#3b82f6"
            formatValue={(v) => `${v} corrida${v !== 1 ? "s" : ""}`}
          />
        </div>
      </div>
    </div>
  );
}
