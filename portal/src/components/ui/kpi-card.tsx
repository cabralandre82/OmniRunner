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
    ? "border-error/30 bg-error-soft"
    : "border-border bg-surface";

  return (
    <div className={`rounded-xl border p-5 shadow-sm transition-colors ${borderClass}`}>
      <div className="flex items-center justify-between">
        <p className="text-sm font-medium text-content-muted">{label}</p>
        {icon && <span className="text-content-muted">{icon}</span>}
      </div>
      <p className="mt-2 text-3xl font-bold text-content-primary">{value}</p>
      {trend != null && (
        <div className="mt-2 flex items-center gap-1">
          {trend > 0 ? (
            <svg
              aria-hidden="true"
              className="h-4 w-4 text-success"
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
              className="h-4 w-4 text-error"
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
                ? "text-success"
                : trend < 0
                  ? "text-error"
                  : "text-content-muted"
            }`}
          >
            {trend > 0 ? "+" : ""}
            {trend}%
          </span>
          {trendLabel && (
            <span className="text-xs text-content-muted">{trendLabel}</span>
          )}
        </div>
      )}
    </div>
  );
}
