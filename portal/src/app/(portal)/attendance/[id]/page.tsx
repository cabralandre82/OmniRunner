import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import Link from "next/link";
import { formatDateISO, formatDateTime } from "@/lib/format";

export const dynamic = "force-dynamic";

const STATUS_LABELS: Record<string, string> = {
  present: "Presente",
  late: "Atrasado",
  excused: "Justificado",
  absent: "Ausente",
};

const METHOD_LABELS: Record<string, string> = {
  qr: "QR",
  manual: "Manual",
};

export default async function AttendanceDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id: sessionId } = await params;
  const groupId = cookies().get("portal_group_id")?.value;
  const role = cookies().get("portal_role")?.value;
  if (!groupId) return null;

  const supabase = createClient();

  const { data: session } = await supabase
    .from("coaching_training_sessions")
    .select("id, title, starts_at, ends_at, location_name, status")
    .eq("id", sessionId)
    .eq("group_id", groupId)
    .single();

  if (!session) {
    return (
      <div className="space-y-6">
        <Link href="/attendance" className="text-sm text-blue-600 hover:underline">
          ← Voltar ao relatório
        </Link>
        <div className="rounded-xl border border-gray-200 bg-white p-8 text-center shadow-sm">
          <p className="text-sm text-gray-500">Treino não encontrado.</p>
        </div>
      </div>
    );
  }

  const { data: attendance } = await supabase
    .from("coaching_training_attendance")
    .select("id, athlete_user_id, checked_at, method, status")
    .eq("session_id", sessionId)
    .eq("group_id", groupId)
    .order("checked_at", { ascending: true });

  const athleteIds = Array.from(new Set((attendance ?? []).map((a) => a.athlete_user_id)));
  const profileMap = new Map<string, string>();

  if (athleteIds.length > 0) {
    const { data: profiles } = await supabase
      .from("profiles")
      .select("id, display_name")
      .in("id", athleteIds);

    for (const p of profiles ?? []) {
      profileMap.set(p.id, p.display_name || "Sem nome");
    }
  }

  const { count: athleteCount } = await supabase
    .from("coaching_members")
    .select("id", { count: "exact", head: true })
    .eq("group_id", groupId)
    .eq("role", "athlete");

  const presentes = (attendance ?? []).filter((a) => a.status === "present").length;
  const total = athleteCount ?? 0;
  const pct = total > 0 ? (presentes / total) * 100 : 0;

  const canMarkAttendance = role === "admin_master" || role === "coach";

  return (
    <div className="space-y-6">
      <Link href="/attendance" className="text-sm text-blue-600 hover:underline">
        ← Voltar ao relatório
      </Link>

      <div>
        <h1 className="text-2xl font-bold text-gray-900">{session.title}</h1>
        <p className="mt-1 text-sm text-gray-500">
          Detalhes da presença no treino
        </p>
      </div>

      <div className="rounded-xl border border-gray-200 bg-white p-6 shadow-sm">
        <h2 className="text-sm font-semibold text-gray-900">Informações do treino</h2>
        <dl className="mt-3 grid gap-2 sm:grid-cols-2">
          <div>
            <dt className="text-xs text-gray-500">Data</dt>
            <dd className="text-sm font-medium text-gray-900">{formatDateISO(session.starts_at)}</dd>
          </div>
          <div>
            <dt className="text-xs text-gray-500">Local</dt>
            <dd className="text-sm font-medium text-gray-900">{session.location_name || "—"}</dd>
          </div>
          <div>
            <dt className="text-xs text-gray-500">Status</dt>
            <dd className="text-sm font-medium text-gray-900">
              <span
                className={`inline-flex rounded-full px-2 py-0.5 text-xs font-medium ${
                  session.status === "done"
                    ? "bg-green-100 text-green-800"
                    : session.status === "cancelled"
                      ? "bg-red-100 text-red-800"
                      : "bg-blue-100 text-blue-800"
                }`}
              >
                {session.status === "done" ? "Realizado" : session.status === "cancelled" ? "Cancelado" : "Agendado"}
              </span>
            </dd>
          </div>
        </dl>
      </div>

      <div className="rounded-xl border border-gray-200 bg-white p-6 shadow-sm">
        <div className="flex items-center justify-between">
          <h2 className="text-sm font-semibold text-gray-900">Presença</h2>
          {canMarkAttendance && (
            <button
              type="button"
              className="rounded-lg border border-gray-300 bg-white px-3 py-1.5 text-xs font-medium text-gray-700 shadow-sm hover:bg-gray-50"
              disabled
              title="Em breve"
            >
              Marcar presença manualmente
            </button>
          )}
        </div>
        <p className="mt-2 text-2xl font-bold text-gray-900">
          {presentes} / {total} atletas = {pct.toFixed(1)}%
        </p>
      </div>

      <div className="overflow-hidden rounded-xl border border-gray-200 bg-white shadow-sm">
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-gray-200 text-sm">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-4 py-3 text-left font-medium text-gray-500">Nome</th>
                <th className="px-4 py-3 text-left font-medium text-gray-500">Check-in</th>
                <th className="px-4 py-3 text-left font-medium text-gray-500">Método</th>
                <th className="px-4 py-3 text-left font-medium text-gray-500">Status</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {(attendance ?? []).map((a) => (
                <tr key={a.id} className="hover:bg-gray-50">
                  <td className="whitespace-nowrap px-4 py-3 font-medium text-gray-900">
                    {profileMap.get(a.athlete_user_id) ?? "—"}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-gray-600">
                    {formatDateTime(a.checked_at)}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-gray-600">
                    {METHOD_LABELS[a.method] ?? a.method}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3">
                    <span
                      className={`inline-flex rounded-full px-2.5 py-0.5 text-xs font-medium ${
                        a.status === "present"
                          ? "bg-green-100 text-green-800"
                          : a.status === "late"
                            ? "bg-yellow-100 text-yellow-800"
                            : a.status === "excused"
                              ? "bg-blue-100 text-blue-800"
                              : "bg-gray-100 text-gray-600"
                      }`}
                    >
                      {STATUS_LABELS[a.status] ?? a.status}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {(attendance ?? []).length === 0 && (
        <div className="rounded-xl border border-gray-200 bg-white p-8 text-center shadow-sm">
          <p className="text-sm text-gray-500">
            Nenhum check-in registrado neste treino.
          </p>
        </div>
      )}
    </div>
  );
}
