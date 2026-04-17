/**
 * triage.ts
 *
 * Triage heurístico dos findings 🔴 critical para distribuir entre Onda 0 e Onda 1.
 *
 * Modelo de score:
 *   priority = exploitability × blast_radius × irreversibility    (1 a 125)
 *
 * - Exploitability (1-5): quão fácil explorar
 *     5 = rota pública / qualquer autenticado
 *     4 = admin_master comprometido ou com acesso legítimo mal usado
 *     3 = múltiplos passos ou coordenação externa
 *     2 = requer acesso interno (CI/DB)
 *     1 = teórico / precisa cadeia complexa
 *
 * - Blast radius (1-5): quantos afetados
 *     5 = todos os tenants/usuários
 *     4 = todos de 1 tenant ou muitos usuários
 *     3 = 1 tenant ou grupo isolado
 *     2 = 1 usuário
 *     1 = operacional, sem usuário direto
 *
 * - Irreversibility (1-5): dano é recuperável?
 *     5 = perda financeira direta irrecuperável (dinheiro → atacante)
 *     4 = vazamento PII / LGPD Art. 48
 *     3 = corrupção de dados exigindo reconciliação manual
 *     2 = downtime / DoS
 *     1 = UX degradado
 *
 * Cutoff proposto: priority >= 45 → Onda 0, senão → Onda 1.
 *
 * Uso:
 *   npx tsx tools/audit/triage.ts            # mostra ranking
 *   npx tsx tools/audit/triage.ts --apply    # aplica wave changes + escreve TRIAGE.md
 */

import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import yaml from "js-yaml";

const ROOT = resolve(__dirname, "..", "..");
const FINDINGS_DIR = join(ROOT, "docs", "audit", "findings");
const TRIAGE_MD = join(ROOT, "docs", "audit", "TRIAGE.md");

const LENS_NAMES: Record<number, string> = {
  1: "CISO", 2: "CTO", 3: "CFO", 4: "CLO", 5: "CPO",
  6: "COO", 7: "CXO", 8: "CDO", 9: "CRO", 10: "CSO",
  11: "Supply Chain", 12: "Cron", 13: "Middleware", 14: "Contracts",
  15: "CMO", 16: "CAO", 17: "VP Eng", 18: "Principal", 19: "DBA", 20: "SRE",
  21: "Atleta Pro", 22: "Atleta Amador", 23: "Treinador",
};

type Finding = {
  file: string;
  id: string;
  title: string;
  lens: number;
  severity: string;
  tags: string[];
  currentWave: number;
  body: string;
  frontmatterRaw: string;
  bodyRaw: string;
  fullRaw: string;
};

function loadCriticals(): Finding[] {
  const files = readdirSync(FINDINGS_DIR)
    .filter(f => f.endsWith(".md") && !f.startsWith("_"));

  const out: Finding[] = [];
  for (const f of files) {
    const raw = readFileSync(join(FINDINGS_DIR, f), "utf-8");
    const m = raw.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
    if (!m) continue;
    const fm = yaml.load(m[1]) as any;
    if (fm.severity !== "critical") continue;
    out.push({
      file: f,
      id: fm.id,
      title: fm.title,
      lens: fm.lens,
      severity: fm.severity,
      tags: fm.tags ?? [],
      currentWave: fm.wave,
      body: m[2],
      frontmatterRaw: m[1],
      bodyRaw: m[2],
      fullRaw: raw,
    });
  }
  return out;
}

function scoreExploitability(f: Finding): { score: number; reason: string } {
  const body = f.body.toLowerCase();
  const title = f.title.toLowerCase();
  const text = body + " " + title;

  // 5 — rota pública ou qualquer autenticado
  if (/rota pública|sem auth|unauthenticated|anonymous|public|\/challenge|\/invite|webhook/i.test(text)
      && !/admin.?master|platform.?admin|coach|staff/i.test(text)) {
    return { score: 5, reason: "exploitável por qualquer requester não autenticado ou autenticado básico" };
  }
  if (/qualquer autenticado|atleta autenticado|usuário autenticado|any authenticated/i.test(text)) {
    return { score: 5, reason: "qualquer usuário autenticado pode explorar" };
  }

  // 4 — admin_master ou coach (roles com legítimo acesso, mas mal usado)
  if (/admin.?master|malicioso|comprometido/i.test(text)) {
    return { score: 4, reason: "admin_master comprometido/malicioso" };
  }

  // 3 — múltiplos passos
  if (/race condition|concorrência|concorrente|replay|partial.?failure|CSRF|MITM/i.test(text)) {
    return { score: 3, reason: "requer race/replay/MITM" };
  }

  // 2 — acesso interno (CI/DB)
  if (/funcionário|insider|supabase dashboard|CI|SQL direct|acesso DB|internal/i.test(text)) {
    return { score: 2, reason: "requer acesso interno (DB/CI)" };
  }

  // 1 — teórico ou migration drift (só dispara em cenários específicos)
  if (/fresh install|migration drift|reprovisão|disaster recovery|manual SQL/i.test(text)) {
    return { score: 1, reason: "teórico / ativa em cenários específicos (migration replay, DR)" };
  }

  return { score: 3, reason: "default (requer autenticação ou passo coordenado)" };
}

