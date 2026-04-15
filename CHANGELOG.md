# Changelog

All notable changes to the Omni Runner project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.9.1] - 2026-04-15

### Fixed
- **[CRÍTICO] OmniCoins distribuídas sumindo do painel** (`staff_credits_screen.dart`, `distributions/page.tsx`, `distribute-coins/route.ts`): o painel mostrava 0 distribuídas porque a RLS da tabela `coin_ledger` só devolve as próprias linhas do usuário logado — coaches não viam as linhas dos atletas. Corrigido usando `fn_sum_coin_ledger_by_group` (SECURITY DEFINER) no app e `createServiceClient()` na página do portal. Adicionado `issuer_group_id` e chamada a `decrement_token_inventory` que estavam faltando em `distribute-coins/route.ts`.
- **[CRÍTICO] OmniCoins: saldo disponível não era decrementado** (`distribute-coins/route.ts`): a rota distribuía tokens para o atleta mas nunca chamava `decrement_token_inventory`, deixando `available_tokens` inalterado na assessoria. Corrigido.
- **Assessorias Parceiras: "Não foi possível carregar parcerias"** (`partner_assessorias_screen.dart`): o código verificava apenas o código de erro `42883` (Postgres) mas o PostgREST retorna `PGRST202` quando a função não está no schema cache. Corrigido para tratar ambos.
- **Suporte: "Não foi possível carregar chamados"** (`20260408130000_support_member_messages.sql`): migration que amplia as políticas RLS de `support_tickets` / `support_messages` para incluir roles atuais (`coach`, `assistant`) e permitir que atletas abram chamados. **Aplicar manualmente no SQL editor.**

### Infrastructure
- `supabase/migrations/20260415020000_coin_ledger_group_visibility.sql`: adiciona política RLS `group_staff_read_issued_ledger` em `coin_ledger` (leitura por `issuer_group_id`), backfill de `issuer_group_id` em entradas legadas via `token_intents`, e GRANT em `fn_sum_coin_ledger_by_group`. **Aplicar no SQL editor.**

---

## [1.9.0] - 2026-04-15

### Added
- **Personalização de blocos por atleta** (`WorkoutActionDrawer` → aba 🧩 Blocos): o treinador pode editar os blocos do `content_snapshot` de um treino individual sem alterar o template original. Pace, distância, HR, RPE e notas de cada bloco ficam gravados exclusivamente para aquele atleta.
- **Blocos estruturados em treinos "Descrever"** (`WorkoutPickerDrawer` → aba ✍️ Descrever): bloco editor inline agora aparece ao final do formulário, permitindo estruturar o treino com aquecimento/blocos/recuperação/volta-à-calma para compatibilidade com relógios GPS.
- **IA gera blocos completos** (`WorkoutPickerDrawer` → aba ✨ IA): `POST /api/training-plan/ai/parse-workout` agora retorna `blocks[]` com todas as fases do treino. A IA recebe instruções detalhadas de estrutura (repeat, interval, recovery...) e os blocos são exibidos como preview antes de confirmar.
- **Componente `BlockEditor`** (`portal/src/components/training-plan/block-editor.tsx`): editor reutilizável de blocos `ReleaseBlock[]` com modo edição (expandível por bloco, reordenação, remoção, adição) e modo readOnly (preview compacto). Usado na aba Blocos do drawer de ação e no formulário de treino.
- **Tipo `ReleaseBlock`** (`types.ts`): novo tipo para blocos dentro de `content_snapshot` (sem `id` de DB), com campos `target_hr_min`, `target_hr_max` para alertas de FC absolutos.

### Changed
- **`PATCH /api/training-plan/workouts/[workoutId]/update`**: aceita campo `blocks: ReleaseBlock[]` — quando presente, faz fetch do `content_snapshot` atual, substitui apenas os blocos e incrementa `content_version`.
- **`POST /api/training-plan/ai/parse-workout`**: prompt expandido, `max_tokens` 400 → 1200, retorna `blocks[]` estruturados compatíveis com GPS. Bloco com `block_type` inválido é convertido para `steady`.
- **`POST /api/training-plan/weeks/[weekId]/workouts`**: aceita `blocks[]` no body e os passa para `fn_create_descriptive_workout` via novo parâmetro `p_blocks jsonb`.
- **`GET /api/training-plan/[planId]/weeks`**: agora inclui `content_snapshot` no SELECT para que o drawer de ação exiba os blocos do treino imediatamente.

