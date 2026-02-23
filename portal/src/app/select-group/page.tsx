import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { setPortalGroup } from "@/lib/actions";

export default async function SelectGroupPage() {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) redirect("/login");

  const { data } = await supabase
    .from("coaching_members")
    .select("group_id, role, coaching_groups(name)")
    .eq("user_id", user.id)
    .in("role", ["admin_master", "professor", "assistente"]);

  const memberships = data ?? [];

  if (memberships.length === 0) redirect("/no-access");
  if (memberships.length === 1) {
    const m = memberships[0];
    await setPortalGroup(m.group_id as string, m.role as string);
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-gray-50">
      <div className="w-full max-w-md space-y-6 rounded-xl bg-white p-8 shadow-lg">
        <div className="text-center">
          <h1 className="text-xl font-bold text-gray-900">
            Selecione a Assessoria
          </h1>
          <p className="mt-1 text-sm text-gray-500">
            Você pertence a mais de uma assessoria
          </p>
        </div>

        <div className="space-y-3">
          {memberships.map((m) => {
            const groupId = m.group_id as string;
            const role = m.role as string;
            const groups = m.coaching_groups as unknown as
              | { name: string }
              | { name: string }[]
              | null;
            const groupName = Array.isArray(groups)
              ? groups[0]?.name
              : groups?.name;

            return (
              <form key={groupId} action={setPortalGroup.bind(null, groupId, role)}>
                <button
                  type="submit"
                  className="flex w-full items-center justify-between rounded-lg border border-gray-200 p-4 text-left transition hover:border-blue-300 hover:bg-blue-50"
                >
                  <div>
                    <p className="font-medium text-gray-900">
                      {groupName ?? "Assessoria"}
                    </p>
                    <p className="text-xs text-gray-500">{role}</p>
                  </div>
                  <span className="text-gray-400">→</span>
                </button>
              </form>
            );
          })}
        </div>
      </div>
    </div>
  );
}
