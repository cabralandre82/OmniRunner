import type { Metadata } from "next";
import Link from "next/link";
import { cookies } from "next/headers";
import { createServiceClient } from "@/lib/supabase/service";
import { NoGroupSelected } from "@/components/no-group-selected";
import { StatBlock, DashboardCard } from "@/components/ui";
import { formatKm } from "@/lib/format";

export const metadata: Metadata = { title: "Perfil do Atleta" };
export const dynamic = "force-dynamic";

interface AthleteProfile {
  displayName: string;
  level: number;
  xp: number;
  currentStreak: number;
  badgeCount: number;
  recentSessions: number;
  totalDistance: number;
}

export default async function AthleteProfilePage({
  params,
}: {
  params: { id: string };
}) {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return <NoGroupSelected />;

  const athleteId = params.id;
  const db = createServiceClient();

  const { data: member } = await db
    .from("coaching_members")
    .select("user_id, display_name")
    .eq("group_id", groupId)
    .eq("user_id", athleteId)
    .in("role", ["athlete", "atleta"])
    .maybeSingle();

  if (!member) {
    return (
      <div className="space-y-4">
        <Link
          href="/athletes"
          className="inline-flex items-center gap-1 text-sm text-content-muted hover:text-content-primary transition-colors"
        >
          <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" d="M15.75 19.5L8.25 12l7.5-7.5" />
          </svg>
          Voltar
        </Link>
        <div className="rounded-xl border border-error/30 bg-error-soft p-8 text-center">
          <h2 className="text-lg font-semibold text-error">Atleta não encontrado</h2>
          <p className="mt-2 text-sm text-content-secondary">
            Este atleta não pertence ao grupo atual ou não existe.
          </p>
        </div>
      </div>
    );
  }

  const typedMember = member as { user_id: string; display_name: string };
  let profile: AthleteProfile = {
    displayName: typedMember.display_name || "Sem nome",
    level: 0,
    xp: 0,
    currentStreak: 0,
    badgeCount: 0,
    recentSessions: 0,
    totalDistance: 0,
  };

  try {
    const thirtyDaysAgo = Date.now() - 30 * 86_400_000;

    const [progressRes, badgeRes, sessionsRes] = await Promise.all([
      db
        .from("profile_progress")
        .select("level, total_xp, daily_streak_count")
        .eq("user_id", athleteId)
        .maybeSingle(),
      db
        .from("badge_awards")
        .select("id", { count: "exact", head: true })
        .eq("user_id", athleteId),
      db
        .from("sessions")
        .select("total_distance_m")
        .eq("user_id", athleteId)
        .gte("start_time_ms", thirtyDaysAgo)
        .gte("status", 3),
    ]);

    const progress = progressRes.data as {
      level: number;
      total_xp: number;
      daily_streak_count: number;
    } | null;

    const sessions = (sessionsRes.data ?? []) as { total_distance_m: number }[];

    profile = {
      ...profile,
      level: progress?.level ?? 0,
      xp: progress?.total_xp ?? 0,
      currentStreak: progress?.daily_streak_count ?? 0,
      badgeCount: badgeRes.count ?? 0,
      recentSessions: sessions.length,
      totalDistance: sessions.reduce((sum, s) => sum + (s.total_distance_m ?? 0), 0),
    };
  } catch {
    // partial data is fine — show what we have
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3">
        <Link
          href="/athletes"
          className="inline-flex items-center gap-1 text-sm text-content-muted hover:text-content-primary transition-colors"
        >
          <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" d="M15.75 19.5L8.25 12l7.5-7.5" />
          </svg>
          Atletas
        </Link>
      </div>

      <div>
        <h1 className="text-2xl font-bold text-content-primary">
          {profile.displayName}
        </h1>
        <p className="mt-1 text-sm text-content-secondary">
          Como o atleta vê — visão simplificada do perfil
        </p>
      </div>

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <StatBlock
          label="Level"
          value={profile.level}
          detail={`${profile.xp.toLocaleString("pt-BR")} XP`}
          accentClass="text-brand"
        />
        <StatBlock
          label="Streak Atual"
          value={`${profile.currentStreak} dia${profile.currentStreak !== 1 ? "s" : ""}`}
          accentClass="text-warning"
        />
        <StatBlock
          label="Badges"
          value={profile.badgeCount}
          accentClass="text-info"
        />
        <StatBlock
          label="Corridas (30d)"
          value={profile.recentSessions}
          detail={`${formatKm(profile.totalDistance)} km`}
          accentClass="text-success"
        />
      </div>

      <DashboardCard title="Resumo">
        <div className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-2 text-sm">
            <div className="flex justify-between">
              <span className="text-content-muted">Level</span>
              <span className="font-medium text-content-primary">{profile.level}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-content-muted">XP Total</span>
              <span className="font-medium text-content-primary">{profile.xp.toLocaleString("pt-BR")}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-content-muted">Streak</span>
              <span className="font-medium text-content-primary">{profile.currentStreak} dia{profile.currentStreak !== 1 ? "s" : ""}</span>
            </div>
          </div>
          <div className="space-y-2 text-sm">
            <div className="flex justify-between">
              <span className="text-content-muted">Badges</span>
              <span className="font-medium text-content-primary">{profile.badgeCount}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-content-muted">Corridas (30d)</span>
              <span className="font-medium text-content-primary">{profile.recentSessions}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-content-muted">Distância (30d)</span>
              <span className="font-medium text-content-primary">{formatKm(profile.totalDistance)} km</span>
            </div>
          </div>
        </div>
      </DashboardCard>
    </div>
  );
}
