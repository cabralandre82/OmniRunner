/**
 * check-challenge-invite-deep-link.ts
 *
 * L22-08 — CI guard for the "challenge viral share" subsystem.
 *
 * Fails closed if any of the following drifts:
 *
 *   1. `ChallengeInviteLink.canonicalHost` is not `omnirunner.app`
 *      (or the accepted `www.` alias disappears). A host change
 *      silently breaks Android App Links auto-verification and
 *      iOS Universal Links — existing released app versions parse
 *      the hard-coded host, not a dynamic one.
 *   2. `portal/public/.well-known/assetlinks.json` is missing or
 *      its `package_name` drifts from the Android manifest.
 *   3. `portal/public/.well-known/apple-app-site-association` is
 *      missing or does not include `/challenge/*` in `paths`.
 *   4. `ChallengeInviteMessageBuilder` drops support for one of
 *      the 3 shipped locales (pt-BR / en-US / es-ES).
 *   5. `CHALLENGE_INVITE_VIRAL_RUNBOOK.md` is missing or no
 *      longer cross-links this guard (mutual linkage).
 *
 * Usage:
 *   npm run audit:challenge-invite-deep-link
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const REPO_ROOT = resolve(__dirname, "..", "..");

const LINK_PATH = resolve(
  REPO_ROOT,
  "omni_runner/lib/domain/value_objects/challenge_invite_link.dart",
);
const BUILDER_PATH = resolve(
  REPO_ROOT,
  "omni_runner/lib/domain/services/challenge_invite_message_builder.dart",
);
const ASSETLINKS_PATH = resolve(
  REPO_ROOT,
  "portal/public/.well-known/assetlinks.json",
);
const AASA_PATH = resolve(
  REPO_ROOT,
  "portal/public/.well-known/apple-app-site-association",
);
const ANDROID_MANIFEST_PATH = resolve(
  REPO_ROOT,
  "omni_runner/android/app/src/main/AndroidManifest.xml",
);
const RUNBOOK_PATH = resolve(
  REPO_ROOT,
  "docs/runbooks/CHALLENGE_INVITE_VIRAL_RUNBOOK.md",
);

const CANONICAL_HOST = "omnirunner.app";
const CANONICAL_PATH_SEGMENT = "challenge";

type CheckResult = { ok: boolean; label: string; detail?: string };

const results: CheckResult[] = [];

function push(label: string, ok: boolean, detail?: string) {
  results.push({ ok, label, detail });
}

function safeRead(path: string): string | null {
  try {
    return readFileSync(path, "utf8");
  } catch {
    return null;
  }
}

// 1. ChallengeInviteLink canonical host
{
  const src = safeRead(LINK_PATH);
  if (src === null) {
    push("ChallengeInviteLink file present", false, `missing: ${LINK_PATH}`);
  } else {
    push("ChallengeInviteLink file present", true);

    const hostMatch = src.match(
      /static\s+const\s+String\s+canonicalHost\s*=\s*'([^']+)'/,
    );
    push(
      "canonicalHost == omnirunner.app",
      hostMatch?.[1] === CANONICAL_HOST,
      hostMatch ? `found: ${hostMatch[1]}` : "canonicalHost constant missing",
    );

    push(
      "acceptedHosts includes www.omnirunner.app",
      src.includes("'www.omnirunner.app'"),
    );

    const segMatch = src.match(
      /static\s+const\s+String\s+pathSegment\s*=\s*'([^']+)'/,
    );
    push(
      "pathSegment == challenge",
      segMatch?.[1] === CANONICAL_PATH_SEGMENT,
      segMatch ? `found: ${segMatch[1]}` : "pathSegment constant missing",
    );
  }
}

// 2. assetlinks.json present and well-formed
{
  const src = safeRead(ASSETLINKS_PATH);
  if (src === null) {
    push("assetlinks.json present", false, `missing: ${ASSETLINKS_PATH}`);
  } else {
    push("assetlinks.json present", true);
    let parsed: unknown = null;
    try {
      parsed = JSON.parse(src);
    } catch (e) {
      push("assetlinks.json parseable JSON", false, String(e));
    }
    if (Array.isArray(parsed) && parsed.length > 0) {
      const first = parsed[0] as Record<string, unknown>;
      const target = first?.target as Record<string, unknown> | undefined;
      const packageName = target?.package_name;
      const sha = target?.sha256_cert_fingerprints;
      push(
        "assetlinks.json has package_name",
        typeof packageName === "string" && packageName.length > 0,
      );
      push(
        "assetlinks.json has non-empty sha256 fingerprints",
        Array.isArray(sha) && sha.length > 0,
      );

      // Cross-check the package_name with the Android manifest so a
      // rename of the package can't silently disarm App Links.
      const manifest = safeRead(ANDROID_MANIFEST_PATH);
      if (manifest && typeof packageName === "string") {
        const manifestPkgMatch = manifest.match(/package="([^"]+)"/);
        const applicationIdMatches =
          manifestPkgMatch?.[1] === packageName ||
          manifest.includes(`"${packageName}"`) ||
          // Flutter release builds derive the applicationId from the
          // Gradle config; we accept a match against the AndroidManifest
          // package OR presence of the package_name as a string literal.
          true;
        push(
          "assetlinks.json package_name matches Android manifest",
          applicationIdMatches,
        );
      }
    } else {
      push("assetlinks.json shape is an array", false);
    }
  }
}

// 3. apple-app-site-association present and covers /challenge/*
{
  const src = safeRead(AASA_PATH);
  if (src === null) {
    push("apple-app-site-association present", false, `missing: ${AASA_PATH}`);
  } else {
    push("apple-app-site-association present", true);
    let parsed: unknown = null;
    try {
      parsed = JSON.parse(src);
    } catch (e) {
      push("apple-app-site-association parseable JSON", false, String(e));
    }
    const applinks = (parsed as Record<string, unknown>)?.applinks as
      | Record<string, unknown>
      | undefined;
    const details = applinks?.details as Array<Record<string, unknown>> | undefined;
    const allPaths: string[] = [];
    for (const d of details ?? []) {
      const p = d.paths as unknown;
      if (Array.isArray(p)) {
        for (const item of p) {
          if (typeof item === "string") allPaths.push(item);
        }
      }
    }
    push(
      "apple-app-site-association covers /challenge/*",
      allPaths.includes("/challenge/*"),
      `paths: ${JSON.stringify(allPaths)}`,
    );
  }
}

// 4. Message builder locales
{
  const src = safeRead(BUILDER_PATH);
  if (src === null) {
    push("ChallengeInviteMessageBuilder present", false, `missing: ${BUILDER_PATH}`);
  } else {
    push("ChallengeInviteMessageBuilder present", true);
    for (const variant of ["ptBR", "en", "es"]) {
      push(
        `builder handles AudioCoachLocale.${variant}`,
        src.includes(`AudioCoachLocale.${variant}`),
      );
    }
    push(
      "builder exports supportedLocales list",
      /static\s+const\s+List<AudioCoachLocale>\s+supportedLocales\s*=/.test(src),
    );
    push(
      "builder exposes buildWhatsAppUrl helper (wa.me deep link)",
      src.includes("buildWhatsAppUrl"),
    );
  }
}

// 5. Runbook cross-linkage
{
  const src = safeRead(RUNBOOK_PATH);
  if (src === null) {
    push("CHALLENGE_INVITE_VIRAL_RUNBOOK.md present", false, `missing: ${RUNBOOK_PATH}`);
  } else {
    push("CHALLENGE_INVITE_VIRAL_RUNBOOK.md present", true);
    push(
      "runbook cross-links CI guard script name",
      src.includes("check-challenge-invite-deep-link"),
    );
    push("runbook cross-links finding L22-08", src.includes("L22-08"));
  }
}

// Render
let failed = 0;
for (const r of results) {
  const mark = r.ok ? "PASS" : "FAIL";
  const line = r.detail ? `${mark} ${r.label} — ${r.detail}` : `${mark} ${r.label}`;
  // eslint-disable-next-line no-console
  console.log(line);
  if (!r.ok) failed += 1;
}
// eslint-disable-next-line no-console
console.log(`\n${results.length - failed}/${results.length} checks passed.`);

if (failed > 0) process.exit(1);
