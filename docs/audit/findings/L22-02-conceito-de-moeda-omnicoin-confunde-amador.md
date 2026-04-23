---
id: L22-02
audit_ref: "22.2"
lens: 22
title: "Conceito de \"moeda / OmniCoin\" confunde amador"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["finance", "mobile", "personas", "athlete-amateur"]
files:
  - portal/src/lib/omnicoin-narrative/types.ts
  - portal/src/lib/omnicoin-narrative/translate.ts
  - portal/src/lib/omnicoin-narrative/index.ts
  - portal/src/lib/omnicoin-narrative/translate.test.ts
  - tools/audit/check-omnicoin-narrative.ts
  - supabase/migrations/20260421700000_l22_02_revoke_nonchallenge_coins.sql
correction_type: code
test_required: true
tests:
  - portal/src/lib/omnicoin-narrative/translate.test.ts
  - tools/audit/check-omnicoin-narrative.ts
  - tools/audit/check-referral-program.ts
  - tools/audit/check-sponsorships.ts
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Amadores nunca veem coins; o módulo `omnicoin-narrative` renderiza copy
  persona-aware usando um union fechado de `ChallengeLedgerReason` (8
  motivos, todos ligados a desafios). Para a persona `amateur` o template
  é puramente narrativo e **nunca** menciona "OmniCoin" nem números
  derivados de `deltaCoins`. Personas `pro` / `coach` / `admin_master`
  enxergam o valor bruto para reconciliação operacional.

  Escopo estendido (2026-04-21): após o product owner reafirmar que
  "OmniCoins são usadas SOMENTE em desafios", a migration compensatória
  `20260421700000_l22_02_revoke_nonchallenge_coins.sql` foi adicionada
  para reverter dois vazamentos introduzidos em Batch J:
    - L15-02: `fn_activate_referral` creditava `referral_referrer_reward`
      / `referral_referred_reward` no `coin_ledger` + bump em `wallets`.
      Substituído por uma versão sem mutação de ledger/wallet (a tabela
      `referrals` continua existindo para tracking de crescimento viral).
    - L16-05: `fn_sponsorship_distribute_monthly_coins` creditava uma
      mesada mensal sob reason `sponsorship_payout`. Função dropada e
      colunas de orçamento (`monthly_coins_per_athlete`, `coin_budget_*`)
      removidas de `sponsorships`.
    - CHECK constraint `coin_ledger_reason_check` restaurado para a
      lista canônica L03-13 + `challenge_withdrawal_refund`; reasons
      pre-existentes `institution_token_*` / `institution_switch_burn`
      (que L16-05 havia removido silenciosamente) foram reinstalados.
    - Self-test da migration falha se qualquer reason proibido ressurgir.
    - CI guard `check-omnicoin-narrative` varre `supabase/migrations` +
      `supabase/functions` e falha se qualquer literal de reason
      proibido for reintroduzido em código.
---
# [L22-02] Conceito de "moeda / OmniCoin" confunde amador
> **Lente:** 22 — Atleta Amador · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— [7.12] repete. Amador pensa "corro por saúde, não quero moeda". Conceito financeiro complexo na frente assusta.
## Correção proposta

— UI amador **não mostra** coins/wallet. Apenas badges, streaks, KM totais. Coaches e assessorias usam coins nos bastidores. Amador só "desbloqueia" benefícios via interface narrativa.

## Correção aplicada
1. Módulo pure-domain `portal/src/lib/omnicoin-narrative/`:
   - `types.ts` exporta o union fechado `ChallengeLedgerReason` com 8
     motivos estritamente ligados a desafios (entry fee / refunds /
     completions / wins) + o set `PERSONAS_HIDING_COINS = {"amateur"}`.
   - `translate.ts` → `renderChallengeNarrative(event, persona, locale)`:
     amadores veem só narrativa (ex.: "Inscrição confirmada"); coaches e
     admins veem o `deltaCoins` literal para reconciliação.
   - Teste `translate.test.ts` cobre iteração exaustiva dos 8 motivos na
     persona amateur provando ausência de dígitos / palavra "OmniCoin".
2. CI guard `tools/audit/check-omnicoin-narrative.ts` reforça:
   - union fechado imutável, templates amateur livres de números,
   - CHECK constraint do banco proibindo reasons fora do conjunto
     canônico, e
   - varredura global de `supabase/` bloqueando literais de reason
     proibidos (referral / sponsorship / welcome / onboarding etc.).
3. Migration `20260421700000_l22_02_revoke_nonchallenge_coins.sql`
   compensa os vazamentos introduzidos em L15-02 e L16-05 — ver a nota
   frontmatter para detalhes.

**Política do produto (invariante):** OmniCoins são exclusivamente
emitidas/queimadas por fluxos de desafio. Nenhuma outra feature pode
creditar coins ao usuário — referral, patrocínio, onboarding, streak,
welcome, etc. entregam valor por outras vias (narrativa, benefício
físico, desconto em reais, etc.), nunca por moeda virtual.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[22.2]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 22 — Atleta Amador, item 22.2).
- `2026-04-21` — Módulo `omnicoin-narrative` + guard entregues (J40).
- `2026-04-21` — Escopo estendido: migration compensatória revoga coin-credit em referral (L15-02) e sponsorship (L16-05); restaura CHECK canônico.
