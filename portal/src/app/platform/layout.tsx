import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import Link from "next/link";

export default async function PlatformLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) redirect("/login");

  const { data: profile } = await supabase
    .from("profiles")
    .select("platform_role")
    .eq("id", user.id)
    .single();

  if (profile?.platform_role !== "admin") {
    redirect("/no-access");
  }

  return (
    <div className="flex h-screen overflow-hidden bg-gray-50">
      <aside className="flex h-screen w-56 flex-col border-r border-gray-200 bg-white">
        <div className="border-b border-gray-200 px-4 py-5">
          <h2 className="text-lg font-bold text-gray-900">Omni Runner</h2>
          <p className="text-xs text-red-500 font-semibold">Admin Plataforma</p>
        </div>

        <nav className="flex-1 space-y-1 px-2 py-4">
          <Link
            href="/platform/assessorias"
            className="block rounded-lg px-3 py-2 text-sm font-medium text-gray-600 hover:bg-gray-50 hover:text-gray-900"
          >
            Assessorias
          </Link>
          <Link
            href="/dashboard"
            className="block rounded-lg px-3 py-2 text-sm font-medium text-gray-400 hover:bg-gray-50 hover:text-gray-600"
          >
            ← Portal Staff
          </Link>
        </nav>

        <div className="border-t border-gray-200 px-4 py-3">
          <p className="truncate text-xs text-gray-400">{user.email}</p>
        </div>
      </aside>

      <div className="flex flex-1 flex-col overflow-hidden">
        <header className="flex h-14 items-center justify-between border-b border-gray-200 bg-white px-6">
          <h3 className="text-sm font-semibold text-gray-900">
            Administração da Plataforma
          </h3>
        </header>
        <main className="flex-1 overflow-y-auto p-6">{children}</main>
      </div>
    </div>
  );
}