function scoreBlastRadius(f: Finding): { score: number; reason: string } {
  const body = f.body.toLowerCase();
  const title = f.title.toLowerCase();
  const text = body + " " + title;

  if (/todos os tenants|todas as assessorias|all tenants|plataforma|toda a plataforma/i.test(text)) {
    return { score: 5, reason: "afeta plataforma inteira / todos tenants" };
  }
  if (/todos os usuários|todos atletas|all users|cross.?tenant|database dump|secret vazamento/i.test(text)
      || /API.?Key|secret|credentials/i.test(text)) {
    return { score: 5, reason: "exposição cross-tenant ou secret compartilhado" };
  }
  if (f.tags.includes("finance") || /inventory|custódia|custody|wallet|ledger|clearing/i.test(text)) {
    return { score: 4, reason: "afeta todos usuários financeiros de 1+ tenants" };
  }
  if (f.tags.includes("lgpd") || /PII|dados pessoais|dados sensíveis|biométrico/i.test(text)) {
    return { score: 4, reason: "afeta dados pessoais de múltiplos usuários" };
  }
  if (/tenant|assessoria|grupo/i.test(text)) {
    return { score: 3, reason: "afeta 1 tenant / assessoria" };
  }
  if (/atleta individual|single user|user específico/i.test(text)) {
    return { score: 2, reason: "afeta usuário individual" };
  }

  return { score: 3, reason: "default (afeta subset de usuários)" };
}

function scoreIrreversibility(f: Finding): { score: number; reason: string } {
  const body = f.body.toLowerCase();
  const title = f.title.toLowerCase();
  const text = body + " " + title;

  // Guard-rails: débito técnico e gaps de processo NÃO são "stop the bleeding" mesmo
  // que a descrição mencione "plataforma" ou "todos usuários". São foundation work.
  // Detectamos via título (mais sinalizador que corpo, que cita "linha X" em refs)
  const titleLow = title;
  if (/segregação|bounded context|design pattern|não unificado|ad.?hoc|refactor|monoreposit|bundle size|code smell|\d{3,} linhas|segregar/i.test(titleLow)) {
    return { score: 2, reason: "débito técnico / refactor — foundation, não bleeding" };
  }
  if (/SLO|SLI|dashboard ausente|dashboard consolidad|monitoramento ausente|observability gap|sem alerta|sem runbook|zero runbook/i.test(titleLow)
      || /sem SLO|sem SLI/i.test(text)) {
    return { score: 2, reason: "gap de observabilidade/processo — foundation" };
  }
  if (/documenta\w+ (desatualiz|incomplet)|OpenAPI|sem docs|docs (desatualiz|incompletos)|bug bounty|disclosure policy/i.test(titleLow)) {
    return { score: 2, reason: "gap de documentação/processo — foundation" };
  }
  if (/idempotência ad.?hoc|idempotência.*não unificad|padrão não unificado/i.test(titleLow)) {
    return { score: 2, reason: "padrão de design ausente — foundation" };
  }

  if (/fraude financeira direta|saque fraudulento|withdraw.*fraudulent|payout.*attacker|dinheiro.*atacante|money.*attacker/i.test(text)) {
    return { score: 5, reason: "perda financeira direta irrecuperável" };
  }
  if (/API.?Key.*(plaintext|texto puro|unencrypted)|secret.*plain|senha texto puro|chave em texto/i.test(text)) {
    return { score: 5, reason: "secret vazado permite abuso persistente" };
  }
  if (/double.?spend|inflação monetária|emissão sem lastro|burn sem commit|commit silencioso/i.test(text)) {
    return { score: 5, reason: "inflação monetária / double-spend" };
  }
  if (/nota fiscal|receita federal|regulatório|compliance fiscal/i.test(text)) {
    return { score: 5, reason: "violação regulatória fiscal (multa por operação)" };
  }
  if (/direito ao esquecimento|LGPD.*Art\.?.?(46|48|11|8)|dados sensíveis|biométric|saúde/i.test(text)) {
    return { score: 4, reason: "exposição PII sensível / violação LGPD alta gravidade" };
  }
  if (f.tags.includes("lgpd") || /PII leak|data breach/i.test(text)) {
    return { score: 4, reason: "exposição PII / violação LGPD" };
  }
  if (/SECURITY DEFINER.*search.?path|privilege escalation|escalação de privilég|bypass.*auth/i.test(text)) {
    return { score: 4, reason: "bypass de autorização / escalada de privilégio" };
  }
  if (/reconciliação|partial.?failure|inconsistência|drift|discrepância|orphan|órfã/i.test(text)) {
    return { score: 3, reason: "corrupção de dados exigindo reconciliação manual" };
  }
  if (/DoS|downtime|indisponib|unavailable|queda|deadlock/i.test(text)) {
    return { score: 2, reason: "DoS / downtime" };
  }

  return { score: 3, reason: "default (corrupção recuperável)" };
}