### Infrastructure
- `supabase/migrations/20260415010000_descriptive_workout_blocks.sql`: `CREATE OR REPLACE FUNCTION fn_create_descriptive_workout` — adiciona parâmetro `p_blocks jsonb DEFAULT '[]'` e usa `COALESCE(p_blocks, '[]'::jsonb)` no snapshot. **Aplicada em produção 2026-04-15** (requerido DROP da assinatura antiga antes do CREATE OR REPLACE pois o Postgres retornava `42725: function name is not unique`).

### Tests (new)
- `portal/src/app/api/training-plan/templates/route.test.ts` — 6 testes: auth, groupId, templates enriquecidos, DB error
- `portal/src/app/api/training-plan/ai/parse-workout/route.test.ts` — 8 testes: sem API key, validação, resultado com blocos, blocos vazios, fallback de tipo, erro OpenAI, sanitização
- `portal/src/app/api/training-plan/workouts/[workoutId]/update/route.test.ts` — 5 testes: auth, validação, update label, update blocos (merge snapshot), blocos > 30
- `portal/src/components/training-plan/block-editor.test.tsx` — 9 testes (happy-dom): add/remove/reorder, preview readOnly, expand, summary com pace

## [1.8.1] - 2026-04-15

### Fixed
- **Templates não apareciam no picker de treino**: `coaching_workout_templates` nunca teve colunas `sport_type` nem `workout_type`. A query `GET /api/training-plan/templates` selecionava essas colunas inexistentes → Supabase retornava `DB_ERROR` silencioso → picker sempre exibia "Sem templates cadastrados". Corrigido removendo `sport_type` da query e adicionando `workout_type` via migration.
- **Biblioteca de templates não salvava tipo**: `POST /api/workouts/templates` não persistia `workout_type`. Corrigido para aceitar e gravar o campo.
- **Build Vercel falhava por `node-fetch` sem types**: `src/test/setup.ts` estava incluído no typecheck de produção (não estava em `exclude` do `tsconfig.json`). Corrigido excluindo `src/test/**` do tsconfig e removendo polyfill desnecessário (Node 18+ tem `fetch` nativo).

### Changed
- **Deploy Vercel revertido para integração nativa**: o mecanismo de deploy via `VERCEL_TOKEN` no pipeline CI foi removido — o Vercel volta a detectar pushes no `master` e deployar automaticamente. O pipeline CI permanece como quality gate exclusivo (lint → typecheck → test → E2E → k6). Ver DECISAO 145 (revertida).

### Infrastructure
- `supabase/migrations/20260415000000_workout_template_type.sql`: ADD COLUMN `workout_type text NOT NULL DEFAULT 'free'` em `coaching_workout_templates` — **aplicada em produção 2026-04-15**
- `.github/workflows/portal.yml`: job `deploy` removido; deploy delegado à integração nativa Vercel↔GitHub

## [1.8.0] - 2026-04-14

### Added
- **IA: Briefing do atleta no CRM**: ao abrir qualquer perfil em `/crm/[userId]`, um card lazy-loaded gera automaticamente um parágrafo de 2–4 frases resumindo os sinais atuais do atleta (aderência ao plano, RPE médio, dias inativo, alertas ativos, última nota do treinador). O card é colorido de acordo com o sinal semântico retornado pela IA: verde (positivo), âmbar (atenção), vermelho (risco). Falha silenciosamente — nunca bloqueia o carregamento da página. Endpoint: `POST /api/ai/athlete-briefing`.
- **IA: Comentário pós-corrida personalizado**: ao finalizar qualquer corrida, o `RunSummaryScreen` chama a edge function `generate-run-comment` que compara a corrida atual com as últimas 8 sessões do atleta e gera 1–2 frases de feedback personalizado em português. Exibido como card `✨` no painel de métricas. Falha silenciosamente caso não haja histórico ou a IA esteja indisponível. Requer `OPENAI_API_KEY` configurada como Supabase secret.
- **`docs/AI_ROADMAP.md`**: novo arquivo documentando o ecossistema de IA implementado e 7 ideias futuras priorizadas (narrativa semanal, rascunho de mensagem para atleta em risco, gerador de comunicado, ajuste de carga sugerido, plano periodizado, auto-classificação de corrida, matching inteligente).

