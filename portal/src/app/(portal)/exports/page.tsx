"use client";

import { useState } from "react";

const today = new Date().toISOString().slice(0, 10);
const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000)
  .toISOString()
  .slice(0, 10);

interface ExportCardProps {
  title: string;
  description: string;
  from: string;
  to: string;
  onFromChange: (v: string) => void;
  onToChange: (v: string) => void;
  exportHref: string;
}

function ExportCard({
  title,
  description,
  from,
  to,
  onFromChange,
  onToChange,
  exportHref,
}: ExportCardProps) {
  const params = new URLSearchParams();
  if (from) params.set("from", from);
  if (to) params.set("to", to);
  const href = exportHref + (params.toString() ? `?${params.toString()}` : "");

  return (
    <div className="rounded-xl border border-border bg-surface p-4 shadow-sm">
      <h3 className="font-semibold text-content-primary">{title}</h3>
      <p className="mt-1 text-sm text-content-secondary">{description}</p>
      <div className="mt-4 flex flex-wrap items-end gap-3">
        <div>
          <label htmlFor={`${title}-from`} className="block text-xs font-medium text-content-secondary">
            De
          </label>
          <input
            id={`${title}-from`}
            type="date"
            value={from}
            onChange={(e) => onFromChange(e.target.value)}
            className="mt-1 block rounded-md border border-border px-2 py-1.5 text-sm"
          />
        </div>
        <div>
          <label htmlFor={`${title}-to`} className="block text-xs font-medium text-content-secondary">
            Até
          </label>
          <input
            id={`${title}-to`}
            type="date"
            value={to}
            onChange={(e) => onToChange(e.target.value)}
            className="mt-1 block rounded-md border border-border px-2 py-1.5 text-sm"
          />
        </div>
        <a
          href={href}
          className="rounded-lg bg-surface-elevated px-3 py-2 text-sm font-medium text-white hover:bg-bg-secondary"
        >
          Exportar CSV
        </a>
      </div>
    </div>
  );
}

export default function ExportsPage() {
  const [engagementFrom, setEngagementFrom] = useState(thirtyDaysAgo);
  const [engagementTo, setEngagementTo] = useState(today);
  const [attendanceFrom, setAttendanceFrom] = useState(thirtyDaysAgo);
  const [attendanceTo, setAttendanceTo] = useState(today);
  const [crmFrom, setCrmFrom] = useState(thirtyDaysAgo);
  const [crmTo, setCrmTo] = useState(today);
  const [announcementsFrom, setAnnouncementsFrom] = useState(thirtyDaysAgo);
  const [announcementsTo, setAnnouncementsTo] = useState(today);
  const [alertsFrom, setAlertsFrom] = useState(thirtyDaysAgo);
  const [alertsTo, setAlertsTo] = useState(today);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-content-primary">Central de Exports</h1>
        <p className="mt-1 text-sm text-content-secondary">
          Exporte dados CSV de todos os módulos
        </p>
      </div>

      <div className="grid gap-4 sm:grid-cols-1 lg:grid-cols-2">
        <ExportCard
          title="Engajamento"
          description="KPIs diários: dia, score, atletas, coaches, risco churn"
          from={engagementFrom}
          to={engagementTo}
          onFromChange={setEngagementFrom}
          onToChange={setEngagementTo}
          exportHref="/api/export/engagement"
        />
        <ExportCard
          title="Treinos Prescritos"
          description="Treinos, datas, atletas, status de cumprimento, método"
          from={attendanceFrom}
          to={attendanceTo}
          onFromChange={setAttendanceFrom}
          onToChange={setAttendanceTo}
          exportHref="/api/export/attendance"
        />
        <ExportCard
          title="CRM Atletas"
          description="Membros, tags, status e notas"
          from={crmFrom}
          to={crmTo}
          onFromChange={setCrmFrom}
          onToChange={setCrmTo}
          exportHref="/api/export/crm"
        />
        <ExportCard
          title="Mural de Avisos"
          description="Avisos e leituras"
          from={announcementsFrom}
          to={announcementsTo}
          onFromChange={setAnnouncementsFrom}
          onToChange={setAnnouncementsTo}
          exportHref="/api/export/announcements"
        />
        <ExportCard
          title="Alertas"
          description="Atleta, tipo alerta, dia, resolvido, data resolução"
          from={alertsFrom}
          to={alertsTo}
          onFromChange={setAlertsFrom}
          onToChange={setAlertsTo}
          exportHref="/api/export/alerts"
        />
      </div>
    </div>
  );
}
