interface KpiCardProps {
  label: string;
  value: string | number;
  trend?: number | null;
  trendLabel?: string;
  icon?: React.ReactNode;
  alert?: boolean;
}

export function KpiCard({
  label,
  value,
  trend,
  trendLabel,
  icon,
  alert = false,
}: KpiCardProps) {
  const borderClass = alert
    ? "border-red-200 bg-red-50"
    : "border-gray-200 bg-white";

  return (
    <div className={`rounded-xl border p-5 ${borderClass}`}>
      <div className="flex items-center justify-between">
        <p className="text-sm font-medium text-gray-500">{label}</p>
        {icon && <span className="text-gray-400">{icon}</span>}
      </div>
      <p className="mt-2 text-3xl font-bold text-gray-900">{value}</p>
      {trend != null && (
        <div className="mt-2 flex items-center gap-1">
          {trend > 0 ? (
            <svg
              aria-hidden="true"
              className="h-4 w-4 text-green-600"
              fill="none"
              viewBox="0 0 24 24"
              strokeWidth={2}
              stroke="currentColor"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                d="M4.5 19.5l15-15m0 0H8.25m11.25 0v11.25"
              />
            </svg>
          ) : trend < 0 ? (
            <svg
              aria-hidden="true"
              className="h-4 w-4 text-red-600"
              fill="none"
              viewBox="0 0 24 24"
              strokeWidth={2}
              stroke="currentColor"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                d="M4.5 4.5l15 15m0 0V8.25m0 11.25H8.25"
              />
            </svg>
          ) : null}
          <span
            className={`text-xs font-medium ${
              trend > 0
                ? "text-green-600"
                : trend < 0
                  ? "text-red-600"
                  : "text-gray-500"
            }`}
          >
            {trend > 0 ? "+" : ""}
            {trend}%
          </span>
          {trendLabel && (
            <span className="text-xs text-gray-400">{trendLabel}</span>
          )}
        </div>
      )}
    </div>
  );
}
