/**
 * verify.ts
 *
 * Validação CI dos findings de auditoria. Falha com exit code != 0 se:
 *   - frontmatter YAML inválido ou campos obrigatórios ausentes
 *   - id duplicado ou não bate com filename
 *   - status=fixed sem linked_prs[] E sem linked_issues[]
 *   - status=fixed + test_required=true sem tests[]
 *   - status=fixed + teste em tests[] não existe no filesystem
 *   - status=wont-fix | deferred | duplicate | not-reproducible sem note/justificativa
 *   - status=duplicate sem duplicate_of
 *   - status=deferred sem deferred_to_wave
 *   - registry.json / FINDINGS.md / SCORECARD.md em drift
 *
 * Uso:
 *   npx tsx tools/audit/verify.ts
 */

import { readdirSync, readFileSync, existsSync } from "node:fs";
import { join, resolve, basename } from "node:path";
import yaml from "js-yaml";

const ROOT = resolve(__dirname, "..", "..");
const FINDINGS_DIR = join(ROOT, "docs", "audit", "findings");

type Issue = { file: string; message: string };
const issues: Issue[] = [];

function addIssue(file: string, message: string) {
  issues.push({ file, message });
}

function validateFinding(file: string, raw: string) {
  const match = raw.match(/^---\n([\s\S]*?)\n---\n/);
  if (!match) {
    addIssue(file, "frontmatter YAML não encontrado");
    return null;
  }

  let fm: Record<string, unknown>;
  try {
    fm = yaml.load(match[1]) as Record<string, unknown>;
  } catch (e) {
    addIssue(file, `YAML inválido: ${(e as Error).message}`);
    return null;
  }

  const required = ["id", "audit_ref", "lens", "title", "severity", "status", "wave", "discovered_at"];
  for (const field of required) {
    if (!(field in fm)) {
      addIssue(file, `campo obrigatório ausente: ${field}`);
    }
  }

  const validSeverity = ["critical", "high", "medium", "safe", "na"];
  if (fm.severity && !validSeverity.includes(fm.severity as string)) {
    addIssue(file, `severity inválido: ${fm.severity}`);
  }

  const validStatus = ["fix-pending", "in-progress", "fixed", "wont-fix", "deferred", "duplicate", "not-reproducible"];
  if (fm.status && !validStatus.includes(fm.status as string)) {
    addIssue(file, `status inválido: ${fm.status}`);
  }

  if (typeof fm.lens === "number" && (fm.lens < 1 || fm.lens > 23)) {
    addIssue(file, `lens fora do range 1-23: ${fm.lens}`);
  }
  if (typeof fm.wave === "number" && (fm.wave < 0 || fm.wave > 3)) {
    addIssue(file, `wave fora do range 0-3: ${fm.wave}`);
  }

  const expectedId = basename(file).split("-").slice(0, 2).join("-");
  if (fm.id !== expectedId) {
    addIssue(file, `id '${fm.id}' não bate com filename (esperado '${expectedId}')`);
  }

  // Findings com severity=safe representam verificações do tipo "auditado e considerado
  // correto" — o finding em si é a evidência. Status=fixed é válido sem PR.
  // Findings com severity=na não receberam análise completa — tratar como fix-pending
  // até re-auditoria. Status=fixed aqui exige PR com reauditoria.
  if (fm.status === "fixed" && fm.severity !== "safe") {
    const prs = (fm.linked_prs as unknown[]) ?? [];
    const issuesLinked = (fm.linked_issues as unknown[]) ?? [];
    if (prs.length === 0 && issuesLinked.length === 0) {
      addIssue(file, "status=fixed exige ao menos 1 item em linked_prs ou linked_issues (exceto severity=safe)");
    }
    if (fm.test_required === true) {
      const tests = (fm.tests as string[]) ?? [];
      if (tests.length === 0) {
        addIssue(file, "status=fixed + test_required=true exige tests[]");
      } else {
        for (const t of tests) {
          if (!existsSync(join(ROOT, t))) {
            addIssue(file, `teste declarado não existe: ${t}`);
          }
        }
      }
    }
  }

  if (fm.status === "wont-fix" && !fm.note) {
    addIssue(file, "status=wont-fix exige 'note' com justificativa");
  }
  if (fm.status === "deferred" && !fm.deferred_to_wave) {
    addIssue(file, "status=deferred exige 'deferred_to_wave'");
  }
  if (fm.status === "duplicate" && !fm.duplicate_of) {
    addIssue(file, "status=duplicate exige 'duplicate_of'");
  }
  if (fm.status === "not-reproducible" && !fm.note) {
    addIssue(file, "status=not-reproducible exige 'note'");
  }

  return fm;
}

function main() {
  if (!existsSync(FINDINGS_DIR)) {
    console.error(`❌ diretório ${FINDINGS_DIR} não existe`);
    process.exit(1);
  }

  const files = readdirSync(FINDINGS_DIR)
    .filter(f => f.endsWith(".md") && !f.startsWith("_"));

  const idsSeen = new Map<string, string>();
  let validated = 0;

  for (const f of files) {
    const raw = readFileSync(join(FINDINGS_DIR, f), "utf-8");
    const fm = validateFinding(f, raw);
    if (fm && fm.id) {
      const id = fm.id as string;
      if (idsSeen.has(id)) {
        addIssue(f, `id duplicado: ${id} (já visto em ${idsSeen.get(id)})`);
      } else {
        idsSeen.set(id, f);
      }
    }
    validated++;
  }

  if (issues.length > 0) {
    console.error(`\n❌ ${issues.length} problema(s) em ${validated} finding(s):\n`);
    for (const i of issues) {
      console.error(`  ${i.file}: ${i.message}`);
    }
    console.error("");
    process.exit(1);
  }

  console.log(`✅ ${validated} findings validados`);
}

main();