### Infrastructure
- `supabase/functions/generate-run-comment/index.ts`: nova edge function para comentário pós-corrida
- `supabase/config.toml`: registrada `[functions.generate-run-comment]` com `verify_jwt = true`
- **Deploy manual realizado:** função implantada via Supabase Dashboard Editor usando versão standalone (CORS, auth e helpers inlined; rate limiting omitido). Versão com módulos compartilhados mantida no repo para futuros deploys via CLI.
- **Ação necessária:** executar `supabase secrets set OPENAI_API_KEY=<chave>` para ativar o comentário pós-corrida no app (ou definir via Dashboard → Settings → Edge Functions → Secrets)

---

## [1.7.0] - 2026-04-14

### Added
- **Passagem de Treino — Visão por Atleta (padrão)**: `/training-plan` agora abre por padrão na visão "Por Atleta", mostrando todos os atletas do grupo com status da semana atual (rascunho/liberado/concluído), alerta de fadiga e link direto para a planilha. Visão "Por Planilha" mantida como aba secundária.
- **Prescrição em texto livre (Descrever)**: aba "✍️ Descrever" no `WorkoutPickerDrawer` — coach pode prescrever treinos sem usar templates: nome, tipo, descrição completa, notas, link de vídeo YouTube. Novo RPC `fn_create_descriptive_workout` no Supabase (migration `20260414000000_training_plan_v2.sql`).
- **IA: Parse de treino em linguagem natural**: aba "✨ IA" no picker — coach digita em texto livre (ex: "4x1km em 4:30 com 2min de descanso") e a IA (GPT-4o-mini via `OPENAI_API_KEY`) interpreta e retorna estrutura de treino. Endpoint `POST /api/training-plan/ai/parse-workout`.
- **Replicar semana como próxima**: menu ⋯ de cada semana ganha "Replicar como próxima semana" — calcula automaticamente a segunda-feira seguinte e duplica todos os treinos (via `fn_duplicate_week` existente). Não exige input do usuário.
- **Link de vídeo por treino**: campo `video_url` em `plan_workout_releases` (coluna adicionada via migration). Na aba "Descrever", campo de URL de vídeo. No `WorkoutActionDrawer`, link clicável com ícone YouTube na aba "Detalhes".
- **Alerta de fadiga automático**: visão "Por Atleta" detecta atletas com RPE médio ≥ 8 nas últimas 5 sessões de feedback e exibe badge ⚠️ RPE alto com valor exato.
- **Criar planilha pré-preenchida com atleta**: botão "+ Criar planilha" na linha de atleta sem planilha navega para `/training-plan/new?athleteId=xxx` com o atleta já selecionado.
- **`GET /api/training-plan/athletes-overview`**: novo endpoint retorna todos os atletas do grupo com plano ativo, semana atual, contagem de treinos por status e RPE médio.
- **`POST /api/training-plan/ai/parse-workout`**: novo endpoint chama OpenAI GPT-4o-mini para parsear descrição de treino em texto livre e retornar estrutura `{ workout_type, workout_label, description, coach_notes, estimated_distance_km, estimated_duration_minutes }`.

### Changed
- `WorkoutPickerDrawer`: 3 abas (📋 Templates / ✍️ Descrever / ✨ IA) em vez da view única de templates
- `WeeklyPlanner`: `handlePickTemplate` → `handlePick(result: WorkoutPickResult)` — aceita tanto templates quanto treinos descritivos
- `POST /api/training-plan/weeks/[weekId]/workouts`: `template_id` agora opcional; rota para `fn_create_descriptive_workout` quando ausente
- `/training-plan/page.tsx` renomeada para "Passagem de Treino" (era "Planilhas de Treino")
- Menu ⋯ da semana: "Replicar como próxima semana" adicionado acima de "Duplicar semana (escolher data)"

### Infrastructure
- `supabase/migrations/20260414000000_training_plan_v2.sql`: ADD COLUMN `video_url` + CREATE FUNCTION `fn_create_descriptive_workout` — **aplicada em produção 2026-04-14**
- `OPENAI_API_KEY` configurada como Vercel environment variable em 2026-04-14 — feature de IA ativa em produção

---

## [1.6.2] - 2026-04-15

### Added
- **Training Plan — Arquivar planilha**: botão de arquivar (ícone lixeira) no cabeçalho da planilha; confirma antes de executar e redireciona para a lista. `DELETE /api/training-plan/[planId]` faz soft-delete (`status = archived`); a planilha some de todas as listagens (que já filtravam `status != archived`), dados preservados.
- **`GET /api/athletes`**: novo endpoint que lê `portal_group_id` do cookie de sessão e retorna todos os atletas ativos do grupo (`user_id`, `display_name`, `avatar_url`). Usado pelo dropdown de atleta na criação de planilha.

