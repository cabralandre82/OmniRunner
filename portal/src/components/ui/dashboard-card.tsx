import type { ReactNode } from "react";

interface DashboardCardProps {
  title?: string;
  description?: string;
  actions?: ReactNode;
  children: ReactNode;
  className?: string;
  noPadding?: boolean;
}

export function DashboardCard({
  title,
  description,
  actions,
  children,
  className = "",
  noPadding = false,
}: DashboardCardProps) {
  return (
    <div
      className={`rounded-xl border border-border bg-surface shadow-sm transition-colors ${className}`}
    >
      {(title || actions) && (
        <div className="flex items-center justify-between border-b border-border-subtle px-6 py-4">
          <div>
            {title && (
              <h3 className="text-sm font-semibold text-content-primary">
                {title}
              </h3>
            )}
            {description && (
              <p className="mt-0.5 text-xs text-content-muted">{description}</p>
            )}
          </div>
          {actions && <div className="flex items-center gap-2">{actions}</div>}
        </div>
      )}
      <div className={noPadding ? "" : "p-6"}>{children}</div>
    </div>
  );
}
