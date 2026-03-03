import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import Link from "next/link";
import { redirect } from "next/navigation";
import { AnnouncementForm } from "../../announcement-form";

export const dynamic = "force-dynamic";

export default async function AnnouncementEditPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const groupId = cookies().get("portal_group_id")?.value;
  const role = cookies().get("portal_role")?.value;
  if (!groupId) return null;

  const canEdit = role === "admin_master" || role === "coach";
  if (!canEdit) redirect("/announcements");

  const supabase = createClient();
  const { data: announcement } = await supabase
    .from("coaching_announcements")
    .select("id, title, body, pinned")
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

  return (
    <div className="space-y-6">
      <Link href="/announcements" className="text-sm text-blue-600 hover:underline">
        ← Voltar ao mural
      </Link>
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Editar aviso</h1>
        <p className="mt-1 text-sm text-gray-500">
          Alterar título, conteúdo ou fixar/desfixar
        </p>
      </div>
      <AnnouncementForm
        groupId={groupId}
        editId={announcement.id}
        editTitle={announcement.title}
        editBody={announcement.body}
        editPinned={announcement.pinned ?? false}
      />
    </div>
  );
}
