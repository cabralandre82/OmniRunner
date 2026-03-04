"use client";

import { useEffect, useState } from "react";

interface StaffAlert {
  key: string;
  label: string;
  count: number;
  severity: "warning" | "error" | "info";
}

const SEVERITY_STYLES: Record<string, string> = {
  error: "border-error/30 bg-error-soft text-error",
  warning: "border-warning/30 bg-warning-soft text-warning",
  info: "border-info/30 bg-info-soft text-info",
};

export function DashboardAlerts() {
  const [alerts, setAlerts] = useState<StaffAlert[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetch("/api/staff-alerts")
      .then((res) => (res.ok ? res.json() : { alerts: [] }))
      .then((data: { alerts: StaffAlert[] }) => setAlerts(data.alerts ?? []))
      .catch(() => setAlerts([]))
      .finally(() => setLoading(false));
  }, []);

  if (loading || alerts.length === 0) return null;

  return (
    <div className="space-y-2">
      <h3 className="text-sm font-semibold text-content-primary">Alertas</h3>
      <div className="space-y-2">
        {alerts.map((alert) => (
          <div
            key={alert.key}
            className={`flex items-center gap-3 rounded-lg border px-4 py-2.5 text-sm font-medium ${SEVERITY_STYLES[alert.severity] ?? SEVERITY_STYLES.info}`}
          >
            {alert.severity === "error" ? (
              <svg className="h-4 w-4 flex-shrink-0" fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z" />
              </svg>
            ) : (
              <svg className="h-4 w-4 flex-shrink-0" fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" d="M12 9v3.75m9-.75a9 9 0 11-18 0 9 9 0 0118 0zm-9 3.75h.008v.008H12v-.008z" />
              </svg>
            )}
            <span>{alert.label}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
