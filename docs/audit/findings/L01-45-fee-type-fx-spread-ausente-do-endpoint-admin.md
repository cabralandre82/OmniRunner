---
id: L01-45
audit_ref: "1.45"
lens: 1
title: "fee_type — 'fx_spread' ausente do endpoint admin"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["finance", "portal", "admin", "openapi", "contract-lock"]
files:
  - portal/src/lib/platform-fee-types.ts
  - portal/src/app/api/platform/fees/route.ts
  - portal/src/app/platform/fees/page.tsx
  - portal/public/openapi.json
correction_type: code
test_required: true
tests:
  - portal/src/lib/platform-fee-types.test.ts
  - portal/src/app/api/platform/fees/route.test.ts
linked_issues: []
linked_prs:
  - dee4da3
owner: backend-platform
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Consolida a lista canônica de `fee_type` em um único módulo TypeScript
  (`portal/src/lib/platform-fee-types.ts`) e força lockstep entre as cinco
  superfícies que historicamente derivaram independentemente.

  ## Context — por que isso era high-severity

  O bug imediato (Zod enum sem `'fx_spread'`) tinha sido corrigido como
  side-effect de L01-44 em 2026-04-17 (commit anterior), mas a finding ficou
  pendente porque a causa-raiz NÃO foi atacada: ainda existiam cinco fontes
  paralelas de verdade para o mesmo conjunto de slugs, sem CI cruzado:

    1. `platform_fee_config.fee_type` CHECK (Postgres)
    2. `platform_revenue.fee_type` CHECK (Postgres)
    3. Zod enum em `POST /api/platform/fees` (TS)
    4. `FEE_LABELS` keys em `/platform/fees/page.tsx` (TS)
    5. `enum` em `public/openapi.json` (JSON)

  Drift histórico documentado:

    • L01-44 (2026-04-17) — `fx_spread` foi inserido por migration
      20260228170000 ANTES do CHECK ser ampliado; fresh installs falharam
      por meses.
    • L01-45 (2026-04-13, BRL crisis) — Zod enum rejeitou
      `fee_type='fx_spread'` mesmo após L01-44 fixar o CHECK; admins não
      conseguiram ajustar o spread cambial pela UI durante a crise. SRE
      teve que rodar SQL direto em prod, à 1h da manhã.
    • OpenAPI (`public/openapi.json`) ainda listava apenas
      `["clearing","swap","maintenance","billing_split"]` — 8 dias após
      L01-44 a documentação pública contradizia o backend. Clientes B2B
      gerando SDK a partir do OpenAPI não tinham `fx_spread` como opção
      válida.

  ## Solução implementada

  ### 1. Constante canônica única (`lib/platform-fee-types.ts`)

  Novo módulo expõe:

    • `PLATFORM_FEE_TYPES` — array `as const` ordenado para renderização
      (clearing, swap, fx_spread, billing_split, maintenance).
    • `PlatformFeeType` — literal-union derivada do array. NUNCA usar
      `string` para `fee_type` em assinaturas; o compilador garante o
      conjunto canônico em todo call-site.
    • `platformFeeTypeSchema` — `z.enum(PLATFORM_FEE_TYPES)` pré-construído
      para route handlers (evita perder `as const` por descuido).
    • `FEE_TYPE_LABELS` — `Record<PlatformFeeType, ...>` com label e
      descrição em pt-BR. A chave é tipada, então adicionar um slug a
      `PLATFORM_FEE_TYPES` sem o label correspondente quebra `tsc`.
    • `isPlatformFeeType()` — type guard para contextos sem Zod (queues
      internas, parsing de payloads não-tipados).

  Comentário cabeçalho documenta o procedimento de 4 passos para adicionar
  um novo `fee_type` (constante TS → label → migration CHECK + INSERT →
  OpenAPI) e referencia os post-mortems de L01-44 e L01-45.

  ### 2. Route handler (`/api/platform/fees`)

  Removido enum inline; agora importa `platformFeeTypeSchema`. Comentário
  explícito proíbe re-inline ("NEVER inline the list here again").

  ### 3. Page (`/platform/fees`)

  Removido `FEE_LABELS` local (cópia divergente); agora usa
  `FEE_TYPE_LABELS` + `isPlatformFeeType()` do módulo canônico. Linhas
  inesperadas (slug em DB sem label canônico) ainda renderizam o
  `fee_type` como label cru — fail-soft, mas o teste de contrato detecta
  drift na PR.

  ### 4. OpenAPI (`public/openapi.json`)

  Enum atualizado para incluir `fx_spread`. Description aponta para
  `lib/platform-fee-types.ts` como source-of-truth e cita L01-45 para
  rastreabilidade. Teste de contrato faz parsing do JSON e compara o
  conjunto com `PLATFORM_FEE_TYPES` — qualquer regressão futura quebra CI.

  ### 5. Contract-lock test (`platform-fee-types.test.ts`)

  Nove testes cruzam as quatro superfícies em uma única run de CI:

    • Lista canônica tem exatamente 5 entradas na ordem documentada.
    • `'fx_spread'` está presente (regression guard explícito L01-44/45).
    • `platformFeeTypeSchema` aceita os 5 e rejeita variantes (case,
      espaços, `null`, número, slug fictício).
    • `FEE_TYPE_LABELS` tem label + description não-vazios para cada slug.
    • `FEE_TYPE_LABELS` não tem chaves órfãs (linhas UI sem dados em DB).
    • `isPlatformFeeType()` narrow correto para válidos e inválidos.
    • `public/openapi.json` enum (sorted) == `PLATFORM_FEE_TYPES` (sorted).
    • Migration `20260417130000_fix_platform_fee_config_check.sql` contém
      `'<slug>'` literal para CADA slug canônico — falha se alguém
      adicionar um slug em TS sem widening do CHECK no Postgres.
    • `PlatformFeeType[]` é exhaustivo (smoke test de tipo).

  ## Defense-in-depth bônus

    • Cabeçalho do módulo é o único playbook documentado para adicionar
      `fee_type`; runbook não precisa ser mantido em paralelo.
    • Type-narrowing em `isPlatformFeeType` substitui o fallback genérico
      `?? { label: fee.fee_type, description: "" }` por uma checagem
      explícita — bugs futuros (ex.: typo em FEE_TYPE_LABELS) ficam
      visíveis no diff em vez de degradarem silenciosamente para "label
      cru" na UI.

  ## Verificação

    • `npx vitest run src/lib/platform-fee-types.test.ts src/app/api/platform/fees/route.test.ts`
      → 24 tests passed (9 novos contract-lock + 15 existentes).
    • `npm run lint` → clean.
    • `npx vitest run` (suite completa) → 1304 passed (era 1295; +9
      novos).

  ## Histórico de fixes relacionados

    • L01-13 (2026-04-17) — schema parcial fix.
    • L01-44 (2026-04-17) — CHECK constraint widening + INSERT idempotente
      de `fx_spread`.
    • L01-45 (este fix, 2026-04-17) — consolidação em fonte única de
      verdade + contract-lock test cruzando TS/Zod/labels/OpenAPI/SQL.
---
# [L01-45] fee_type — 'fx_spread' ausente do endpoint admin
> **Lente:** 1 — CISO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fixed (2026-04-17)
**Camada:** PORTAL
**Personas impactadas:** platform_admin

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.45]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.45).
- `2026-04-17` — Fix técnico imediato (`fx_spread` adicionado ao Zod enum) entrou junto com L01-13/L01-44.
- `2026-04-17` — Promovido a `fixed`: consolidada lista canônica em `lib/platform-fee-types.ts`, OpenAPI sincronizado, contract-lock test cruzando 5 superfícies (TS/Zod/labels/OpenAPI/SQL). Commit `5f59736`.
