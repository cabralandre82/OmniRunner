import { NextRequest } from "next/server";
import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";
import { logger } from "@/lib/logger";
import {
  apiError,
  apiUnauthorized,
  apiValidationFailed,
  apiOk,
} from "@/lib/api/errors";
import {
  generatePeriodization,
  PeriodizationInputError,
} from "@/lib/periodization/generate-periodization";
import {
  ATHLETE_LEVELS,
  AthleteLevel,
  RACE_TARGETS,
  RaceTarget,
} from "@/lib/periodization/types";

/**
 * POST /api/training-plan/wizard — L23-06 periodization preview.
 *
 * Coach supplies `{ raceTarget, totalWeeks, athleteLevel }` and
 * receives a ready-to-materialise {@link PeriodizationPlan} that
 * already contains base → build → peak → taper blocks whose
 * weeklyVolumeKm is tuned to the athlete's level. The coach then
 * edits blocks (not individual workouts) before the portal
 * persists them to `training_plan_weeks` — the insight the finding
 * identified as "escala".
 *
 * Security posture (see docs/runbooks/PERIODIZATION_WIZARD_RUNBOOK.md):
 *
 * - Auth-required: the generator is deterministic and carries no
 *   user data, but exposing it to anon would let adversaries
 *   enumerate/scrape the template without signal — also cheap DoS
 *   via large totalWeeks. We gate on `supabase.auth.getUser()`.
 * - Input is validated defensively (enum + range) before it hits
 *   the generator; any `PeriodizationInputError` surfaces as 422,
 *   never as 500.
 * - This endpoint is pure preview: it never writes. The coach
 *   explicitly applies the plan via the existing
 *   `/api/training-plan/[planId]/weeks` wiring.
 */
function createClient() {
  const cookieStore = cookies();
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    { cookies: { getAll: () => cookieStore.getAll(), setAll: () => {} } },
  );
}

interface WizardBody {
  raceTarget?: string;
  totalWeeks?: number;
  athleteLevel?: string;
}

export async function POST(req: NextRequest) {
  try {
    const supabase = createClient();
    const {
      data: { user },
      error: authErr,
    } = await supabase.auth.getUser();
    if (authErr || !user) return apiUnauthorized(req);

    let body: WizardBody;
    try {
      body = (await req.json()) as WizardBody;
    } catch {
      return apiValidationFailed(req, "Body must be JSON.");
    }

    const raceTarget = body.raceTarget as RaceTarget | undefined;
    const athleteLevel = body.athleteLevel as AthleteLevel | undefined;
    const totalWeeks = body.totalWeeks;

    if (!raceTarget || !RACE_TARGETS.includes(raceTarget)) {
      return apiValidationFailed(
        req,
        `raceTarget must be one of ${RACE_TARGETS.join(", ")}`,
      );
    }
    if (!athleteLevel || !ATHLETE_LEVELS.includes(athleteLevel)) {
      return apiValidationFailed(
        req,
        `athleteLevel must be one of ${ATHLETE_LEVELS.join(", ")}`,
      );
    }
    if (typeof totalWeeks !== "number" || !Number.isInteger(totalWeeks)) {
      return apiValidationFailed(req, "totalWeeks must be an integer.");
    }

    try {
      const plan = generatePeriodization({
        raceTarget,
        totalWeeks,
        athleteLevel,
      });
      return apiOk({ plan });
    } catch (err) {
      if (err instanceof PeriodizationInputError) {
        return apiValidationFailed(req, err.message);
      }
      throw err;
    }
  } catch (err) {
    logger.error("POST /api/training-plan/wizard", err);
    return apiError(req, "INTERNAL_ERROR", "unexpected error", 500);
  }
}
