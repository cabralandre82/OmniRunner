import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { PlatformSidebar } from "./platform-sidebar";

export const dynamic = "force-dynamic";

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
    <div className="flex h-screen overflow-hidden bg-bg-secondary">
      <PlatformSidebar email={user.email ?? ""} />

      <div className="flex flex-1 flex-col overflow-hidden min-w-0">
        <header className="flex h-14 items-center justify-between border-b border-border bg-surface px-4 sm:px-6">
          <div className="flex items-center gap-2">
            <button
              id="platform-menu-btn"
              className="rounded-lg p-2 text-content-secondary hover:bg-bg-secondary lg:hidden"
              aria-label="Abrir menu"
            >
              <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" d="M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25h16.5" />
              </svg>
            </button>
            <h3 className="text-sm font-semibold text-content-primary">
              Administração da Plataforma
            </h3>
          </div>
        </header>
        <main className="flex-1 overflow-y-auto p-4 sm:p-6">{children}</main>
      </div>
    </div>
  );
}
