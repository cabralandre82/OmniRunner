#!/usr/bin/env -S node --experimental-strip-types
/**
 * tools/legal/check-document-hashes.ts — L09-09 drift detection
 *
 * Calcula SHA-256 dos contratos privados em `docs/legal/` e compara com o
 * valor seedado em `consent_policy_versions.document_hash` (via migration).
 *
 * Uso:
 *   npx tsx tools/legal/check-document-hashes.ts          # check (CI)
 *   npx tsx tools/legal/check-document-hashes.ts --print  # imprime hashes
 *   npx tsx tools/legal/check-document-hashes.ts --json   # output máquina
 *
 * Exit code 0 = sem drift, 1 = drift detectado (build falha).
 *
 * Política:
 *   - Os MDs são imutáveis após publicação. Qualquer edição obriga bump de
 *     versão (v1.0 → v1.1 ou v2.0) e nova migration que atualize document_hash.
 *   - Em CI, a fonte da verdade do hash esperado é o constant `EXPECTED`
 *     abaixo (espelho da migration `20260421210000_l09_09_legal_contracts_consent.sql`).
 *     Mantenha-os em lockstep — qualquer divergência também falha o check.
 */
import { createHash } from "node:crypto";
import { readFileSync, existsSync } from "node:fs";
import { resolve, join } from "node:path";

const ROOT = resolve(__dirname, "..", "..");

type Doc = {
  consentType: string;
  path: string;
  version: string;
  /**
   * SHA-256 esperado — espelho da migration. Atualizar AMBOS em lockstep
   * quando rotacionar versão (a checagem `verifyLockstepWithMigration`
   * abaixo falha o build se a migration deixar de referenciar o hash).
   */
  expectedSha256: string;
  /** Migration que primeiro registrou esse hash em consent_policy_versions */
  migrationPath: string;
};

const EXPECTED: Doc[] = [
  {
    consentType: "club_adhesion",
    path: "docs/legal/TERMO_ADESAO_ASSESSORIA.md",
    version: "1.0",
    expectedSha256:
      "1103d8ee324d5106dc28a1722037989f6c3095965a2df8f1c95a4dc12bf1a3f1",
    migrationPath:
      "supabase/migrations/20260421210000_l09_09_legal_contracts_consent.sql",
  },
  {
    consentType: "athlete_contract",
    path: "docs/legal/TERMO_ATLETA.md",
    version: "1.0",
    expectedSha256:
      "834f70fa7945f1fc6a30b10b77eeacd76216eaf05d99477f14b635df57f2f1dd",
    migrationPath:
      "supabase/migrations/20260421210000_l09_09_legal_contracts_consent.sql",
  },
];

function sha256OfFile(absPath: string): string {
  const buf = readFileSync(absPath);
  return createHash("sha256").update(buf).digest("hex");
}

type Computed = {
  doc: Doc;
  abs: string;
  exists: boolean;
  actualSha256: string | null;
  match: boolean;
};

function compute(): Computed[] {
  return EXPECTED.map((doc) => {
    const abs = join(ROOT, doc.path);
    const exists = existsSync(abs);
    const actual = exists ? sha256OfFile(abs) : null;
    return {
      doc,
      abs,
      exists,
      actualSha256: actual,
      match: actual === doc.expectedSha256,
    };
  });
}

/**
 * Lockstep check: verifica que o hash esperado também está literalmente no
 * arquivo de migration. Isso evita drift "silencioso" se alguém atualizar
 * EXPECTED sem refletir no SQL (ou vice-versa).
 *
 * Retorna lista de problemas detectados (vazia = OK).
 */
function verifyLockstepWithMigration(): string[] {
  const problems: string[] = [];
  for (const doc of EXPECTED) {
    const abs = join(ROOT, doc.migrationPath);
    if (!existsSync(abs)) {
      problems.push(
        `migration ${doc.migrationPath} não encontrada (consent_type=${doc.consentType})`,
      );
      continue;
    }
    const sql = readFileSync(abs, "utf8");
    if (!sql.includes(doc.expectedSha256)) {
      problems.push(
        `migration ${doc.migrationPath} não referencia hash ` +
          `${doc.expectedSha256} esperado para ${doc.consentType} v${doc.version}. ` +
          `Atualize EXPECTED + migration em lockstep.`,
      );
    }
  }
  return problems;
}

export { EXPECTED, sha256OfFile, compute, verifyLockstepWithMigration };
export type { Doc, Computed };

export function main(argv: string[]): number {
  const print = argv.includes("--print");
  const json = argv.includes("--json");
  const results = compute();

  if (json) {
    process.stdout.write(JSON.stringify(results, null, 2) + "\n");
    return results.every((r) => r.exists && r.match) ? 0 : 1;
  }

  if (print) {
    for (const r of results) {
      const status = !r.exists
        ? "MISSING"
        : r.match
          ? "OK"
          : "DRIFT";
      process.stdout.write(
        `${r.doc.path.padEnd(40)} v${r.doc.version}  sha256=${r.actualSha256 ?? "<missing>"}  ${status}\n`,
      );
    }
    return 0;
  }

  let failed = 0;
  for (const r of results) {
    if (!r.exists) {
      process.stderr.write(
        `[L09-09] FAIL ${r.doc.path} não existe (consent_type=${r.doc.consentType})\n`,
      );
      failed += 1;
      continue;
    }
    if (!r.match) {
      process.stderr.write(
        `[L09-09] FAIL drift detectado em ${r.doc.path} ` +
          `(consent_type=${r.doc.consentType}, versão=${r.doc.version})\n` +
          `         esperado: ${r.doc.expectedSha256}\n` +
          `         calculado: ${r.actualSha256}\n` +
          `         → o conteúdo foi alterado sem bump de versão.\n` +
          `         Ações:\n` +
          `         1. Reverter alteração se for inadvertida; OU\n` +
          `         2. Bump de versão (v→v+1) e nova migration UPDATE\n` +
          `            consent_policy_versions SET document_hash=...,\n` +
          `            current_version=..., minimum_version=...\n` +
          `         3. Atualizar EXPECTED em tools/legal/check-document-hashes.ts\n` +
          `         Detalhes: docs/runbooks/LEGAL_CONTRACTS_RUNBOOK.md\n`,
      );
      failed += 1;
    }
  }

  // Lockstep contract: hash em EXPECTED deve estar literalmente no SQL
  const lockstepProblems = verifyLockstepWithMigration();
  for (const p of lockstepProblems) {
    process.stderr.write(`[L09-09] FAIL lockstep — ${p}\n`);
    failed += 1;
  }

  if (failed === 0) {
    process.stdout.write(
      `[L09-09] OK ${results.length} contratos íntegros (sem drift; migration em lockstep).\n`,
    );
    return 0;
  }
  process.stderr.write(
    `[L09-09] ${failed} problema(s) detectado(s) — ver mensagens acima.\n`,
  );
  return 1;
}

// Só executa quando rodado direto via CLI, NÃO quando importado por um teste.
// `import.meta.url === pathToFileURL(process.argv[1]).href` é a forma canônica
// para Node ESM, mas como podemos rodar via tsx (CJS-like), usamos um guard
// equivalente baseado no nome do arquivo invocado.
const invokedPath = process.argv[1] ?? "";
if (invokedPath.endsWith("check-document-hashes.ts")
    || invokedPath.endsWith("check-document-hashes.js")) {
  const argv = process.argv.slice(2);
  process.exit(main(argv));
}
