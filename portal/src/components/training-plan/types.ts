// Shared types for the training plan module

export type ReleaseStatus =
  | "draft"
  | "scheduled"
  | "released"
  | "in_progress"
  | "completed"
  | "cancelled"
  | "replaced"
  | "archived";

export type WorkoutType =
  | "continuous"
  | "interval"
  | "regenerative"
  | "long_run"
  | "strength"
  | "technique"
  | "test"
  | "free"
  | "race"
  | "brick";

export type CycleType =
  | "base"
  | "build"
  | "peak"
  | "recovery"
  | "test"
  | "free"
  | "taper"
  | "transition";

export interface WorkoutTemplate {
  id: string;
  name: string;
  description: string | null;
  workout_type: WorkoutType;
  estimated_distance_m: number | null;
  block_count: number;
  used_count?: number;
}

export interface WorkoutBlock {
  id: string;
  order_index: number;
  block_type: string;
  duration_seconds: number | null;
  distance_meters: number | null;
  target_pace_min_sec_per_km: number | null;
  target_pace_max_sec_per_km: number | null;
  target_hr_zone: number | null;
  rpe_target: number | null;
  repeat_count: number | null;
  notes: string | null;
}

/** Block stored inside content_snapshot.blocks — same shape, no db id */
export interface ReleaseBlock {
  order_index: number;
  block_type: "warmup" | "interval" | "recovery" | "cooldown" | "steady" | "rest" | "repeat";
  duration_seconds: number | null;
  distance_meters: number | null;
  target_pace_min_sec_per_km: number | null;
  target_pace_max_sec_per_km: number | null;
  target_hr_zone: number | null;
  target_hr_min: number | null;
  target_hr_max: number | null;
  rpe_target: number | null;
  repeat_count: number | null;
  notes: string | null;
}

export interface CompletedMetrics {
  id: string;
  actual_distance_m: number | null;
  actual_duration_s: number | null;
  actual_avg_hr: number | null;
  perceived_effort: number | null;
  finished_at: string | null;
}

export interface FeedbackSummary {
  rating: number | null;
  mood: number | null;
  how_was_it: string | null;
}

export interface WorkoutRelease {
  id: string;
  scheduled_date: string;
  workout_order: number;
  release_status: ReleaseStatus;
  workout_type: WorkoutType;
  workout_label: string | null;
  coach_notes: string | null;
  video_url: string | null;
  content_version: number;
  content_snapshot: {
    blocks: ReleaseBlock[];
    template_name?: string;
    description?: string;
  } | null;
  template: {
    id: string;
    name: string;
    description: string | null;
    /** Blocks from the original template — used to pre-populate the editor
     *  when content_snapshot.blocks is still empty. */
    coaching_workout_blocks?: ReleaseBlock[];
  } | null;
  completed: CompletedMetrics[];
  feedback: FeedbackSummary[];
}

// ── Workout Picker selection result ──────────────────────────────────────────

export type WorkoutPickResult =
  | { mode: "template"; template: WorkoutTemplate }
  | {
      mode: "descriptive";
      label: string;
      description?: string;
      workout_type: WorkoutType;
      coach_notes?: string;
      video_url?: string;
      blocks?: ReleaseBlock[];
    };

export interface PlanWeek {
  id: string;
  plan_id: string;
  week_number: number;
  starts_on: string;
  ends_on: string;
  label: string | null;
  coach_notes: string | null;
  cycle_type: CycleType;
  status: string;
  workouts: WorkoutRelease[];
}

export interface GroupMember {
  user_id: string;
  display_name: string;
  avatar_url: string | null;
}

// ── Label maps ─────────────────────────────────────────────────────────────────

export const STATUS_LABEL: Record<ReleaseStatus, string> = {
  draft:       "Rascunho",
  scheduled:   "Agendado",
  released:    "Liberado",
  in_progress: "Em andamento",
  completed:   "Concluído",
  cancelled:   "Cancelado",
  replaced:    "Substituído",
  archived:    "Arquivado",
};

export const WORKOUT_TYPE_LABEL: Record<WorkoutType, string> = {
  continuous:   "Contínuo",
  interval:     "Intervalado",
  regenerative: "Regenerativo",
  long_run:     "Longão",
  strength:     "Força",
  technique:    "Técnica",
  test:         "Teste",
  free:         "Livre",
  race:         "Competição",
  brick:        "Brick",
};

export const CYCLE_LABEL: Record<CycleType, string> = {
  base:       "Base",
  build:      "Construção",
  peak:       "Pico",
  recovery:   "Recuperação",
  test:       "Teste",
  free:       "Livre",
  taper:      "Taper",
  transition: "Transição",
};

// ── Style maps ─────────────────────────────────────────────────────────────────

export const STATUS_BG: Record<ReleaseStatus, string> = {
  draft:       "bg-surface-elevated border-border text-content-secondary",
  scheduled:   "bg-warning-soft border-warning/40 text-warning",
  released:    "bg-info-soft border-info/40 text-info",
  in_progress: "bg-brand-soft border-brand/40 text-brand",
  completed:   "bg-success-soft border-success/40 text-success",
  cancelled:   "bg-error-soft border-error/30 text-error/70 line-through",
  replaced:    "bg-surface-elevated border-border text-content-muted line-through",
  archived:    "bg-surface-elevated border-border text-content-muted",
};

export const CYCLE_BG: Record<CycleType, string> = {
  base:       "bg-blue-100 text-blue-800 dark:bg-blue-900/40 dark:text-blue-300",
  build:      "bg-orange-100 text-orange-800 dark:bg-orange-900/40 dark:text-orange-300",
  peak:       "bg-red-100 text-red-800 dark:bg-red-900/40 dark:text-red-300",
  recovery:   "bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-300",
  test:       "bg-purple-100 text-purple-800 dark:bg-purple-900/40 dark:text-purple-300",
  free:       "bg-surface-elevated text-content-secondary",
  taper:      "bg-yellow-100 text-yellow-800 dark:bg-yellow-900/40 dark:text-yellow-300",
  transition: "bg-surface-elevated text-content-muted",
};

export const WORKOUT_TYPE_COLOR: Record<WorkoutType, string> = {
  continuous:   "text-brand",
  interval:     "text-red-500",
  regenerative: "text-green-500",
  long_run:     "text-orange-500",
  strength:     "text-purple-500",
  technique:    "text-sky-500",
  test:         "text-yellow-500",
  free:         "text-content-secondary",
  race:         "text-error",
  brick:        "text-info",
};

// ── Helpers ────────────────────────────────────────────────────────────────────

export function formatDate(d: string): string {
  const [, month, day] = d.split("-");
  return `${day}/${month}`;
}

export function formatDuration(s: number): string {
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  if (h > 0) return `${h}h${m.toString().padStart(2, "0")}`;
  return `${m}min`;
}

export function formatPace(secPerKm: number): string {
  const m = Math.floor(secPerKm / 60);
  const s = secPerKm % 60;
  return `${m}:${s.toString().padStart(2, "0")}/km`;
}

export function formatDistanceM(m: number): string {
  if (m >= 1000) return `${(m / 1000).toFixed(1)} km`;
  return `${m} m`;
}

export function weekDates(startsOn: string): string[] {
  const dates: string[] = [];
  const start = new Date(startsOn + "T00:00:00");
  for (let i = 0; i < 7; i++) {
    const d = new Date(start);
    d.setDate(d.getDate() + i);
    dates.push(d.toISOString().split("T")[0]);
  }
  return dates;
}
