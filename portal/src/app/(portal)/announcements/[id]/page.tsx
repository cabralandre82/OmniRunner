import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import Link from "next/link";
import { formatDateTime } from "@/lib/format";

export const dynamic = "force-dynamic";

interface ReadRow {
  user_id: string;
  read_at: string;
  display_name: string | null;
}

export default async function AnnouncementDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const groupId = cookies().get("portal_group_id")?.value;
  const role = cookies().get("portal_role")?.value;
  if (!groupId) return null;

  const supabase = createClient();

  const { data: announcement } = await supabase
    .from("coaching_announcements")
    .select("id, title, body, pinned, created_at, created_by")
    .eq("id", id)
    .eq("group_id", groupId)
    .single();

  if (!announcement) {
    return (
      <div className="space-y-6">
        <Link href="/announcements" className="text-sm text-blue-600 hover:underline">
          ← Voltar ao mural
        </Link>
        <div className="rounded-xl border border-gray-200 bg-white p-8 text-center shadow-sm">
          <p className="text-sm text-gray-500">Aviso não encontrado.</p>
        </div>
      </div>
    );
  }

  const { data: author } = await supabase
    .from("profiles")
    .select("display_name")
    .eq("id", announcement.created_by)
    .single();

  const { count: totalMembers } = await supabase
    .from("coaching_members")
    .select("id", { count: "exact", head: true })
    .eq("group_id", groupId);

  const { data: reads } = await supabase
    .from("coaching_announcement_reads")
    .select("user_id, read_at")
    .eq("announcement_id", id)
    .order("read_at", { ascending: true });

  const userIds = Array.from(new Set((reads ?? []).map((r) => r.user_id)));
  const profileMap = new Map<string, string>();
  if (userIds.length > 0) {
    const { data: profiles } = await supabase
      .from("profiles")
      .select("id, display_name")
      .in("id", userIds);
    for (const p of profiles ?? []) {
      profileMap.set(p.id, (p as { id: string; display_name: string }).display_name || "Sem nome");
    }
  }

  const readList: ReadRow[] = (reads ?? []).map((r) => ({
    user_id: (r as { user_id: string }).user_id,
    read_at: (r as { read_at: string }).read_at,
    display_name: profileMap.get((r as { user_id: string }).user_id) ?? null,
  }));

  const readCount = readList.length;
  const total = totalMembers ?? 0;
  const readRate = total > 0 ? (readCount / total) * 100 : 0;
  const isStaff = role && ["admin_master", "coach", "assistant"].includes(role);

  return (
    <div className="space-y-6">
      <Link href="/announcements" className="text-sm text-blue-600 hover:underline">
        ← Voltar ao mural
      </Link>

      <div className="rounded-xl border border-gray-200 bg-white p-6 shadow-sm">
        <div className="flex items-start justify-between gap-4">
          <div>
            <h1 className="text-2xl font-bold text-gray-900">{announcement.title}</h1>
            <p className="mt-1 text-sm text-gray-500">
              Por {(author as { display_name: string } | null)?.display_name ?? "—"} em{" "}
              {formatDateTime(announcement.created_at)}
              {announcement.pinned && (
                <span className="ml-2 inline-flex rounded-full bg-amber-100 px-2 py-0.5 text-xs font-medium text-amber-800">
                  Fixado
                </span>
              )}
            </p>
          </div>
          {isStaff && (
            <Link
              href={`/announcements/${id}/edit`}
              className="rounded-lg border border-gray-300 bg-white px-3 py-1.5 text-sm font-medium text-gray-700 shadow-sm hover:bg-gray-50"
            >
              Editar
            </Link>
          )}
        </div>
        <div className="mt-4 whitespace-pre-wrap text-gray-700">
          {announcement.body}
        </div>
      </div>

      {isStaff && (
        <div className="rounded-xl border border-gray-200 bg-white p-6 shadow-sm">
          <h2 className="text-sm font-semibold text-gray-900">Estatísticas de leitura</h2>
          <p className="mt-2 text-2xl font-bold text-gray-900">
            Lido por {readCount} de {total} ({readRate.toFixed(1)}%)
          </p>
          {readList.length > 0 ? (
            <div className="mt-4 overflow-hidden rounded-lg border border-gray-200">
              <table className="min-w-full divide-y divide-gray-200 text-sm">
                <thead className="bg-gray-50">
                  <tr>
                    <th className="px-4 py-2 text-left font-medium text-gray-500">
                      Membro
                    </th>
                    <th className="px-4 py-2 text-left font-medium text-gray-500">
                      Lido em
                    </th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {readList.map((r) => (
                    <tr key={r.user_id + r.read_at} className="hover:bg-gray-50">
                      <td className="whitespace-nowrap px-4 py-2 font-medium text-gray-900">
                        {r.display_name ?? "—"}
                      </td>
                      <td className="whitespace-nowrap px-4 py-2 text-gray-600">
                        {formatDateTime(r.read_at)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : (
            <p className="mt-2 text-sm text-gray-500">Ninguém leu este aviso ainda.</p>
          )}
        </div>
      )}
    </div>
  );
}
