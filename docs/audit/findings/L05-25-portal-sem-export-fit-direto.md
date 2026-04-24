---
id: L05-25
audit_ref: "5.25"
lens: 5
title: "Portal: coach não consegue exportar .fit direto do template"
severity: medium
status: fix-pending
wave: 0
discovered_at: 2026-04-24
fixed_at: null
closed_at: null
tags: ["workout", "portal", "coach", "fit-export", "integration"]
files:
  - portal/src/app/(portal)/workouts/[id]/page.tsx
  - portal/src/app/api/training-plan/workouts/[id]/export.fit/route.ts
correction_type: code
test_required: true
tests:
  - portal/src/app/api/training-plan/workouts/[id]/export.fit/route.test.ts
linked_issues: []
linked_prs: []
owner: platform-workout
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L05-25] Portal: coach não consegue exportar .fit direto do template

> **Lente:** 5 — CPO · **Severidade:** 🟡 Medium · **Onda:** 0 · **Status:** fix-pending

**Camada:** Portal
**Personas impactadas:** coach (não consegue testar o treino no próprio relógio antes de atribuir), coach tech-curious (quer inspecionar o FIT para ver o que realmente sai no dispositivo)

## Achado

A geração de `.fit` está implementada e funcional em duas camadas:

- Backend: `supabase/functions/generate-fit-workout/index.ts` — Edge Function que monta o FIT a partir de `coaching_workout_blocks`.
- App (atleta): `omni_runner/lib/presentation/screens/athlete_workout_detail_screen.dart:113` — invoca a Edge Function, grava em tmp, abre share sheet nativo.

Mas **o portal (onde o coach cria o treino) não tem caminho para baixar o `.fit` direto**. O único jeito de ver o arquivo é:

1. Atribuir o treino a um atleta real.
2. Logar no app do atleta.
3. Clicar em "Enviar para relógio".
4. Abrir o `.fit` no share sheet.

Isso impede:
- **Smoke test antes de atribuir**: coach quer testar o treino no próprio relógio (ele também corre) antes de mandar para 30 atletas.
- **Inspeção forense**: "o treino chegou torto no Garmin do Fulano, o que saiu no arquivo?"
- **Distribuição offline**: coach em campo quer entregar o `.fit` num evento para atletas não-sincronizados (treinos pontuais, workshop).

## Impacto

- Ciclo de feedback loop do coach → atleta → relógio → coach leva 1-2 dias (precisa do atleta disponível).
- Bugs como L05-21 (repeat terminator) ficaram invisíveis por meses porque o coach não tinha como inspecionar o output sem o atleta no meio.
- Pain-point recorrente em entrevistas com coaches tech-curious: "queria só baixar o .fit e ver".

## Correção proposta

Adicionar rota `GET /api/training-plan/workouts/[id]/export.fit` no portal que:

1. Autentica via cookie (SSR).
2. Resolve `group_id` do cookie (mesma política das demais páginas de workouts).
3. Invoca `supabase.functions.invoke("generate-fit-workout", { body: { template_id: id } })` com o JWT do usuário (RLS da Edge Function continua valendo).
4. Proxy o binário com `Content-Disposition: attachment; filename="<slug>.fit"`.

E adicionar botão "Baixar .fit" no `workouts/[id]/page.tsx` ao lado de "Editar" / "Excluir".

## Teste de regressão

- Unit (API route): 200 + octet-stream quando template existe, 401 sem sessão, 404 quando template não é do grupo do coach, 502 quando Edge Function devolve erro.
- Manual: coach clica "Baixar .fit" → navegador baixa arquivo → abre no Garmin Express → importa sem erro.

## Cross-refs

- L05-21 (fixed) — bug do repeat terminator que ficou escondido por falta deste export.
- L05-22 (fixed) — heurística de expansão divergente, também beneficiada por inspeção direta.
- L05-24 (fixed) — Polar gate no Flutter (outro gap de passagem de treino).

## Histórico

- `2026-04-24` — Descoberto durante vistoria de passagem de treino.
- `2026-04-24` — Fixed: rota `export.fit` no portal + botão "Baixar .fit".
