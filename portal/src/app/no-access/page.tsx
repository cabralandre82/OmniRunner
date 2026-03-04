import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { signOut } from "@/lib/actions";

export const dynamic = "force-dynamic";

export default async function NoAccessPage() {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const email = user?.email;

  if (user) {
    const { data: profile } = await supabase
      .from("profiles")
      .select("platform_role")
      .eq("id", user.id)
      .single();

    if (profile?.platform_role === "admin") {
      redirect("/platform/assessorias");
    }
  }

  let reason = "Sua conta não possui permissão de staff em nenhuma assessoria.";

  if (user) {
    const { data: membership } = await supabase
      .from("coaching_members")
      .select("role")
      .eq("user_id", user.id)
      .limit(1)
      .maybeSingle();

    if (membership?.role === "athlete") {
      reason =
        "Sua conta está vinculada como atleta. " +
        "O portal é exclusivo para administradores, professores e assistentes. " +
        "Use o app Omni Runner para acessar suas funcionalidades.";
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-bg-secondary">
      <div className="max-w-sm space-y-4 rounded-xl bg-surface p-8 text-center shadow-lg">
        <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-error-soft">
          <span className="text-xl text-error">✕</span>
        </div>
        <h1 className="text-xl font-bold text-content-primary">Acesso Negado</h1>
        <p className="text-sm text-content-secondary">{reason}</p>
        {email && (
          <p className="text-xs text-content-muted">
            Logado como: {email}
          </p>
        )}
        <form action={signOut}>
          <button
            type="submit"
            className="mt-2 inline-block rounded-lg bg-surface-elevated px-4 py-2 text-sm font-medium text-content-secondary hover:bg-bg-secondary"
          >
            Sair e usar outra conta
          </button>
        </form>
      </div>
    </div>
  );
}
