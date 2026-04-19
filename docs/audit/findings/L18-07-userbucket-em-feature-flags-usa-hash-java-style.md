---
id: L18-07
audit_ref: "18.7"
lens: 18
title: "userBucket em feature-flags usa hash Java-style (inseguro, colisões)"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-19
tags: ["cron"]
files:
  - portal/src/lib/feature-flags.ts
  - portal/src/lib/feature-flags.test.ts
correction_type: code
test_required: true
tests:
  - portal/src/lib/feature-flags.test.ts
linked_issues: []
linked_prs:
  - "commit:34d9018"
owner: backend
runbook: docs/runbooks/FEATURE_FLAGS_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Substituído o accumulator DJB2-style por SHA-256 (`node:crypto.createHash`)
  em `userBucket()`:

      const digest = createHash("sha256").update(`${userId}:${key}`).digest();
      return digest.readUInt32BE(0) % 100;

  API permanece síncrona — o custo é alguns microssegundos por chamada
  (irrelevante perto da latência de DB). A motivação é distribuição
  estatística: a versão antiga `(hash<<5) - hash + charCodeAt(i)` produz
  buckets enviesados em inputs com prefixos longos compartilhados, o que
  é exatamente a forma de UUIDs v4 emitidos pelo `auth.users`. Para
  rollouts 50/50 o viés era invisível; para rollouts skewed (90/10,
  99/1) a distribuição podia ser visivelmente desigual.

  Side-effect documentado no runbook: trocar a hash function é uma
  re-randomização one-time de TODOS os experimentos A/B em curso —
  usuários no bucket "in" podem ir para "out" e vice-versa. Para 50/50
  é invisível; para splits skewed é o preço de ganhar buckets unbiased
  daqui pra frente.

  Cobertura: 4 novos testes em `feature-flags.test.ts` validam (a)
  determinismo + range [0,100), (b) decorrelação cruzada entre keys
  para o mesmo userId, (c) distribuição ~uniforme em 1000 UUIDs com
  rollout 10% (banda 70-130 in-bucket), e (d) que sibling UUIDs
  diferindo apenas nos últimos 4 chars produzem ≥30 buckets distintos
  em 100 amostras — eliminando o prefix-bias do hash anterior.
---
# [L18-07] userBucket em feature-flags usa hash Java-style (inseguro, colisões)
> **Lente:** 18 — Principal Eng · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— Linhas 43-51 implementam hash `(hash << 5) - hash + charCodeAt`. Não é crypto-secure nem uniform. Para split 50/50 funciona, mas para 90/10 distribuição pode ser enviesada.
## Correção proposta

— Usar `crypto.subtle.digest` (Web Crypto):

```typescript
async function userBucket(userId: string, key: string): Promise<number> {
  const data = new TextEncoder().encode(`${userId}:${key}`);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return new DataView(hash).getUint32(0) % 100;
}
```

Trade-off: assíncrono. Vale pela robustez estatística em A/B.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[18.7]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 18 — Principal Eng, item 18.7).