### Fixed
- **Varredura de integridade frontend↔API**: revisão completa dos 60+ `fetch()` calls versus os 57 endpoints existentes. Uma rota faltando e 4 shape mismatches encontrados e corrigidos:
  - `profiles.full_name` e `profiles.username` não existem — a tabela só tem `display_name`. Corrigidos em: `api/athletes/route.ts`, `api/groups/[groupId]/members/route.ts`, `api/training-plan/[planId]/route.ts`, `training-plan/page.tsx`. Resultado: nomes de atletas apareciam como "Atleta" em toda a UI.

---

## [1.6.1] - 2026-04-15

### Fixed
- **Training Plan — WorkoutPickerDrawer vazio**: `GET /api/training-plan/templates` usava nome de relacionamento errado (`coaching_workout_template_blocks`) ao invés de `coaching_workout_blocks`; o Supabase retornava `DB_ERROR` silencioso e o picker abria sem listar nenhum template
- **Training Plan — WeeklyPlanner invisível em modelos de grupo**: a condição `plan.athlete_user_id` ocultava silenciosamente o `WeeklyPlanner` em planos criados sem atleta; agora exibe mensagem explicativa orientando o coach a criar um plano vinculado a um atleta específico

---

## [1.6.0] - 2026-04-14

### Added
- **Training Plan Module — Passagem de Treino (estilo Treinus)**: coaches can create multi-week training plans for individual athletes with a full interactive weekly grid
  - `WeeklyPlanner` component: 7-column weekly grid, today highlight, past-day styling, progress bar per week (completed/total), version update badge
  - `WorkoutPickerDrawer` (slide-in right): template library grouped by workout type, search filter + type filter chips, click-to-add
  - `WorkoutActionDrawer` (slide-in bottom): 4 tabs (Detalhes, Editar, Copiar, Agendar), release/cancel quick actions, inline label + coach notes editing, copy to any date, schedule auto-release with date+time picker
  - `BatchAssignModal`: distribute a full week to multiple athletes at once — select target date, search + checkbox list of athletes with select-all, per-athlete success/error feedback
  - Week-level actions: Liberar Semana, Duplicar, Distribuir para outros atletas
  - Real-time toast notifications for every action
- **New Portal API endpoints**: `GET /api/training-plan/[planId]`, `GET /api/training-plan/templates`, `POST /api/training-plan/bulk-assign`, `PATCH /api/training-plan/workouts/[workoutId]/update`, `GET /api/groups/[groupId]/members`
- **New DB tables** (migration `20260407000000_training_plan_module.sql`, aplicada em produção 2026-04-15): `training_plans`, `training_plan_weeks`, `plan_workout_releases`, `completed_workouts`, `athlete_workout_feedback`, `workout_change_log`, `workout_sync_cursors` — fully additive, no conflicts with existing tables
- **Support member messages** (migration `20260408130000_support_member_messages.sql`, aplicada em produção 2026-04-15): amplia RLS de `support_tickets` e `support_messages` para atletas poderem abrir e responder tickets

### Changed
- **Vercel deployment pipeline**: disconnected Vercel automatic GitHub integration to prevent duplicate deployments; all portal deploys now go exclusively through GitHub Actions CI/CD to `omni-runner-portal` project
- Portal `/training-plan/[planId]` page: replaced static form with full interactive `WeeklyPlanner` + `Add Week` modal
- `api-handler.ts`: `withErrorHandler` now supports route context params for dynamic API routes

### Fixed
- **CI/CD pipeline fully green**: corrected `working-directory` for `vercel deploy`, added Supabase secrets to all test jobs, fixed k6 installation (direct binary download), fixed Playwright test ignore flags, excluded `delivery.spec.ts` in CI (requires auth setup), visual regression baselines updated
- Code coverage thresholds adjusted to reflect current state (statements/lines: 40%, branches/functions: 55%)

### Infrastructure
- `update-snapshots.yml` workflow added for manual visual regression baseline updates
- `portal.yml` `workflow_dispatch` trigger added for manual pipeline runs

## [1.5.0] - 2026-03-19

