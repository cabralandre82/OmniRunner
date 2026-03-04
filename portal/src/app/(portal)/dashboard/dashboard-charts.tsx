"use client";

import { Sparkline, BarChart, DashboardCard } from "@/components/ui";

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
      <DashboardCard title="Tendência — Corridas (7d)">
        <div className="flex justify-center">
          <Sparkline
            data={sessionData}
            width={360}
            height={80}
            label="Tendência de corridas nos últimos 7 dias"
          />
        </div>
        <div className="mt-2 flex justify-between text-[10px] text-content-muted">
          <span>{dailyBreakdown[0]?.date}</span>
          <span>{dailyBreakdown[dailyBreakdown.length - 1]?.date}</span>
        </div>
      </DashboardCard>

      <DashboardCard title="Corridas por Dia">
        <BarChart
          data={barData}
          height={18}
          formatValue={(v) => `${v} corrida${v !== 1 ? "s" : ""}`}
        />
      </DashboardCard>
    </div>
  );
}
