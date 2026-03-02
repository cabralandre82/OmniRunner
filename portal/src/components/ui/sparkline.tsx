"use client";

interface SparklineProps {
  data: number[];
  width?: number;
  height?: number;
  color?: string;
  fillOpacity?: number;
  strokeWidth?: number;
  className?: string;
  label?: string;
}

/**
 * Minimal SVG sparkline chart — zero dependencies.
 * Renders a smooth area chart for KPI trend visualization.
 */
export function Sparkline({
  data,
  width = 200,
  height = 50,
  color = "#3b82f6",
  fillOpacity = 0.15,
  strokeWidth = 2,
  className = "",
  label,
}: SparklineProps) {
  if (data.length < 2) {
    return (
      <svg width={width} height={height} className={className} role="img" aria-label={label}>
        <text x={width / 2} y={height / 2} textAnchor="middle" className="fill-gray-300 text-xs">
          —
        </text>
      </svg>
    );
  }

  const padding = strokeWidth;
  const chartW = width - padding * 2;
  const chartH = height - padding * 2;

  const min = Math.min(...data);
  const max = Math.max(...data);
  const range = max - min || 1;

  const points = data.map((v, i) => ({
    x: padding + (i / (data.length - 1)) * chartW,
    y: padding + chartH - ((v - min) / range) * chartH,
  }));

  const linePath = points.map((p, i) => `${i === 0 ? "M" : "L"} ${p.x} ${p.y}`).join(" ");
  const areaPath = `${linePath} L ${points[points.length - 1].x} ${height - padding} L ${points[0].x} ${height - padding} Z`;

  return (
    <svg
      width={width}
      height={height}
      className={className}
      role="img"
      aria-label={label ?? `Sparkline chart with ${data.length} data points`}
    >
      <path d={areaPath} fill={color} fillOpacity={fillOpacity} />
      <path d={linePath} fill="none" stroke={color} strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round" />
      {points.length > 0 && (
        <circle
          cx={points[points.length - 1].x}
          cy={points[points.length - 1].y}
          r={strokeWidth + 1}
          fill={color}
        />
      )}
    </svg>
  );
}