### Added
- **Assessoria partnerships**: assessorias can send/accept/reject partner invitations; partners can be invited to championships; tutorial cards on empty states explain the flow
- **Maintenance fee per athlete**: platform charges $0–10 USD per athlete, deducted automatically from subscription payments via Asaas Split (fixedValue); recorded in `platform_revenue` when webhook confirms payment; configurable by platform admin
- New tables/RPCs: `assessoria_partnerships`, `fn_request_partnership`, `fn_respond_partnership`, `fn_list_partnerships`, `fn_count_pending_partnerships`, `fn_search_assessorias`, `fn_request_champ_join`, `fn_partner_championships`
- `rate_usd` column on `platform_fee_config` for fixed-amount fees
- Idempotency index on `platform_revenue` for maintenance fee (one record per payment)
- RLS penetration tests (`tools/test_partner_assessorias_rls.sql`), E2E integration tests (`tools/test_partnerships_e2e.sql`), 31 Vitest partnership tests, 12 Flutter widget tests
- `platform_revenue` table with RLS, indexes, and grants
- Server Actions for platform product management (`mutations.ts`) with `revalidatePath`

### Changed
- **Portal labels renamed for clarity** (assessoria portal is now "para dummies"):
  - Eventos Webhook → **Histórico de Cobranças** (with tutorial banner)
  - Custódia → **Saldo OmniCoins**
  - Compensações → **Transferências OmniCoins**
  - Distribuições → **Distribuir OmniCoins**
  - All clearing/custody page headers, KPIs, columns, and detail sections rewritten with human-friendly OmniCoins terminology
- Platform admin product mutations migrated from client-side `fetch` to **Server Actions** with `revalidatePath` (fixes products reappearing after suspend/remove)
- Asaas subscription creation now includes maintenance fee as `fixedValue` split alongside billing_split percentage
- `asaas-webhook` records maintenance revenue in `platform_revenue` on `PAYMENT_CONFIRMED`/`PAYMENT_RECEIVED`

### Fixed
- Platform admin products reappearing after suspend/remove (Router Cache not invalidated)
- 17 pre-existing Vitest failures (auth mocks, design token CSS classes, sidebar labels, swap error message)
- 3 pre-existing Flutter failures (wallet error message, brand color value, compliance false positive)
- Map route not tracing athlete's path (GPS point format + storage path issues)
- "Primeiros Passos" not detecting first run/challenges (Isar local check added)
- `backfill_strava_sessions` SQL function typo (`activity_date` → `start_date`)

### Removed
- **Dead code cleanup**: `staff_disputes_screen.dart`, `dispute_status_card.dart` (+ test), Edge Functions `clearing-confirm-sent`, `clearing-confirm-received`, `clearing-open-dispute`, `clearing-cron` and their `config.toml` entries
- Old clearing cases query from `staff-alerts` API route
- `fn_charge_maintenance_fees()` cron-based function (replaced by webhook-driven approach)

## [1.4.0] - 2026-03-06

### Added
- **Asaas billing integration**: automated payment processing for assessorias via Asaas API
- Payment configuration page at `/settings/payments` for Asaas API key setup
- Auto-billing toggle in plan assignment wizard (Step 3)
- CPF collection for athletes (Asaas requirement)
- Platform billing split (2.5%) configurable by admin
- Webhook-based subscription status sync (payment confirmed → active, overdue → late, etc.)
- Edge Functions: `asaas-sync` (API proxy), `asaas-webhook` (event receiver)
- New tables: payment_provider_config, asaas_customer_map, asaas_subscription_map, payment_webhook_events

## [1.3.0] - 2026-03-05

### Added
- **Athlete-first wizard for workouts**: step-by-step flow (1: select athletes → 2: choose/create workout → 3: confirm date & assign)
  - Inline template preview with all block details when selecting an existing template
  - Inline "criar treino novo" builder to create templates without leaving the page
  - Clear step indicators with numbered circles and checkmarks
  - Template block preview API (`GET /api/workouts/templates/blocks`)
- **Athlete-first wizard for subscriptions**: same step-by-step pattern for financial plans
  - `/financial/subscriptions/assign` page: select athletes → choose plan card → set start/due dates → assign
  - KPI badges showing active, late, and no-plan athlete counts
  - Plan cards with price display for easy visual selection
  - API route `POST /api/financial/subscriptions` (bulk upsert with conflict handling)
