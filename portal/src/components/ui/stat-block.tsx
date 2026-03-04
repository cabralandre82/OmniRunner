interface StatBlockProps {
  label: string;
  value: string | number;
  detail?: string;
  trend?: number;
  alert?: boolean;
  accentClass?: string;
}

export function StatBlock({
  label,
  value,
  detail,
  trend,
  alert = false,
  accentClass,
}: StatBlockProps) {
  const containerClass = alert
    ? "border-error/30 bg-error-soft"
    : "border-border bg-surface";

  return (
    <div
      className={`rounded-xl border p-5 shadow-sm transition-colors ${containerClass}`}
    >
      <p className="text-xs font-medium uppercase tracking-wide text-content-muted">
        {label}
      </p>
      <div className="mt-2 flex items-baseline gap-2">
        <p
          className={`text-2xl font-bold ${accentClass ?? "text-content-primary"}`}
        >
          {value}
        </p>
        {trend !== undefined && trend !== 0 && (
          <span
            className={`inline-flex items-center gap-0.5 text-xs font-semibold ${
              trend > 0 ? "text-success" : "text-error"
            }`}
          >
            <svg
              className="h-3 w-3"
              fill="none"
              viewBox="0 0 24 24"
              strokeWidth={2.5}
              stroke="currentColor"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                d={
                  trend > 0
                    ? "M4.5 19.5l15-15m0 0H8.25m11.25 0v11.25"
                    : "M4.5 4.5l15 15m0 0V8.25m0 11.25H8.25"
                }
              />
            </svg>
            {trend > 0 ? "+" : ""}
            {trend}%
          </span>
        )}
      </div>
      {detail && (
        <p className="mt-1 text-xs text-content-muted">{detail}</p>
      )}
    </div>
  );
}