type Scored = Finding & {
  expl: number; explReason: string;
  blast: number; blastReason: string;
  irrev: number; irrevReason: string;
  priority: number;
  proposedWave: number;
};

function scoreAll(findings: Finding[]): Scored[] {
  const ONDA_0_THRESHOLD = 45;

  const scored = findings.map(f => {
    const expl = scoreExploitability(f);
    const blast = scoreBlastRadius(f);
    const irrev = scoreIrreversibility(f);
    const priority = expl.score * blast.score * irrev.score;
    return {
      ...f,
      expl: expl.score, explReason: expl.reason,
      blast: blast.score, blastReason: blast.reason,
      irrev: irrev.score, irrevReason: irrev.reason,
      priority,
      proposedWave: priority >= ONDA_0_THRESHOLD ? 0 : 1,
    };
  });

  scored.sort((a, b) => b.priority - a.priority);
  return scored;
}

function buildTriageMd(scored: Scored[]): string {
  const onda0 = scored.filter(s => s.proposedWave === 0);
  const onda1 = scored.filter(s => s.proposedWave === 1);

  const lines: string[] = [];
  lines.push("# TRIAGE — Priorização dos Criticals");
  lines.push("");
  lines.push("> **Gerado por** `tools/audit/triage.ts` em " + new Date().toISOString().slice(0, 10) + ".");
  lines.push("> **Método**: score = exploitability × blast_radius × irreversibility (1 a 125).");
  lines.push("> **Cutoff**: priority ≥ 45 → Onda 0; senão → Onda 1.");
  lines.push("");
  lines.push("Ver racional completo do scoring em `tools/audit/triage.ts`.");
  lines.push("");
  lines.push("## Resumo");
  lines.push("");
  lines.push(`- Total criticals: **${scored.length}**`);
  lines.push(`- Proposto Onda 0: **${onda0.length}**`);
  lines.push(`- Proposto Onda 1: **${onda1.length}**`);
  lines.push(`- Score médio: ${(scored.reduce((s, f) => s + f.priority, 0) / scored.length).toFixed(1)}`);
  lines.push(`- Score máximo: ${scored[0]?.priority ?? 0}`);
  lines.push(`- Score mínimo: ${scored[scored.length - 1]?.priority ?? 0}`);
  lines.push("");

  lines.push("## Onda 0 — Stop the bleeding (priority ≥ 45)");
  lines.push("");
  lines.push("| # | ID | Score | Expl | Blast | Irrev | Lente | Título |");
  lines.push("|---|---|-------|------|-------|-------|-------|--------|");
  onda0.forEach((s, i) => {
    const title = s.title.slice(0, 70).replace(/\|/g, "\\|");
    lines.push(`| ${i + 1} | [${s.id}](./findings/${s.file}) | **${s.priority}** | ${s.expl} | ${s.blast} | ${s.irrev} | L${String(s.lens).padStart(2, "0")} ${LENS_NAMES[s.lens]} | ${title} |`);
  });
  lines.push("");

  lines.push("## Onda 1 — Foundation (priority < 45)");
  lines.push("");
  lines.push("| # | ID | Score | Expl | Blast | Irrev | Lente | Título |");
  lines.push("|---|---|-------|------|-------|-------|-------|--------|");
  onda1.forEach((s, i) => {
    const title = s.title.slice(0, 70).replace(/\|/g, "\\|");
    lines.push(`| ${i + 1} | [${s.id}](./findings/${s.file}) | ${s.priority} | ${s.expl} | ${s.blast} | ${s.irrev} | L${String(s.lens).padStart(2, "0")} ${LENS_NAMES[s.lens]} | ${title} |`);
  });
  lines.push("");

  lines.push("## Rationale por finding (Onda 0)");
  lines.push("");
  for (const s of onda0) {
    lines.push(`### ${s.id} — score ${s.priority}`);
    lines.push("");
    lines.push(`**Título:** ${s.title}`);
    lines.push("");
    lines.push(`- **Exploitability ${s.expl}/5**: ${s.explReason}`);
    lines.push(`- **Blast radius ${s.blast}/5**: ${s.blastReason}`);
    lines.push(`- **Irreversibility ${s.irrev}/5**: ${s.irrevReason}`);
    lines.push("");
  }

  // Seção de overrides manuais
  const overrides = scored.filter(s => /Override manual/i.test(s.frontmatterRaw));
  if (overrides.length > 0) {
    lines.push("## Overrides manuais");
    lines.push("");
    lines.push("Findings cujo `wave` foi ajustado manualmente (bypass do heurístico). A regra de proteção em `tools/audit/triage.ts` respeita esses overrides em re-execuções.");
    lines.push("");
    lines.push("| ID | Score heurístico | Wave proposto | Wave efetivo | Justificativa |");
    lines.push("|---|---|---|---|---|");
    for (const s of overrides) {
      const m = s.frontmatterRaw.match(/note:\s*"([^"]+)"/);
      const justification = m ? m[1].slice(0, 150) : "(ver note no finding)";
      lines.push(`| [${s.id}](./findings/${s.file}) | ${s.priority} | ${s.proposedWave} | **${s.currentWave}** | ${justification} |`);
    }
    lines.push("");
  }

  lines.push("## Como revisar / ajustar");
  lines.push("");
  lines.push("1. Se discordar de um score, abra o finding (`docs/audit/findings/LXX-YY-*.md`) e edite o `wave:` no frontmatter manualmente.");
  lines.push("2. Adicione justificativa no campo `note:` explicando por que o score heurístico não se aplica.");
  lines.push("3. Rode `npm run audit:build` para regenerar SCORECARD.");
  lines.push("4. Para rodar a triage novamente (se adicionar novos findings), execute `npx tsx tools/audit/triage.ts --apply`.");
  lines.push("");

  return lines.join("\n") + "\n";
}

