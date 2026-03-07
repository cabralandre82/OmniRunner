import { redirect } from "next/navigation";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { isFeatureEnabled } from "@/lib/feature-flags";
import { Sidebar } from "@/components/sidebar";
import { Header } from "@/components/header";
import { KeyboardShortcuts } from "@/components/keyboard-shortcuts";
import { OnboardingOverlay } from "@/components/onboarding/onboarding-overlay";
import { PageWrapper } from "@/components/page-wrapper";

interface Branding {
  logo_url: string | null;
  primary_color: string;
  sidebar_bg: string;
  sidebar_text: string;
  accent_color: string;
}

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
  let role = cookieStore.get("portal_role")?.value ?? "assistant";

  if (!groupId) {
    const { data: profile } = await supabase
      .from("profiles")
      .select("platform_role")
      .eq("id", user.id)
      .single();

    if (profile?.platform_role === "admin") {
      redirect("/platform/assessorias");
    }

    redirect("/select-group");
  }

  const { data: memberships } = await supabase
    .from("coaching_members")
    .select("group_id, role")
    .eq("user_id", user.id)
    .in("role", ["admin_master", "coach", "assistant"]);

  const multiGroup = (memberships?.length ?? 0) > 1;

  // Re-verify: user must belong to the group in cookie (defense in depth)
  const membershipForGroup = memberships?.find((m) => m.group_id === groupId);
  if (!membershipForGroup) {
    redirect("/select-group");
  }
  const roleFromDb = membershipForGroup.role ?? role;

  let groupName = "Assessoria";
  let isPlatformAdmin = false;
  let isBlocked = false;
  let branding: Branding = {
    logo_url: null,
    primary_color: "#3b82f6",
    sidebar_bg: "#111827",
    sidebar_text: "#f1f5f9",
    accent_color: "#3b82f6",
  };
  let tpEnabled = false;

  try {
    const [groupRes, profileRes, brandingRes, custodyRes] =
      await Promise.allSettled([
        supabase
          .from("coaching_groups")
          .select("name")
          .eq("id", groupId)
          .single(),
        supabase
          .from("profiles")
          .select("platform_role")
          .eq("id", user.id)
          .single(),
        supabase
          .from("portal_branding")
          .select(
            "logo_url, primary_color, sidebar_bg, sidebar_text, accent_color",
          )
          .eq("group_id", groupId)
          .maybeSingle(),
        supabase
          .from("custody_accounts")
          .select("is_blocked")
          .eq("group_id", groupId)
          .maybeSingle(),
      ]);

    if (groupRes.status === "fulfilled") {
      groupName = groupRes.value.data?.name ?? groupName;
    }
    if (profileRes.status === "fulfilled") {
      isPlatformAdmin = profileRes.value.data?.platform_role === "admin";
    }
    if (custodyRes.status === "fulfilled") {
      isBlocked = custodyRes.value.data?.is_blocked ?? false;
    }
    if (brandingRes.status === "fulfilled" && brandingRes.value.data) {
      branding = {
        logo_url: brandingRes.value.data.logo_url ?? null,
        primary_color: brandingRes.value.data.primary_color ?? "#3b82f6",
        sidebar_bg: brandingRes.value.data.sidebar_bg ?? "#111827",
        sidebar_text: brandingRes.value.data.sidebar_text ?? "#f1f5f9",
        accent_color: brandingRes.value.data.accent_color ?? "#3b82f6",
      };
    }

    tpEnabled = await isFeatureEnabled("trainingpeaks_enabled");
  } catch (err) {
    console.error("Portal layout: failed to load data", err);
    const environment = process.env.NEXT_PUBLIC_ENV ?? "production";
    return (
      <div className="flex h-screen items-center justify-center bg-gray-50 p-8 text-center">
        <div>
          <h2 className="text-xl font-semibold text-gray-800">
            Unable to load the portal
          </h2>
          <p className="mt-2 text-sm text-gray-500">
            A temporary error occurred. Please refresh or try again later.
          </p>
        </div>
      </div>
    );
  }

  const environment = process.env.NEXT_PUBLIC_ENV ?? "production";

  const cssVars = {
    "--brand-primary": branding.primary_color,
    "--brand-sidebar-bg": branding.sidebar_bg,
    "--brand-sidebar-text": branding.sidebar_text,
    "--brand-accent": branding.accent_color,
  } as React.CSSProperties;

  return (
    <div className="flex h-screen overflow-hidden bg-bg-primary" style={cssVars}>
      <KeyboardShortcuts />
      <OnboardingOverlay />
      <Sidebar
        role={roleFromDb}
        isPlatformAdmin={isPlatformAdmin}
        logoUrl={branding.logo_url}
        groupName={groupName}
        trainingpeaksEnabled={tpEnabled}
      />
      <div className="flex flex-1 flex-col overflow-hidden">
        <Header
          groupName={groupName}
          userEmail={user.email ?? ""}
          multiGroup={multiGroup}
          role={roleFromDb}
          environment={environment}
          isBlocked={isBlocked}
        />
        <main className="flex-1 overflow-y-auto bg-bg-primary p-4 sm:p-6">
          <PageWrapper>{children}</PageWrapper>
        </main>
      </div>
    </div>
  );
}
