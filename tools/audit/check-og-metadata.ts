/**
 * check-og-metadata.ts
 *
 * L15-03 — CI guard for dynamic Open Graph + Twitter metadata.
 *
 * Invariants:
 *   1. `portal/src/lib/og-metadata.ts` exports `buildOgMetadata`,
 *      `getSiteBaseUrl`, `OG_IMAGE_SIZE` (1200x630), `OG_SITE_NAME`,
 *      and `OG_IMAGE_THEMES` with challenge + invite + default.
 *   2. `buildOgMetadata` produces `openGraph.images`,
 *      `openGraph.siteName`, `openGraph.locale`, `twitter.card =
 *      summary_large_image`, `alternates.canonical`, and a
 *      deterministic dynamic OG image URL `<path>/opengraph-image`.
 *   3. Unit tests for `buildOgMetadata` exist and cover the fall-back
 *      base URL, env override, malformed env rejection, payload shape,
 *      and image URL override.
 *   4. Shareable segments that must carry dynamic OG images:
 *        - `portal/src/app/challenge/[id]/opengraph-image.tsx`
 *        - `portal/src/app/invite/[code]/opengraph-image.tsx`
 *      Each:
 *        - imports `ImageResponse` from `next/og`,
 *        - exports `size = OG_IMAGE_SIZE`,
 *        - exports `contentType = "image/png"`,
 *        - uses a palette from `OG_IMAGE_THEMES`,
 *        - references the site brand `OG_SITE_NAME`.
 *   5. Corresponding `page.tsx` files import `buildOgMetadata` and
 *      return its result from `generateMetadata`.
 *   6. Finding references the shared helper + the two OG image routes.
 *
 * Usage: npm run audit:og-metadata
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const ROOT = resolve(__dirname, "..", "..");

interface CheckResult { name: string; ok: boolean; detail?: string; }
const results: CheckResult[] = [];
const push = (name: string, ok: boolean, detail?: string) =>
  results.push({ name, ok, detail });

function safeRead(path: string, label: string): string | null {
  try { return readFileSync(path, "utf8"); }
  catch { push(label, false, `missing: ${path}`); return null; }
}

// ── 1. shared helper ────────────────────────────────────────────────────
const helperPath = resolve(ROOT, "portal/src/lib/og-metadata.ts");
const helper = safeRead(helperPath, "og-metadata helper present");
if (helper) {
  push(
    "exports buildOgMetadata",
    /export function buildOgMetadata\(/.test(helper),
  );
  push(
    "exports getSiteBaseUrl",
    /export function getSiteBaseUrl\(\)/.test(helper),
  );
  push(
    "defines OG_SITE_NAME",
    /export const OG_SITE_NAME\s*=\s*"Omni Runner"/.test(helper),
  );
  push(
    "defines 1200x630 OG_IMAGE_SIZE",
    /OG_IMAGE_WIDTH\s*=\s*1200[\s\S]{0,80}OG_IMAGE_HEIGHT\s*=\s*630/.test(
      helper,
    ),
  );
  push(
    "defines OG_IMAGE_THEMES.challenge / .invite / .default",
    /OG_IMAGE_THEMES[\s\S]{0,200}challenge:[\s\S]{0,200}invite:[\s\S]{0,200}default:/
      .test(helper),
  );
  push(
    "helper emits twitter.card=summary_large_image by default",
    /card:\s*input\.twitterCard\s*\?\?\s*"summary_large_image"/.test(helper),
  );
  push(
    "helper sets openGraph.siteName",
    /siteName:\s*OG_SITE_NAME/.test(helper),
  );
  push(
    "helper sets alternates.canonical",
    /alternates:\s*\{\s*canonical:/.test(helper),
  );
  push(
    "helper defaults locale to pt_BR",
    /OG_DEFAULT_LOCALE\s*=\s*"pt_BR"/.test(helper),
  );
  push(
    "helper derives og image URL from path",
    /\$\{url\}\/opengraph-image/.test(helper),
  );
  push(
    "helper rejects non-http env base URL",
    /\/\^https\?:\\\/\\\/\/i\.test\(envUrl\)/.test(helper) ||
      /\/\^https\?:\\\/\\\//i.test(helper),
  );
}

// ── 2. unit tests ───────────────────────────────────────────────────────
const testPath = resolve(ROOT, "portal/src/lib/og-metadata.test.ts");
const test = safeRead(testPath, "og-metadata tests present");
if (test) {
  push(
    "test: fallback base URL asserted",
    /falls back to omnirunner\.app when no env base is set/.test(test),
  );
  push(
    "test: env override asserted",
    /honours NEXT_PUBLIC_PORTAL_BASE_URL/.test(test),
  );
  push(
    "test: malformed env rejected",
    /ignores malformed base URL and falls back/.test(test),
  );
  push(
    "test: payload shape asserted",
    /emits full OG \+ Twitter payload with dynamic image URL/.test(test),
  );
  push(
    "test: image URL override asserted",
    /lets callers override image URL/.test(test),
  );
  push(
    "test: normalises missing leading slash",
    /normalises missing leading slash in path/.test(test),
  );
}

// ── 3. dynamic OG image routes ──────────────────────────────────────────
interface OgRoute {
  label: string;
  path: string;
  themeKey: string;
}
const ogRoutes: OgRoute[] = [
  {
    label: "challenge",
    path: "portal/src/app/challenge/[id]/opengraph-image.tsx",
    themeKey: "challenge",
  },
  {
    label: "invite",
    path: "portal/src/app/invite/[code]/opengraph-image.tsx",
    themeKey: "invite",
  },
];

for (const route of ogRoutes) {
  const src = safeRead(
    resolve(ROOT, route.path),
    `${route.label} opengraph-image.tsx present`,
  );
  if (!src) continue;
  push(
    `${route.label}: imports ImageResponse from next/og`,
    /import\s*\{[^}]*ImageResponse[^}]*\}\s*from\s*"next\/og"/.test(src),
  );
  push(
    `${route.label}: exports size = OG_IMAGE_SIZE`,
    /export const size\s*=\s*OG_IMAGE_SIZE/.test(src),
  );
  push(
    `${route.label}: exports contentType = image/png`,
    /export const contentType\s*=\s*"image\/png"/.test(src),
  );
  push(
    `${route.label}: uses OG_IMAGE_THEMES.${route.themeKey}`,
    new RegExp(`OG_IMAGE_THEMES\\.${route.themeKey}`).test(src),
  );
  push(
    `${route.label}: references OG_SITE_NAME`,
    /OG_SITE_NAME/.test(src),
  );
  push(
    `${route.label}: runs on edge runtime`,
    /export const runtime\s*=\s*"edge"/.test(src),
  );
}

// ── 4. page.tsx uses buildOgMetadata ────────────────────────────────────
const pages = [
  {
    label: "challenge",
    path: "portal/src/app/challenge/[id]/page.tsx",
  },
  {
    label: "invite",
    path: "portal/src/app/invite/[code]/page.tsx",
  },
];
for (const p of pages) {
  const src = safeRead(resolve(ROOT, p.path), `${p.label} page.tsx present`);
  if (!src) continue;
  push(
    `${p.label}: page imports buildOgMetadata`,
    /import\s*\{\s*buildOgMetadata\s*\}\s*from\s*"@\/lib\/og-metadata"/.test(
      src,
    ),
  );
  push(
    `${p.label}: generateMetadata returns buildOgMetadata(...)`,
    /generateMetadata[\s\S]{0,400}return buildOgMetadata\(/.test(src),
  );
}

// ── 5. finding cross-references ─────────────────────────────────────────
const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L15-03-social-sharing-sem-open-graph-dinamico.md",
);
const finding = safeRead(findingPath, "L15-03 finding present");
if (finding) {
  push(
    "finding references og-metadata helper",
    /portal\/src\/lib\/og-metadata\.ts/.test(finding),
  );
  push(
    "finding references dynamic OG image routes",
    /opengraph-image\.tsx/.test(finding),
  );
}

let failed = 0;
for (const r of results) {
  if (r.ok) console.log(`[OK]   ${r.name}`);
  else {
    failed += 1;
    console.error(`[FAIL] ${r.name}${r.detail ? ` — ${r.detail}` : ""}`);
  }
}
console.log(
  `\n${results.length - failed}/${results.length} og-metadata checks passed.`,
);
if (failed > 0) {
  console.error("\nL15-03 invariants broken.");
  process.exit(1);
}
