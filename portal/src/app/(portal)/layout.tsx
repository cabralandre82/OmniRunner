import { redirect } from "next/navigation";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { Sidebar } from "@/components/sidebar";
import { Header } from "@/components/header";

export default async function PortalLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) redirect("/login");

  const cookieStore = cookies();
  const groupId = cookieStore.get("portal_group_id")?.value;
  const role = cookieStore.get("portal_role")?.value ?? "assistente";

  if (!groupId) redirect("/select-group");

  const { data: memberships } = await supabase
    .from("coaching_members")
    .select("group_id")
    .eq("user_id", user.id)
    .in("role", ["admin_master", "professor", "assistente"]);

  const multiGroup = (memberships?.length ?? 0) > 1;

  const { data: group } = await supabase
    .from("coaching_groups")
    .select("name")
    .eq("id", groupId)
    .single();

  const groupName = group?.name ?? "Assessoria";

  return (
    <div className="flex h-screen overflow-hidden bg-gray-50">
      <Sidebar role={role} />
      <div className="flex flex-1 flex-col overflow-hidden">
        <Header
          groupName={groupName}
          userEmail={user.email ?? ""}
          multiGroup={multiGroup}
        />
        <main className="flex-1 overflow-y-auto p-6">{children}</main>
      </div>
    </div>
  );
}
