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
    .in("role", ["admin_master", "coach", "assistant"]);

  const memberships = data ?? [];

  if (memberships.length === 0) {
    const { data: profile } = await supabase
      .from("profiles")
      .select("platform_role")
      .eq("id", user.id)
      .single();

    if (profile?.platform_role === "admin") {
      redirect("/platform/assessorias");
    }

    redirect("/no-access");
  }
  if (memberships.length === 1) {
    const m = memberships[0];
    redirect(
      `/api/set-group?groupId=${encodeURIComponent(m.group_id as string)}&role=${encodeURIComponent(m.role as string)}`,
    );
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-bg-secondary">
      <div className="w-full max-w-md space-y-6 rounded-xl bg-surface p-8 shadow-lg">
        <div className="text-center">
          <h1 className="text-xl font-bold text-content-primary">
            Selecione a Assessoria
          </h1>
          <p className="mt-1 text-sm text-content-secondary">
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
                  className="flex w-full items-center justify-between rounded-lg border border-border p-4 text-left transition hover:border-blue-300 hover:bg-brand-soft"
                >
                  <div>
                    <p className="font-medium text-content-primary">
                      {groupName ?? "Assessoria"}
                    </p>
                    <p className="text-xs text-content-secondary">{role}</p>
                  </div>
                  <span className="text-content-muted">→</span>
                </button>
              </form>
            );
          })}
        </div>
      </div>
    </div>
  );
}
