/**
 * build-registry.ts
 *
 * Lê todos os findings em docs/audit/findings/*.md e gera:
 *   - docs/audit/registry.json   (fonte machine-readable para CI/dashboards)
 *   - docs/audit/FINDINGS.md     (tabela-índice ordenada)
 *   - docs/audit/SCORECARD.md    (burn-down por onda/lente/severidade)
 *
 * Uso:
 *   npx tsx tools/audit/build-registry.ts
 *
 * Modo verificação (não escreve, retorna exit code != 0 se houver drift):
 *   npx tsx tools/audit/build-registry.ts --check
 */

import { readdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { join, resolve, basename } from "node:path";
import yaml from "js-yaml";

const ROOT = resolve(__dirname, "..", "..");
const FINDINGS_DIR = join(ROOT, "docs", "audit", "findings");
const OUT_REGISTRY = join(ROOT, "docs", "audit", "registry.json");
const OUT_FINDINGS = join(ROOT, "docs", "audit", "FINDINGS.md");
const OUT_SCORECARD = join(ROOT, "docs", "audit", "SCORECARD.md");

const LENS_NAMES: Record<number, string> = {
  1: "CISO", 2: "CTO", 3: "CFO", 4: "CLO", 5: "CPO",
  6: "COO", 7: "CXO", 8: "CDO", 9: "CRO", 10: "CSO",
  11: "Supply Chain", 12: "Cron/Scheduler", 13: "Middleware", 14: "Contracts",
  15: "CMO", 16: "CAO", 17: "VP Eng", 18: "Principal Eng", 19: "DBA", 20: "SRE",
  21: "Atleta Pro", 22: "Atleta Amador", 23: "Treinador",
};

const SEVERITY_EMOJI: Record<string, string> = {
  critical: "🔴", high: "🟠", medium: "🟡", safe: "🟢", na: "⚪",
};

const STATUS_EMOJI: Record<string, string> = {
  "fix-pending": "⏳", "in-progress": "🚧", "fixed": "✅",
  "wont-fix": "🚫", "deferred": "⏭️", "duplicate": "🔁", "not-reproducible": "❓",
};

type Finding = {
  id: string;
  audit_ref: string;
  lens: number;
  title: string;
  severity: "critical" | "high" | "medium" | "safe" | "na";
  status: "fix-pending" | "in-progress" | "fixed" | "wont-fix" | "deferred" | "duplicate" | "not-reproducible";
  wave: 0 | 1 | 2 | 3;
  discovered_at: string;
  tags?: string[];
  files?: string[];
  correction_type?: string;
  test_required?: boolean;
  tests?: string[];
  linked_issues?: (string | number)[];
  linked_prs?: (string | number)[];
  owner?: string;
  runbook?: string | null;
  effort_points?: number;
  blocked_by?: string[];
  duplicate_of?: string | null;
  deferred_to_wave?: number | null;
  note?: string | null;
  _file: string;
};

function parseFrontmatter(raw: string, file: string): Finding {
  const match = raw.match(/^---\n([\s\S]*?)\n---\n/);
  if (!match) {
    throw new Error(`[${file}] frontmatter YAML não encontrado`);
  }
  const fm = yaml.load(match[1]) as Record<string, unknown>;
  if (!fm || typeof fm !== "object") {
    throw new Error(`[${file}] frontmatter inválido`);
  }

  for (const required of ["id", "audit_ref", "lens", "title", "severity", "status", "wave", "discovered_at"]) {
    if (!(required in fm)) {
      throw new Error(`[${file}] campo obrigatório ausente: ${required}`);
    }
  }

  const expectedId = basename(file).split("-").slice(0, 2).join("-");
  if (fm.id !== expectedId) {
    throw new Error(`[${file}] id '${fm.id}' não bate com nome do arquivo (esperado '${expectedId}')`);
  }

  return { ...(fm as Finding), _file: file };
}

function loadFindings(): Finding[] {
  if (!existsSync(FINDINGS_DIR)) {
    return [];
  }
  const files = readdirSync(FINDINGS_DIR)
    .filter(f => f.endsWith(".md") && !f.startsWith("_"));

  const findings: Finding[] = [];
  const seen = new Set<string>();

  for (const f of files) {
    const raw = readFileSync(join(FINDINGS_DIR, f), "utf-8");
    const finding = parseFrontmatter(raw, f);
    if (seen.has(finding.id)) {
      throw new Error(`[${f}] id duplicado: ${finding.id}`);
    }
    seen.add(finding.id);
    findings.push(finding);
  }

  findings.sort((a, b) => {
    if (a.lens !== b.lens) return a.lens - b.lens;
    return a.id.localeCompare(b.id);
  });
  return findings;
}

function buildRegistry(findings: Finding[]): string {
  const registry = {
    schema_version: 1,
    generated_at: new Date().toISOString(),
    total: findings.length,
    by_severity: countBy(findings, f => f.severity),
    by_status: countBy(findings, f => f.status),
    by_wave: countBy(findings, f => String(f.wave)),
    by_lens: countBy(findings, f => String(f.lens)),
    findings: findings.map(({ _file, ...rest }) => rest),
  };
  return JSON.stringify(registry, null, 2) + "\n";
}

function countBy<T>(arr: T[], key: (x: T) => string): Record<string, number> {
  const out: Record<string, number> = {};
  for (const x of arr) {
    const k = key(x);
    out[k] = (out[k] ?? 0) + 1;
  }
  return out;
}

function buildFindingsIndex(findings: Finding[]): string {
  const header = `# FINDINGS — Índice Geral

> **Gerado automaticamente** por \`tools/audit/build-registry.ts\`. **Não editar à mão.**
> Atualizado em ${new Date().toISOString().slice(0, 19).replace("T", " ")} UTC.
>
> Fonte: \`docs/audit/findings/*.md\` — editar lá. Rodar \`npx tsx tools/audit/build-registry.ts\` para regenerar.

Total: **${findings.length}** findings.

| Sev | Status | ID | Onda | Lente | Título | Owner |
|-----|--------|----|------|-------|--------|-------|
`;

  const rows = findings.map(f => {
    const sev = `${SEVERITY_EMOJI[f.severity] ?? "?"} ${f.severity}`;
    const status = `${STATUS_EMOJI[f.status] ?? "?"} ${f.status}`;
    const fileName = basename(f._file, ".md");
    const title = f.title.replace(/\|/g, "\\|");
    const lens = `L${String(f.lens).padStart(2, "0")} · ${LENS_NAMES[f.lens] ?? "?"}`;
    const owner = f.owner ?? "unassigned";
    return `| ${sev} | ${status} | [${f.id}](./findings/${fileName}.md) | ${f.wave} | ${lens} | ${title} | ${owner} |`;
  });

  return header + rows.join("\n") + "\n";
}

function buildScorecard(findings: Finding[]): string {
  const total = findings.length;
  const fixed = findings.filter(f => f.status === "fixed").length;
  const inProgress = findings.filter(f => f.status === "in-progress").length;
  const pending = findings.filter(f => f.status === "fix-pending").length;
  const deferred = findings.filter(f => f.status === "deferred").length;
  const wontFix = findings.filter(f => f.status === "wont-fix").length;

  const crit = findings.filter(f => f.severity === "critical");
  const critFixed = crit.filter(f => f.status === "fixed").length;
  const high = findings.filter(f => f.severity === "high");
  const highFixed = high.filter(f => f.status === "fixed").length;
  const med = findings.filter(f => f.severity === "medium");
  const medFixed = med.filter(f => f.status === "fixed").length;

  const pct = (n: number, d: number) => d === 0 ? "—" : `${((n / d) * 100).toFixed(1)}%`;
  const bar = (n: number, d: number, width = 20) => {
    if (d === 0) return "░".repeat(width);
    const filled = Math.round((n / d) * width);
    return "█".repeat(filled) + "░".repeat(width - filled);
  };

  const byWave = [0, 1, 2, 3].map(w => {
    const items = findings.filter(f => f.wave === w);
    const f = items.filter(x => x.status === "fixed").length;
    return { wave: w, total: items.length, fixed: f };
  });

  const byLens = Array.from({ length: 23 }, (_, i) => i + 1).map(l => {
    const items = findings.filter(f => f.lens === l);
    const f = items.filter(x => x.status === "fixed").length;
    const c = items.filter(x => x.severity === "critical").length;
    const cf = items.filter(x => x.severity === "critical" && x.status === "fixed").length;
    return { lens: l, name: LENS_NAMES[l], total: items.length, fixed: f, crit: c, critFixed: cf };
  }).filter(l => l.total > 0);

  let out = `# SCORECARD — Progresso da Auditoria

> **Gerado automaticamente** por \`tools/audit/build-registry.ts\`. **Não editar à mão.**
> Atualizado em ${new Date().toISOString().slice(0, 19).replace("T", " ")} UTC.

## Visão Geral

| Métrica | Valor | Progresso |
|---|---|---|
| **Total de findings** | ${total} | — |
| **✅ Corrigidos** | ${fixed} / ${total} (${pct(fixed, total)}) | \`${bar(fixed, total)}\` |
| **🚧 Em progresso** | ${inProgress} | — |
| **⏳ Pendentes** | ${pending} | — |
| **⏭️ Adiados** | ${deferred} | — |
| **🚫 Won't fix** | ${wontFix} | — |

## Por Severidade

| Severidade | Total | Corrigidos | % | Progresso |
|---|---|---|---|---|
| 🔴 Critical | ${crit.length} | ${critFixed} | ${pct(critFixed, crit.length)} | \`${bar(critFixed, crit.length)}\` |
| 🟠 High | ${high.length} | ${highFixed} | ${pct(highFixed, high.length)} | \`${bar(highFixed, high.length)}\` |
| 🟡 Medium | ${med.length} | ${medFixed} | ${pct(medFixed, med.length)} | \`${bar(medFixed, med.length)}\` |

## Por Onda

| Onda | Total | Corrigidos | % | Progresso |
|---|---|---|---|---|
${byWave.map(w => `| Onda ${w.wave} | ${w.total} | ${w.fixed} | ${pct(w.fixed, w.total)} | \`${bar(w.fixed, w.total)}\` |`).join("\n")}