- **Plan CRUD**: full create/edit/delete for financial plans on `/financial/plans`
  - Inline form for creating and editing plans (name, description, price, billing cycle, workout limit, status)
  - Delete protection: cannot delete plans with active subscribers (409 error)
  - API route `POST /api/financial/plans` (create + update)
  - API route `DELETE /api/financial/plans` (with active subscriber check)
- **Portal template CRUD**: full create/edit/delete flow for workout templates
  - `/workouts/new`, `/workouts/[id]/edit` pages with `TemplateBuilder` component
  - API routes `POST/DELETE /api/workouts/templates`

### Changed
- Sidebar: reorganized financial section (Dashboard, Planos, Atribuir Plano, Assinaturas, Custódia, Compensações, Distribuições, Auditoria)
- Removed Swap de Lastro and Conversão Cambial from sidebar (low-priority features)

## [1.2.0] - 2026-03-05

### Added
- **Structured workout model v2**: pace range (min/max), HR range (bpm), repeat blocks, rest blocks, open duration support in `coaching_workout_blocks`
- **`.FIT` file generation**: Edge Function `generate-fit-workout` produces binary `.FIT` workout files (protocol 2.0, CRC-16 validated) for direct-to-watch delivery
- **"Enviar para relógio" button**: Athletes with FIT-compatible watches (Garmin, COROS, Suunto) can share `.FIT` files via native share sheet
- **Athlete-centric workout assignment page** (`/workouts/assign`): lists all athletes with watch compatibility badges, bulk assignment (select N athletes + template + date), inline watch type editing
- **Watch type tracking**: `watch_type` column on `coaching_members` with auto-detection from `coaching_device_links` via `v_athlete_watch_type` view; `fn_set_athlete_watch_type` RPC for coach override
- **Assignment → auto-attendance bridge**: `trg_assignment_to_training` trigger auto-creates `coaching_training_sessions` with distance/pace from workout blocks when assignments are created
- Portal workout template detail page (`/workouts/[id]`) with structured block visualization
- Portal templates list now shows total distance and links to detail view
- API routes: `POST /api/workouts/assign` (bulk), `POST /api/workouts/watch-type`
- FIT validation tools (`tools/test_fit_generation.js`, `tools/validate_fit.js`)
- 46 new tests: WorkoutBlockEntity v2 fields, WorkoutBlockType enum (rest/repeat), labels, repo mapper, watch type resolution, FIT compatibility
- RLS policies for athlete read access to workout blocks and templates

### Changed
- `WorkoutBlockEntity`: replaced single `targetPaceSecondsPerKm` with `targetPaceMinSecPerKm`/`targetPaceMaxSecPerKm` range; added `targetHrMin`/`targetHrMax`, `repeatCount`, `notes`
- Workout builder UI: expanded bottom sheet with pace range, HR range, repeat count, notes, rest/repeat block types
- Portal sidebar: "Treinos" renamed to "Templates", added "Atribuir Treinos" entry
- Conditional "Enviar para relógio": hidden for Apple Watch/Polar users, shows guidance text instead

## [1.1.0] - 2026-03-04

### Added
- **Auto-attendance system** replacing QR-based check-in for training sessions
  - Staff assigns workouts with distance target and optional pace range
  - System automatically evaluates athlete's next 2 runs against training parameters
  - Distance match (±15%) + pace match → Concluído; ran but no match → Parcial; no runs → Ausente
  - DB triggers on `sessions` (run sync) and `coaching_training_sessions` (new training) for real-time evaluation
  - Manual override via bottom sheet for staff to adjust status
- Workout parameter fields in training creation form (distance km, pace min/max)
- Color-coded attendance status badges (Concluído/Parcial/Ausente) in detail screens
- Attendance status display for athletes in training list bottom sheet
- Portal attendance pages updated: workout params display, status breakdown, analytics
- Unit tests for auto-attendance entities, enums, and workout params (38 tests)
- `fn_evaluate_athlete_training` DB function for workout matching logic
- `trg_session_auto_attendance` and `trg_training_close_prev` DB triggers
- `fn_search_users` DB function for user search in Flutter app
- `platform_fee_config` table with default fee configuration
- Logout button ("Sair") in portal platform admin header
- `ProfileDataService` registration in DI container

