/**
 * generate-findings.ts
 *
 * Uso único (one-shot) para criar arquivos docs/audit/findings/LXX-YY-*.md
 * a partir dos relatórios narrativos em docs/audit/parts/*.md.
 *
 * Este script é IDEMPOTENTE: se um arquivo de finding já existe, não é sobrescrito
 * (para proteger edições manuais posteriores).
 *
 * Uso:
 *   npx tsx tools/audit/generate-findings.ts           # cria faltantes
 *   npx tsx tools/audit/generate-findings.ts --force   # sobrescreve todos
 *   npx tsx tools/audit/generate-findings.ts --dry     # mostra o que criaria
 */

import { readFileSync, writeFileSync, readdirSync, existsSync } from "node:fs";
import { join, resolve } from "node:path";

const ROOT = resolve(__dirname, "..", "..");
const PARTS_DIR = join(ROOT, "docs", "audit", "parts");
const FINDINGS_DIR = join(ROOT, "docs", "audit", "findings");

const LENS_NAMES: Record<number, string> = {
  1: "CISO", 2: "CTO", 3: "CFO", 4: "CLO", 5: "CPO",
  6: "COO", 7: "CXO", 8: "CDO", 9: "CRO", 10: "CSO",
  11: "Supply Chain", 12: "Cron/Scheduler", 13: "Middleware", 14: "Contracts",
  15: "CMO", 16: "CAO", 17: "VP Eng", 18: "Principal Eng", 19: "DBA", 20: "SRE",
  21: "Atleta Pro", 22: "Atleta Amador", 23: "Treinador",
};

type Severity = "critical" | "high" | "medium" | "safe" | "na";

function severityFromText(text: string): Severity {
  if (/CRÍTICO|CRITICO|🔴/i.test(text)) return "critical";
  if (/ALTO|🟠/i.test(text)) return "high";
  if (/MÉDIO|MEDIO|🟡/i.test(text)) return "medium";
  if (/SEGURO|🟢/i.test(text)) return "safe";
  if (/NÃO (AVALIÁVEL|AUDITADO|APLICÁVEL)|NAO (AVALIAVEL|AUDITADO|APLICAVEL)|⚪/i.test(text)) return "na";
  return "medium";
}

function waveFromSeverity(sev: Severity): 0 | 1 | 2 | 3 {
  if (sev === "critical") return 0;
  if (sev === "high") return 1;
  if (sev === "medium") return 2;
  return 3;
}

function slugify(text: string): string {
  return text
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/`/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .split("-")
    .slice(0, 8)
    .join("-")
    .slice(0, 60);
}

type ParsedFinding = {
  auditRef: string;
  lens: number;
  seq: number;
  rawTitle: string;
  title: string;
  severity: Severity;
  body: string;
};

function parsePart(content: string): ParsedFinding[] {
  const findings: ParsedFinding[] = [];
  const sections = content.split(/^### /m).slice(1);

  for (const section of sections) {
    const headerLine = section.split("\n")[0];
    const bodyRaw = section.slice(headerLine.length).trim();

    // match "[X.Y]" com possíveis emojis antes
    const m = headerLine.match(/\[(\d+)\.(\d+)\]\s*(.*)$/);
    if (!m) continue;

    const lens = parseInt(m[1], 10);
    const seq = parseInt(m[2], 10);
    const rawTitle = m[3].trim();

    let title = rawTitle
      .replace(/\*\*/g, "")
      .replace(/`/g, "")
      .replace(/\s+/g, " ")
      .trim();
    if (title.length > 120) title = title.slice(0, 117) + "...";

    let severity: Severity;
    const verdictMatch = bodyRaw.match(/Veredicto:?\*?\*?\s*(.*)/i);
    if (verdictMatch) {
      severity = severityFromText(verdictMatch[1]);
    } else {
      severity = severityFromText(headerLine);
    }

    findings.push({
      auditRef: `${lens}.${seq}`,
      lens,
      seq,
      rawTitle,
      title,
      severity,
      body: bodyRaw,
    });
  }

  return findings;
}

function extractSection(body: string, label: string): string | null {
  const regex = new RegExp(`\\*\\*${label}:?\\*\\*([\\s\\S]*?)(?=\\n\\s*-?\\s*\\*\\*[A-ZÁÉÍÓÚÃÕÇ][^*]+:?\\*\\*|\\n---|$)`, "i");
  const m = body.match(regex);
  return m ? m[1].trim().replace(/^[\s-]+/, "") : null;
}

