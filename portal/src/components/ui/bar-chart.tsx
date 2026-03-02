"use client";

interface BarChartProps {
  data: { label: string; value: number; color?: string }[];
  height?: number;
  barColor?: string;
  className?: string;
  formatValue?: (v: number) => string;
}

/**
 * Simple horizontal bar chart — zero dependencies.
 * Useful for distribution breakdowns (coins per issuer, athletes per group, etc.).
 */
export function BarChart({
  data,
  height = 24,
  barColor = "#3b82f6",
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
            <div className="flex items-center justify-between text-xs text-gray-600">
              <span className="truncate">{item.label}</span>
              <span className="font-medium tabular-nums">{formatValue(item.value)}</span>
            </div>
            <div className="w-full rounded-full bg-gray-100" style={{ height }}>
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
