import { createClient } from "@/lib/supabase/server";
import { signOut } from "@/lib/actions";

export default async function NoAccessPage() {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const email = user?.email;

  let reason = "Sua conta não possui permissão de staff em nenhuma assessoria.";

  if (user) {
    const { data: membership } = await supabase
      .from("coaching_members")
      .select("role")
      .eq("user_id", user.id)
      .limit(1)
      .maybeSingle();

    if (membership?.role === "atleta") {
      reason =
        "Sua conta está vinculada como atleta. " +
        "O portal é exclusivo para administradores, professores e assistentes. " +
        "Use o app Omni Runner para acessar suas funcionalidades.";
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-gray-50">
      <div className="max-w-sm space-y-4 rounded-xl bg-white p-8 text-center shadow-lg">
        <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-red-100">
          <span className="text-xl text-red-600">✕</span>
        </div>
        <h1 className="text-xl font-bold text-gray-900">Acesso Negado</h1>
        <p className="text-sm text-gray-500">{reason}</p>
        {email && (
          <p className="text-xs text-gray-400">
            Logado como: {email}
          </p>
        )}
        <form action={signOut}>
          <button
            type="submit"
            className="mt-2 inline-block rounded-lg bg-gray-100 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-200"
          >
            Sair e usar outra conta
          </button>
        </form>
      </div>
    </div>
  );
}