function extractFiles(body: string): string[] {
  const files = new Set<string>();
  // Match file paths optionally suffixed with :line or :line-line
  const lineSuffix = "(?::\\d+(?:-\\d+)?)?";
  const patterns = [
    new RegExp(`(portal/src/[\\w/.\\-]+\\.(?:ts|tsx|js|jsx|sql|json))${lineSuffix}`, "g"),
    new RegExp(`(portal/e2e/[\\w/.\\-]+\\.(?:ts|spec\\.ts))${lineSuffix}`, "g"),
    new RegExp(`(supabase/(?:functions|migrations|seed)/[\\w/.\\-]+)${lineSuffix}`, "g"),
    new RegExp(`(omni_runner/lib/[\\w/.\\-]+\\.dart)${lineSuffix}`, "g"),
    new RegExp(`(omni_runner/(?:android|ios|test|integration_test)/[\\w/.\\-]+)${lineSuffix}`, "g"),
    new RegExp(`(tools/[\\w/.\\-]+\\.(?:ts|sh|sql))${lineSuffix}`, "g"),
    new RegExp(`(\\.github/[\\w/.\\-]+)${lineSuffix}`, "g"),
    new RegExp(`(docs/[\\w/.\\-]+\\.md)${lineSuffix}`, "g"),
  ];

  for (const p of patterns) {
    let m;
    while ((m = p.exec(body)) !== null) {
      const f = m[1];
      if (f.length < 160) files.add(f);
    }
  }

  return [...files].slice(0, 10);
}

function extractTags(body: string, lens: number): string[] {
  const tags = new Set<string>();
  const patterns: [RegExp, string][] = [
    [/LGPD|privacidade|privacy|consent/i, "lgpd"],
    [/custody|custódia|clearing|wallet|coin_ledger|coins|financeir/i, "finance"],
    [/anti.?cheat|fraud|fraude/i, "anti-cheat"],
    [/idempoten/i, "idempotency"],
    [/atomic|transação|transaction|race.?condition/i, "atomicity"],
    [/RLS|row.level.security|policy/i, "rls"],
    [/webhook|HMAC|signature/i, "webhook"],
    [/rate.?limit/i, "rate-limit"],
    [/CSP|XSS|CSRF|header/i, "security-headers"],
    [/GPS|geoloc|geolocator/i, "gps"],
    [/Strava|TrainingPeaks|OAuth/i, "integration"],
    [/Flutter|Dart|Android|iOS|mobile|app/i, "mobile"],
    [/Next\.?js|portal|middleware/i, "portal"],
    [/Edge Function|deno|supabase\/functions/i, "edge-function"],
    [/migration|CHECK|CREATE TABLE|ALTER/i, "migration"],
    [/cron|pg_cron|scheduled/i, "cron"],
    [/Sentry|observab|logging|metric/i, "observability"],
    [/accessibility|WCAG|a11y|acessibil/i, "a11y"],
    [/onboarding|UX/i, "ux"],
    [/SEO|Open.Graph|deep.link/i, "seo"],
    [/index|query.plan|N\+1|performance/i, "performance"],
    [/teste|test|coverage/i, "testing"],
    [/backup|DR|disaster/i, "reliability"],
  ];

  for (const [re, tag] of patterns) {
    if (re.test(body)) tags.add(tag);
  }

  if (lens >= 21 && lens <= 23) tags.add("personas");
  if (lens === 21) tags.add("athlete-pro");
  if (lens === 22) tags.add("athlete-amateur");
  if (lens === 23) tags.add("coach");

  return [...tags].slice(0, 6);
}

function correctionTypeFromBody(body: string, files: string[]): string {
  if (files.some(f => f.startsWith("supabase/migrations/"))) return "migration";
  if (/\.github\/workflows|CI|pipeline/i.test(body)) return "process";
  if (/runbook|alerta|observab|SLO/i.test(body)) return "process";
  if (/documenta|docs\/|README/i.test(body)) return "docs";
  if (/teste|spec\.|test\.ts/i.test(body) && files.every(f => /\.test\.|\.spec\./.test(f))) return "test";
  if (/env|config|next\.config|gradle/i.test(body)) return "config";
  return "code";
}