function applyWaveChanges(scored: Scored[]): { changed: number; skipped: number } {
  let changed = 0;
  let skipped = 0;
  for (const s of scored) {
    // Proteção: respeita override manual marcado com "Override manual" no note
    if (/Override manual/i.test(s.frontmatterRaw)) {
      skipped++;
      continue;
    }
    if (s.currentWave !== s.proposedWave) {
      const newFm = s.frontmatterRaw.replace(/^wave:\s*\d+/m, `wave: ${s.proposedWave}`);
      const newBody = s.bodyRaw.replace(/\*\*Onda:\*\*\s*\d+/, `**Onda:** ${s.proposedWave}`);
      const newRaw = `---\n${newFm}\n---\n${newBody}`;
      writeFileSync(join(FINDINGS_DIR, s.file), newRaw);
      changed++;
    }
  }
  return { changed, skipped };
}

function main() {
  const apply = process.argv.includes("--apply");
  const findings = loadCriticals();
  const scored = scoreAll(findings);

  const onda0 = scored.filter(s => s.proposedWave === 0);
  const onda1 = scored.filter(s => s.proposedWave === 1);

  console.log(`\n📊 ${scored.length} criticals analisados`);
  console.log(`   Onda 0 proposta: ${onda0.length}`);
  console.log(`   Onda 1 proposta: ${onda1.length}`);
  console.log(`   Score médio: ${(scored.reduce((s, f) => s + f.priority, 0) / scored.length).toFixed(1)}\n`);

  console.log("Top 20:");
  scored.slice(0, 20).forEach((s, i) => {
    const wave = s.proposedWave === 0 ? "→0" : "→1";
    console.log(`  ${String(i + 1).padStart(2)}. [${s.id}] ${wave} score=${String(s.priority).padStart(3)} (${s.expl}×${s.blast}×${s.irrev}) ${s.title.slice(0, 60)}`);
  });

  if (apply) {
    const { changed, skipped } = applyWaveChanges(scored);
    writeFileSync(TRIAGE_MD, buildTriageMd(scored));
    console.log(`\n✅ ${changed} findings re-alocados`);
    if (skipped > 0) console.log(`⏭️  ${skipped} preservados por override manual (note: "Override manual...")`);
    console.log(`✅ TRIAGE.md gerado em docs/audit/TRIAGE.md`);
    console.log(`   Próximo passo: npm run audit:build`);
  } else {
    console.log(`\n💡 Rode com --apply para aplicar mudanças de wave e gerar TRIAGE.md`);
  }
}

main();
