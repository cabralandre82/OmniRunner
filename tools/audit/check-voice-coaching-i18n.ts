/**
 * check-voice-coaching-i18n.ts
 *
 * L22-06 — CI guard for the audio coach subsystem.
 *
 * Fails closed if any of the following drifts:
 *
 *   1. `AudioCoachLocale` enum is missing one of the 3 shipped
 *      locales (ptBR / en / es) or their BCP-47 language tags.
 *   2. `AudioCueFormatter` catalogue is missing coverage for one
 *      of the declared translation keys in one of the locales.
 *   3. Any of the 3 new voice triggers is missing
 *      (countdown / motivation / hydration) — these are what the
 *      finding explicitly asked for.
 *   4. The AUDIO_CUES_RUNBOOK.md is missing or does not cross-link
 *      the CI guard back (mutual linkage).
 *
 * Usage:
 *   npm run audit:voice-coaching-i18n
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const REPO_ROOT = resolve(__dirname, "..", "..");

const FORMATTER_PATH = resolve(
  REPO_ROOT,
  "omni_runner/lib/domain/services/audio_cue_formatter.dart",
);
const LOCALE_PATH = resolve(
  REPO_ROOT,
  "omni_runner/lib/domain/value_objects/audio_coach_locale.dart",
);
const RUNBOOK_PATH = resolve(REPO_ROOT, "docs/runbooks/AUDIO_CUES_RUNBOOK.md");

const REQUIRED_TRIGGERS = [
  "omni_runner/lib/domain/usecases/countdown_voice_trigger.dart",
  "omni_runner/lib/domain/usecases/motivation_voice_trigger.dart",
  "omni_runner/lib/domain/usecases/hydration_voice_trigger.dart",
];

const REQUIRED_LOCALES: Array<{ variant: string; tag: string }> = [
  { variant: "ptBR", tag: "pt-BR" },
  { variant: "en", tag: "en-US" },
  { variant: "es", tag: "es-ES" },
];

type CheckResult = { ok: boolean; label: string; detail?: string };

const results: CheckResult[] = [];

function record(ok: boolean, label: string, detail?: string): void {
  results.push({ ok, label, detail });
}

function readOrNull(path: string): string | null {
  try {
    return readFileSync(path, "utf8");
  } catch {
    return null;
  }
}

function checkLocaleEnum(): void {
  const src = readOrNull(LOCALE_PATH);
  if (src === null) {
    record(false, "locale: file present", LOCALE_PATH);
    return;
  }
  record(true, "locale: file present");

  for (const { variant, tag } of REQUIRED_LOCALES) {
    const variantRe = new RegExp(`\\b${variant}\\s*\\(\\s*'${tag}'\\s*\\)`);
    const ok = variantRe.test(src);
    record(
      ok,
      `locale: ${variant} declared with tag '${tag}'`,
      ok ? undefined : `expected pattern ${variantRe} in audio_coach_locale.dart`,
    );
  }

  const hasFromTag = /static AudioCoachLocale fromTag/.test(src);
  record(
    hasFromTag,
    "locale: AudioCoachLocale.fromTag() factory declared",
    hasFromTag ? undefined : "missing fromTag(String? raw) resolver",
  );
}

function checkFormatter(): void {
  const src = readOrNull(FORMATTER_PATH);
  if (src === null) {
    record(false, "formatter: file present", FORMATTER_PATH);
    return;
  }
  record(true, "formatter: file present");

  const keysBlock = src.match(
    /static const Set<String> translationKeys\s*=\s*\{([\s\S]*?)\};/,
  );
  if (!keysBlock) {
    record(false, "formatter: translationKeys Set declared");
    return;
  }
  record(true, "formatter: translationKeys Set declared");

  const constKeys = Array.from(
    src.matchAll(/static const\s+_([A-Za-z0-9]+)Key\s*=\s*'([^']+)'/g),
  ).map((m) => ({ symbol: `_${m[1]}Key`, value: m[2] }));
  if (constKeys.length === 0) {
    record(false, "formatter: translation keys declared as String constants");
    return;
  }
  record(true, `formatter: ${constKeys.length} translation keys declared`);

  for (const locale of REQUIRED_LOCALES) {
    const localeBlockRe = new RegExp(
      `AudioCoachLocale\\.${locale.variant}:\\s*\\{([\\s\\S]*?)\\},`,
    );
    const m = localeBlockRe.exec(src);
    if (!m) {
      record(false, `formatter: catalogue block for ${locale.variant}`);
      continue;
    }
    const block = m[1];
    let allOk = true;
    const missing: string[] = [];
    for (const key of constKeys) {
      const present = new RegExp(`${key.symbol}\\s*:\\s*'[^']+'`).test(block);
      if (!present) {
        allOk = false;
        missing.push(key.value);
      }
    }
    record(
      allOk,
      `formatter: ${locale.variant} catalogue covers all keys`,
      allOk ? undefined : `missing: ${missing.join(", ")}`,
    );

    const motivationalRe = new RegExp(
      `AudioCoachLocale\\.${locale.variant}:\\s*\\[([\\s\\S]*?)\\],`,
      "g",
    );
    let hasNonEmptyPool = false;
    let match: RegExpExecArray | null;
    while ((match = motivationalRe.exec(src)) !== null) {
      const inner = match[1].trim();
      if (inner.length > 2 && inner.includes("'")) {
        hasNonEmptyPool = true;
        break;
      }
    }
    record(
      hasNonEmptyPool,
      `formatter: ${locale.variant} motivational pool non-empty`,
      hasNonEmptyPool
        ? undefined
        : `locale ${locale.variant} pool is empty or missing in _motivationalPhrases`,
    );
  }
}

function checkTriggers(): void {
  for (const rel of REQUIRED_TRIGGERS) {
    const abs = resolve(REPO_ROOT, rel);
    const src = readOrNull(abs);
    if (src === null) {
      record(false, `trigger: ${rel} present`);
      continue;
    }
    const looksLikeTrigger =
      /class\s+[A-Z]\w+VoiceTrigger/.test(src) &&
      /AudioEventEntity\?\s+evaluate\s*\(/.test(src);
    record(
      looksLikeTrigger,
      `trigger: ${rel} exports *VoiceTrigger with evaluate()`,
      looksLikeTrigger
        ? undefined
        : "missing class <Name>VoiceTrigger or AudioEventEntity? evaluate(...)",
    );
  }
}

function checkRunbook(): void {
  const src = readOrNull(RUNBOOK_PATH);
  if (src === null) {
    record(false, "runbook: AUDIO_CUES_RUNBOOK.md present", RUNBOOK_PATH);
    return;
  }
  record(true, "runbook: AUDIO_CUES_RUNBOOK.md present");

  const mentionsGuard = /audit:voice-coaching-i18n|check-voice-coaching-i18n/.test(src);
  record(
    mentionsGuard,
    "runbook: cross-links the audit:voice-coaching-i18n guard",
    mentionsGuard
      ? undefined
      : "runbook must cite audit:voice-coaching-i18n so guard failures have a playbook",
  );

  const mentionsL22_06 = /L22-06/.test(src);
  record(
    mentionsL22_06,
    "runbook: references finding L22-06",
    mentionsL22_06 ? undefined : "runbook must cite L22-06 in the heading/intro",
  );
}

function main(): number {
  console.log("L22-06: checking voice coaching subsystem…");
  checkLocaleEnum();
  checkFormatter();
  checkTriggers();
  checkRunbook();

  let fails = 0;
  for (const r of results) {
    const mark = r.ok ? "OK" : "FAIL";
    console.log(`  [${mark}] ${r.label}${r.detail ? ` — ${r.detail}` : ""}`);
    if (!r.ok) fails++;
  }

  if (fails > 0) {
    console.error(
      `\n${fails} check(s) failed. See docs/runbooks/AUDIO_CUES_RUNBOOK.md for remediation.`,
    );
    return 1;
  }
  console.log("\nOK — L22-06 voice coaching invariants hold.");
  return 0;
}

process.exit(main());
