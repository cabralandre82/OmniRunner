"use client";

interface BarChartProps {
  data: { label: string; value: number; color?: string }[];
  height?: number;
  barColor?: string;
  className?: string;
  formatValue?: (v: number) => string;
}

export function BarChart({
  data,
  height = 24,
  barColor = "var(--primary)",
  className = "",
  formatValue = (v) => String(v),
}: BarChartProps) {
  const max = Math.max(...data.map((d) => d.value), 1);

  return (
    <div className={`space-y-2 ${className}`} role="img" aria-label="Bar chart">
      {data.map((item) => {
        const pct = (item.value / max) * 100;
        return (
          <div key={item.label} className="space-y-1">
            <div className="flex items-center justify-between text-xs text-content-secondary">
              <span className="truncate">{item.label}</span>
              <span className="font-medium tabular-nums">{formatValue(item.value)}</span>
            </div>
            <div className="w-full rounded-full bg-bg-secondary" style={{ height }}>
              <div
                className="rounded-full transition-all duration-500"
                style={{
                  width: `${pct}%`,
                  height,
                  backgroundColor: item.color ?? barColor,
                  minWidth: item.value > 0 ? 4 : 0,
                }}
              />
            </div>
          </div>
        );
      })}
    </div>
  );
}
