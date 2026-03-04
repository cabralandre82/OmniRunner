import type { ReactNode } from "react";

interface PanelContainerProps {
  title?: string;
  description?: string;
  actions?: ReactNode;
  children: ReactNode;
  className?: string;
}

export function PanelContainer({
  title,
  description,
  actions,
  children,
  className = "",
}: PanelContainerProps) {
  return (
    <section className={`space-y-4 ${className}`}>
      {(title || actions) && (
        <div className="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
          <div>
            {title && (
              <h2 className="text-title-md font-semibold text-content-primary">
                {title}
              </h2>
            )}
            {description && (
              <p className="mt-1 text-sm text-content-secondary">
                {description}
              </p>
            )}
          </div>
          {actions && <div className="flex items-center gap-2">{actions}</div>}
        </div>
      )}
      {children}
    </section>
  );
}