function buildMarkdown(f: ParsedFinding): string {
  const id = `L${String(f.lens).padStart(2, "0")}-${String(f.seq).padStart(2, "0")}`;
  const wave = waveFromSeverity(f.severity);
  const files = extractFiles(f.body);
  const tags = extractTags(f.body, f.lens);
  const correctionType = correctionTypeFromBody(f.body, files);
  const testRequired = f.severity === "critical" || f.severity === "high";

  const severityEmoji = { critical: "🔴", high: "🟠", medium: "🟡", safe: "🟢", na: "⚪" }[f.severity];
  const severityLabel = { critical: "Critical", high: "High", medium: "Medium", safe: "Safe", na: "N/A" }[f.severity];

  const achado = extractSection(f.body, "Achado") ?? "";
  const risco = extractSection(f.body, "Risco") ?? extractSection(f.body, "Impacto") ?? "";
  const correcao = extractSection(f.body, "Correção") ?? extractSection(f.body, "Correcao") ?? "";
  const teste = extractSection(f.body, "Teste de regressão proposto")
    ?? extractSection(f.body, "Teste proposto")
    ?? extractSection(f.body, "Teste");
  const camada = extractSection(f.body, "Camada") ?? "—";
  const personas = extractSection(f.body, "Persona principal impactada") ?? extractSection(f.body, "Persona") ?? "—";

  const frontmatter = [
    "---",
    `id: ${id}`,
    `audit_ref: "${f.auditRef}"`,
    `lens: ${f.lens}`,
    `title: ${JSON.stringify(f.title)}`,
    `severity: ${f.severity}`,
    `status: ${f.severity === "safe" ? "fixed" : "fix-pending"}`,
    `wave: ${wave}`,
    `discovered_at: 2026-04-17`,
    tags.length > 0 ? `tags: [${tags.map(t => JSON.stringify(t)).join(", ")}]` : `tags: []`,
    files.length > 0
      ? `files:\n${files.map(f => `  - ${f}`).join("\n")}`
      : `files: []`,
    `correction_type: ${correctionType}`,
    `test_required: ${testRequired}`,
    `tests: []`,
    `linked_issues: []`,
    `linked_prs: []`,
    `owner: unassigned`,
    `runbook: null`,
    `effort_points: ${f.severity === "critical" ? 5 : f.severity === "high" ? 3 : 2}`,
    `blocked_by: []`,
    `duplicate_of: null`,
    `deferred_to_wave: null`,
    `note: null`,
    "---",
    "",
  ].join("\n");

  const bodyMd = [
    `# [${id}] ${f.title}`,
    "",
    `> **Lente:** ${f.lens} — ${LENS_NAMES[f.lens]} · **Severidade:** ${severityEmoji} ${severityLabel} · **Onda:** ${wave} · **Status:** ${f.severity === "safe" ? "fixed" : "fix-pending"}`,
    "",
    `**Camada:** ${camada.replace(/\n/g, " ")}`,
    "",
    `**Personas impactadas:** ${personas.replace(/\n/g, " ")}`,
    "",
    "## Achado",
    "",
    achado || "_(sem descrição detalhada — ver relatório original em `docs/audit/parts/`)_",
    "",
    risco ? `## Risco / Impacto\n\n${risco}\n` : "",
    correcao ? `## Correção proposta\n\n${correcao}\n` : "",
    teste ? `## Teste de regressão\n\n${teste}\n` : "",
    "## Referência narrativa",
    "",
    `Contexto completo e motivação detalhada em [\`docs/audit/parts/\`](../parts/) — buscar pelo anchor \`[${f.auditRef}]\`.`,
    "",
    "## Histórico",
    "",
    `- \`2026-04-17\` — Descoberto na auditoria inicial (Lente ${f.lens} — ${LENS_NAMES[f.lens]}, item ${f.auditRef}).`,
    "",
  ].filter(Boolean).join("\n");

  return frontmatter + bodyMd;
}

function main() {
  const args = process.argv.slice(2);
  const force = args.includes("--force");
  const dry = args.includes("--dry");

  const partFiles = readdirSync(PARTS_DIR)
    .filter(f => /^\d+.*\.md$/.test(f))
    .sort();

  let created = 0;
  let skipped = 0;
  let bySeverity: Record<Severity, number> = { critical: 0, high: 0, medium: 0, safe: 0, na: 0 };
  let byLens: Record<number, number> = {};

  for (const partFile of partFiles) {
    const content = readFileSync(join(PARTS_DIR, partFile), "utf-8");
    const findings = parsePart(content);

    for (const f of findings) {
      const id = `L${String(f.lens).padStart(2, "0")}-${String(f.seq).padStart(2, "0")}`;
      const filename = `${id}-${slugify(f.title)}.md`;
      const fullPath = join(FINDINGS_DIR, filename);

      bySeverity[f.severity]++;
      byLens[f.lens] = (byLens[f.lens] ?? 0) + 1;

      const existing = readdirSync(FINDINGS_DIR).find(x => x.startsWith(`${id}-`));
      if (existing && !force) {
        skipped++;
        continue;
      }

      if (dry) {
        console.log(`[dry] would write ${filename} (${f.severity}) — ${f.title.slice(0, 60)}`);
        created++;
        continue;
      }

      if (existing && force) {
        const existingPath = join(FINDINGS_DIR, existing);
        if (existing !== filename) {
          require("node:fs").unlinkSync(existingPath);
        }
      }

      writeFileSync(fullPath, buildMarkdown(f));
      created++;
    }
  }

  console.log(`\n✅ ${created} findings ${dry ? "would-be " : ""}criados, ${skipped} preservados`);
  console.log(`\nPor severidade:`);
  for (const [s, n] of Object.entries(bySeverity)) {
    if (n > 0) console.log(`  ${s.padEnd(10)} ${n}`);
  }
  console.log(`\nPor lente:`);
  for (const [l, n] of Object.entries(byLens).sort((a, b) => +a[0] - +b[0])) {
    console.log(`  L${String(l).padStart(2, "0")} ${LENS_NAMES[+l].padEnd(20)} ${n}`);
  }
}

main();