## Por Lente

| # | Lente | Total | Corrig. | Críticos | Crít. corrig. | Progresso |
|---|---|---|---|---|---|---|
${byLens.map(l => `| ${l.lens} | ${l.name} | ${l.total} | ${l.fixed} | ${l.crit} | ${l.critFixed} | \`${bar(l.fixed, l.total, 10)}\` |`).join("\n")}

---

## Meta da Onda 0 (2026-04-24)

- ✅ 100% dos **critical** da Onda 0 corrigidos
- ✅ CI com \`tools/audit/verify.ts\` bloqueando PRs que marcam \`status: fixed\` sem teste de regressão
- ✅ Runbooks gerados para findings com \`runbook\` populado
`;

  return out;
}

function main() {
  const check = process.argv.includes("--check");
  const findings = loadFindings();

  const registry = buildRegistry(findings);
  const findingsMd = buildFindingsIndex(findings);
  const scorecardMd = buildScorecard(findings);

  // Strip timestamp lines para comparação estrutural (evita falso-positivo por generated_at).
  const stripTs = (s: string) => s
    .replace(/"generated_at":\s*"[^"]+"/g, '"generated_at":"<ts>"')
    .replace(/Atualizado em \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC\./g, "Atualizado em <ts>.");

  if (check) {
    let drift = false;
    for (const [path, desired] of [
      [OUT_REGISTRY, registry],
      [OUT_FINDINGS, findingsMd],
      [OUT_SCORECARD, scorecardMd],
    ] as const) {
      const current = existsSync(path) ? readFileSync(path, "utf-8") : "";
      if (stripTs(current) !== stripTs(desired)) {
        console.error(`❌ drift em ${basename(path)} — rode 'npx tsx tools/audit/build-registry.ts' e commite`);
        drift = true;
      }
    }
    if (drift) process.exit(1);
    console.log(`✅ registry consistente — ${findings.length} findings`);
    return;
  }

  writeFileSync(OUT_REGISTRY, registry);
  writeFileSync(OUT_FINDINGS, findingsMd);
  writeFileSync(OUT_SCORECARD, scorecardMd);

  console.log(`✅ ${findings.length} findings processados`);
  console.log(`   → docs/audit/registry.json`);
  console.log(`   → docs/audit/FINDINGS.md`);
  console.log(`   → docs/audit/SCORECARD.md`);
}

main();