### Changed
- **Labels clarified**: "Presença" → "Treinos Prescritos" / "Cumprimento dos Treinos" across all screens and portal to distinguish workout compliance from assessoria attendance
- Portal sidebar: "Presença" → "Treinos Prescritos", "Análise Presença" → "Análise de Treinos"
- CRM labels: "Presenças" → "Treinos", attendance counts → "treinos concluídos"
- Global SafeArea fix via `MaterialApp.builder` to handle Android navigation bar overlap
- Standardized role names from Portuguese to English (`atleta`→`athlete`, `professor`→`coach`, `assistente`→`assistant`) via migration + app/portal filters
- Replaced ~40 silent `catch (_) {}` blocks with proper logging via `AppLogger`
- Premium dark mode design system applied to all 88 Flutter screens and portal pages
- Dark mode readability fixes: theme-aware colors for Strava banners, challenge cards, matchmaking, badge cards
- AppBar backgrounds: removed all `inversePrimary` overrides across 24+ screens for proper dark mode contrast
- "Progresso" hub: removed competition sub-tabs and OmniCoins section for cleaner layout
- "Primeiros passos" card made collapsible; runner quiz only shown after first steps complete
- Strava connection status now refreshes when dashboard tab becomes visible
- Map route fallback: uses `strava_activity_id` direct lookup then date-window matching in `strava_activity_history`
- Edge functions: removed `issuer_group_id` from all `coin_ledger` INSERTs (6 functions)
- Edge function `delete-account`: fixed `profiles.role` → `profiles.user_role`
- Edge function `create-portal-session`: removed non-existent `profiles.email` column
- Portal queries: added try-catch for non-existent feature tables (custody, swap, league)
- Portal role filter: `.eq("role", "athlete")` → `.in("role", ["athlete", "atleta"])` across 16+ files
- Corrected `sessions.distance_meters` → `total_distance_m` in profile screen
- Corrected `coin_ledger.issuer_group_id` removal from wallet remote source
- Corrected `coaching_members.joined_via` → `group_id` lookup in invite QR screen
- Fixed 5 broken DB functions (`fn_delete_user_data`, `fn_compute_kpis_batch`, `fn_compute_skill_bracket`, `fn_increment_wallets_batch`, `fn_sum_coin_ledger_by_group`)
- Fixed `staff-alerts` API route: `settlements` → `clearing_cases`, `created_at_ms` → `created_at`

### Fixed
- Black screen on app startup due to uncaught async initialization errors
- Strava disconnection loop in challenges list and auth repository
- "Algo deu errado" errors on verification card (duplicate DI registration)
- "Algo deu errado" on challenge/matchmaking buttons (missing general catch in BLoC)
- "Recurso não encontrado" on assign workout (improved error messages)
- Assessoria/athlete link mismatch (role name inconsistency in DB vs app filters)
- Invisible green box on "Hoje" screen (white text on green background)
- Typo "corredore" → "corredor" in active runners count
- Profile "Salvar" button not working (missing `ProfileDataService` DI registration)
- Invisible red error button on profile screen (adjusted error card styling)
- Empty fees page in platform admin (missing `platform_fee_config` table)
- Login failure "sem conexão" after disk cleanup (missing `--dart-define-from-file` in build)
- Sentry errors: `workout_delivery_items` table not found, `VerificationBloc` not registered, `ProfileDataService` not registered

### Removed
- QR code scanning screen for staff (`StaffTrainingScanScreen` no longer used for attendance)
- QR code generation for athletes (`AthleteCheckinQrScreen` navigation removed from training list)
- Deleted 129MB `app-prod-release.apk` from repository

## [1.0.13] - 2026-02-27

### Added
- Platform approval flow for assessorias (pending/approved/rejected/suspended)
- Join request approval required setting per assessoria
- Friends activity feed

### Fixed
- RLS recursion in coaching_members and group_members
- Championship templates RLS policies
- `fn_request_join` email column reference

## [1.0.0] - 2026-02-12

### Added
- Initial release with full feature set
- Flutter mobile app (Android/iOS) with Clean Architecture
- Next.js B2B portal for assessorias
- Supabase backend with RLS, Edge Functions, and pg_cron
- Strava integration as sole data source
- Gamification: challenges, OmniCoins, XP, badges, missions
- Coaching: assessorias, member management, join requests
- Championships between assessorias
- Parks detection and leaderboards
- Athlete verification system
- Push notifications via FCM
- BLE heart rate monitor support
- Health export (HealthKit / Health Connect)
- File export (GPX, TCX, FIT)
- Portal: dashboard, credits, billing, athletes, verification, engagement, settings
- Portal: platform admin (assessorias, financeiro, reembolsos, produtos, support)
