/**
 * L21-04 — Daily rollup + CTL / ATL / TSB timeseries.
 *
 * The performance management chart (PMC) is the classical
 * Banister impulse-response model reformulated in daily TSS
 * with two exponentially-weighted moving averages:
 *
 *   CTL_today = CTL_yesterday + (TSS_today − CTL_yesterday) / τ_CTL
 *   ATL_today = ATL_yesterday + (TSS_today − ATL_yesterday) / τ_ATL
 *   TSB_today = CTL_today − ATL_today
 *
 * The discrete-time form is equivalent to a first-order IIR
 * low-pass filter with time-constant τ. For τ_CTL = 42 this
 * gives roughly a 6-week "fitness" memory; τ_ATL = 7 gives a
 * weekly "fatigue" memory.
 *
 * The module is *pure*: you feed in a sorted list of daily
 * TSS values plus optional seed (previous CTL/ATL) and get
 * back the full series. No IO, no Date mutation, no Intl.
 */

import {
  ATL_TAU_DAYS,
  CTL_TAU_DAYS,
  type DailyLoad,
  type LoadPoint,
  type SessionSample,
  TRAINING_ZONE_BANDS,
  type TrainingZone,
} from "./types";

export interface RollupInput {
  sessions: ReadonlyArray<{
    startedAt: number;
    tss: number;
  }>;
  timezoneOffsetMinutes?: number;
}

export function rollupDailyTss(input: RollupInput): DailyLoad[] {
  const offsetMs = (input.timezoneOffsetMinutes ?? 0) * 60_000;
  const perDay = new Map<string, { sum: number; count: number }>();
  for (const session of input.sessions) {
    if (!Number.isFinite(session.startedAt) || !Number.isFinite(session.tss)) continue;
    if (session.tss <= 0) continue;
    const day = formatDayKey(session.startedAt + offsetMs);
    const bucket = perDay.get(day) ?? { sum: 0, count: 0 };
    bucket.sum += session.tss;
    bucket.count += 1;
    perDay.set(day, bucket);
  }
  const days = Array.from(perDay.keys()).sort();
  return days.map((day) => {
    const bucket = perDay.get(day)!;
    return { day, tssSum: roundDecimals(bucket.sum, 1), sessionCount: bucket.count };
  });
}

export interface RollingSeriesInput {
  from: string;
  to: string;
  dailyLoad: ReadonlyArray<DailyLoad>;
  seedCtl?: number;
  seedAtl?: number;
  ctlTauDays?: number;
  atlTauDays?: number;
}

export function buildLoadSeries(input: RollingSeriesInput): LoadPoint[] {
  const ctlTau = input.ctlTauDays ?? CTL_TAU_DAYS;
  const atlTau = input.atlTauDays ?? ATL_TAU_DAYS;
  if (ctlTau <= 0 || atlTau <= 0) {
    throw new Error("CTL and ATL time constants must be positive");
  }
  const byDay = new Map<string, number>();
  for (const entry of input.dailyLoad) byDay.set(entry.day, entry.tssSum);

  const days = enumerateDays(input.from, input.to);
  const result: LoadPoint[] = [];
  let ctl = input.seedCtl ?? 0;
  let atl = input.seedAtl ?? 0;
  for (const day of days) {
    const dailyTss = byDay.get(day) ?? 0;
    ctl = ctl + (dailyTss - ctl) / ctlTau;
    atl = atl + (dailyTss - atl) / atlTau;
    result.push({
      day,
      ctl: roundDecimals(ctl, 1),
      atl: roundDecimals(atl, 1),
      tsb: roundDecimals(ctl - atl, 1),
      dailyTss: roundDecimals(dailyTss, 1),
    });
  }
  return result;
}

export function classifyTrainingZone(tsb: number): TrainingZone {
  for (const band of TRAINING_ZONE_BANDS) {
    if (tsb >= band.tsbMin && tsb < band.tsbMax) return band.zone;
  }
  return "productive";
}

export interface RampRateInput {
  series: ReadonlyArray<LoadPoint>;
  windowDays?: number;
}

export function computeCtlRampRate(input: RampRateInput): number {
  const window = input.windowDays ?? 7;
  if (input.series.length < window + 1) return 0;
  const tail = input.series[input.series.length - 1];
  const head = input.series[input.series.length - 1 - window];
  return roundDecimals(tail.ctl - head.ctl, 1);
}

export function sessionsToSeries(
  sessions: ReadonlyArray<SessionSample & { tss: number }>,
  range: { from: string; to: string; timezoneOffsetMinutes?: number },
): LoadPoint[] {
  const daily = rollupDailyTss({
    sessions: sessions.map((s) => ({ startedAt: s.startedAt, tss: s.tss })),
    timezoneOffsetMinutes: range.timezoneOffsetMinutes,
  });
  return buildLoadSeries({ from: range.from, to: range.to, dailyLoad: daily });
}

function enumerateDays(from: string, to: string): string[] {
  const start = parseDayKey(from);
  const end = parseDayKey(to);
  if (end < start) throw new Error("'to' must be >= 'from'");
  const out: string[] = [];
  for (let cursor = start; cursor <= end; cursor += 86_400_000) {
    out.push(formatDayKey(cursor));
  }
  return out;
}

function formatDayKey(ms: number): string {
  const d = new Date(ms);
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, "0");
  const day = String(d.getUTCDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

function parseDayKey(key: string): number {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(key);
  if (!match) throw new Error(`invalid day key: ${key}`);
  return Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
}

function roundDecimals(n: number, places: number): number {
  const factor = Math.pow(10, places);
  return Math.round(n * factor) / factor;
}
