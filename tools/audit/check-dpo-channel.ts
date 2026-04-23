/**
 * check-dpo-channel.ts
 *
 * L04-11 — CI guard for the canonical DPO + data-subject channel doc
 * (`docs/legal/DPO_AND_DATA_SUBJECT_CHANNEL.md`).
 */

import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const ROOT = resolve(__dirname, "..", "..");
const DOC = resolve(ROOT, "docs", "legal", "DPO_AND_DATA_SUBJECT_CHANNEL.md");

interface CheckResult { name: string; ok: boolean; }
const results: CheckResult[] = [];
const push = (name: string, ok: boolean) => results.push({ name, ok });

if (!existsSync(DOC)) {
  console.error(`[FAIL] doc missing at ${DOC}`);
  process.exit(1);
}
const md = readFileSync(DOC, "utf8");

push("title — DPO + data subject channel",  /Encarregado de Proteção de Dados/.test(md));
push("legal — references LGPD Art. 41",     /Art\.\s*41/.test(md));
push("legal — references LGPD Art. 18",     /Art\.\s*18/.test(md));
push("dpo — canonical email dpo@omnirunner.com.br",
  /dpo@omnirunner\.com\.br/.test(md));
push("dpo — backup email legal@omnirunner.com.br",
  /legal@omnirunner\.com\.br/.test(md));
push(
  "rights — enumerates all 9 LGPD rights",
  ["Confirmação", "Acesso", "Correção", "Anonimização", "Portabilidade",
   "Eliminação", "compartilhamento", "consentimento", "Revogação"]
    .every((kw) => md.includes(kw)),
);
push("sla — 15 dias",                        /15\s+dias/.test(md));
push("sla — 24h ack",                        /24h/.test(md));
push("anpd — recurso documentado",           /ANPD[\s\S]{0,400}canais_atendimento/.test(md));
push("page — refers to /privacy/dpo route",  /\/privacy\/dpo/.test(md));
push("page — refers to flutter feature dir", /omni_runner\/lib\/features\/privacy/.test(md));
push("crossref — links L04-01",              /L04-01/.test(md));
push("crossref — links L04-03",              /L04-03/.test(md));
push("crossref — links L04-15",              /L04-15/.test(md));
push("history — has revision table",         /Histórico de revisão/.test(md));

let failed = 0;
for (const r of results) {
  if (r.ok) console.log(`[OK]   ${r.name}`);
  else { failed += 1; console.error(`[FAIL] ${r.name}`); }
}
console.log(`\n${results.length - failed}/${results.length} dpo-channel checks passed.`);
if (failed > 0) {
  console.error("\nL04-11 invariants broken.");
  process.exit(1);
}
