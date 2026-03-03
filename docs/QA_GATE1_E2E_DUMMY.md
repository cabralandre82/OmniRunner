# GATE 1 — E2E Dummy Flows

> Fluxos completos rastreados end-to-end com 7 personas.  
> Data: 2026-03-03

---

## Personas

| Persona | Role | Group | Descrição |
|---------|------|-------|-----------|
| **Admin A** | admin_master | Group A | Dono da assessoria A |
| **Coach A** | coach | Group A | Treinador da assessoria A |
| **Assistant A** | assistant | Group A | Auxiliar da assessoria A |
| **Athlete A1** | athlete | Group A | Atleta experiente do grupo A |
| **Athlete A2** | athlete | Group A | Atleta novo do grupo A |
| **Admin B** | admin_master | Group B | Dono da assessoria B |
| **Athlete B1** | athlete | Group B | Atleta do grupo B |

---

## Happy Paths

### HP-01: Workout Builder → Assignment → Execution → KPIs → Portal

**Personas:** Admin A, Coach A, Athlete A1

| Step | Actor | Ação | Tela/Rota | Endpoint/RPC | Dados |
|------|-------|------|-----------|--------------|-------|
| 1 | Admin A | Login no portal | `/select-group` | `auth/callback`, cookie `portal_group_id` | session |
| 2 | Admin A | Acessa Dashboard | `/dashboard` | SELECT coaching_token_inventory, coaching_members, sessions | KPIs renderizados |
| 3 | Coach A | Login no app | `login_screen.dart` | Supabase Auth | auth token |
| 4 | Coach A | Abre Staff Dashboard | `staff_dashboard_screen.dart` | SELECT coaching_members WHERE role IN (admin_master, coach, assistant) | 6 cards |
| 5 | Coach A | Cria template de treino | `staff_workout_builder_screen.dart` | INSERT coaching_workout_templates + coaching_workout_blocks | template_id |
| 6 | Coach A | Atribui treino a Athlete A1 | `staff_workout_assign_screen.dart` | INSERT coaching_workout_assignments (valida coaching_subscriptions) | assignment_id |
| 7 | Athlete A1 | Login no app | `login_screen.dart` | Supabase Auth | auth token |
| 8 | Athlete A1 | Visualiza treino do dia | `athlete_workout_day_screen.dart` | SELECT coaching_workout_assignments + blocks WHERE athlete_user_id + scheduled_date | Blocos renderizados |
| 9 | Athlete A1 | Executa e registra manualmente | `athlete_log_execution_screen.dart` | INSERT coaching_workout_executions | execution_id |
| 10 | Sistema | KPIs atualizados | — | `calculate-progression`, `evaluate-badges` | XP, badges |
| 11 | Admin A | Vê execução no portal | `/executions` | SELECT coaching_workout_executions | Linha aparece |
| 12 | Admin A | Vê analytics de treinos | `/workouts/analytics` | SELECT coaching_workout_executions agg | Gráficos atualizados |

**Resultado esperado:** Template → Blocos → Assignment → Execução → KPIs → Portal reflete tudo.

---

### HP-02: Training Session + QR Attendance (OS-01)

**Personas:** Coach A, Athlete A1, Athlete A2

| Step | Actor | Ação | Tela/Rota | Endpoint/RPC | Dados |
|------|-------|------|-----------|--------------|-------|
| 1 | Coach A | Cria sessão de treino | `staff_training_create_screen.dart` | INSERT coaching_training_sessions | session_id |
| 2 | Coach A | Gera QR de presença | `staff_generate_qr_screen.dart` via `issue_checkin_token` | token_intents | QR com checkin_token |
| 3 | Athlete A1 | Escaneia QR | `athlete_checkin_qr_screen.dart` | `mark_attendance` → INSERT coaching_training_attendance | status=present |
| 4 | Athlete A2 | Escaneia mesmo QR | `athlete_checkin_qr_screen.dart` | `mark_attendance` | status=present (idempotent) |
| 5 | Coach A | Vê lista de presença | `staff_training_detail_screen.dart` | SELECT coaching_training_attendance WHERE session_id | 2 atletas presentes |
| 6 | Admin A | Vê analytics no portal | `/attendance`, `/attendance-analytics` | SELECT coaching_training_attendance agg | Taxas de presença |

**Resultado esperado:** QR gerado → 2 atletas escaneiam → presença registrada → portal reflete.

---

### HP-03: Financial Plan → Subscription → Assignment Gate (BLOCO B + C)

**Personas:** Admin A, Athlete A1

| Step | Actor | Ação | Tela/Rota | Endpoint/RPC |
|------|-------|------|-----------|--------------|
| 1 | Admin A | Cria plano financeiro | Portal `/financial/plans` | INSERT coaching_plans |
| 2 | Admin A | Inscreve Athlete A1 | Portal `/financial/subscriptions` | `manage_subscription` → INSERT coaching_subscriptions |
| 3 | Admin A | Tenta atribuir treino | `staff_workout_assign_screen.dart` | INSERT coaching_workout_assignments |
| 4 | Sistema | Valida subscription ativa | — | CHECK coaching_subscriptions.status = 'active' |
| 5 | Admin A | Vê receita no dashboard financeiro | Portal `/financial` | SELECT coaching_financial_ledger |

**Resultado esperado:** Plano → Assinatura ativa → Assignment permitido → Receita contabilizada.

---

### HP-04: Announcements + Read Receipts (OS-03)

**Personas:** Coach A, Athlete A1, Athlete A2, Admin A

| Step | Actor | Ação | Tela/Rota | Endpoint/RPC |
|------|-------|------|-----------|--------------|
| 1 | Coach A | Cria comunicado | `announcement_create_screen.dart` ou Portal `/announcements` | POST `/api/announcements` |
| 2 | Athlete A1 | Abre feed de comunicados | `announcement_feed_screen.dart` | SELECT coaching_announcements WHERE group_id |
| 3 | Athlete A1 | Abre detalhe | `announcement_detail_screen.dart` | INSERT coaching_announcement_reads |
| 4 | Athlete A2 | NÃO abre | — | — |
| 5 | Admin A | Vê taxa de leitura no portal | Portal `/announcements` | COUNT reads / COUNT members = 50% |

**Resultado esperado:** 1 de 2 atletas leu → taxa = 50% no portal.

---

### HP-05: TrainingPeaks Integration (BLOCO D)

**Personas:** Athlete A1, Coach A, Admin A

| Step | Actor | Ação | Tela/Rota | Endpoint/RPC |
|------|-------|------|-----------|--------------|
| 1 | Athlete A1 | Vincula TrainingPeaks | `athlete_device_link_screen.dart` | `link_device` → INSERT coaching_device_links (provider='trainingpeaks') |
| 2 | Coach A | Vê atleta vinculado no portal | Portal `/trainingpeaks` | SELECT coaching_device_links WHERE provider='trainingpeaks' |
| 3 | Coach A | Envia treino para TP | Via app `push_to_trainingpeaks` | `trainingpeaks-sync` edge function |
| 4 | Athlete A1 | Executa treino no TP | (externo) | — |
| 5 | Sistema | Importa execução | `trainingpeaks-sync` (cron/webhook) | INSERT coaching_workout_executions (source='trainingpeaks') |
| 6 | Admin A | Vê execução importada | Portal `/executions` | source='trainingpeaks' na tabela |

**Resultado esperado:** Vínculo → Push → Execução externa → Import automático.

---

### HP-06: CRM Workflow (OS-02)

**Personas:** Coach A, Assistant A, Athlete A1

| Step | Actor | Ação | Tela/Rota | Endpoint/RPC |
|------|-------|------|-----------|--------------|
| 1 | Coach A | Abre CRM no portal | Portal `/crm` | SELECT coaching_member_status, coaching_athlete_tags |
| 2 | Coach A | Clica em Athlete A1 | Portal `/crm/[userId]` | SELECT coaching_athlete_notes |
| 3 | Coach A | Adiciona nota | Portal `/crm/[userId]` add-note-form | POST `/api/crm/notes` |
| 4 | Coach A | Adiciona tag "Iniciante" | Portal `/crm` | POST `/api/crm/tags` |
| 5 | Coach A | Muda status para "trial" | App `staff_crm_list_screen.dart` | `manage_member_status` |
| 6 | Assistant A | Filtra por tag no portal | Portal `/crm?tag=Iniciante` | SELECT WHERE tag |
| 7 | Coach A | Vê Athlete A1 na lista filtrada | Portal `/crm` | 1 resultado |

**Resultado esperado:** Tags + notas + status = ficha completa, filtrável.

---

### HP-07: Token Economy (Distribute → Spend → Clearing)

**Personas:** Admin A, Athlete A1, Admin B

| Step | Actor | Ação | Tela/Rota | Endpoint/RPC |
|------|-------|------|-----------|--------------|
| 1 | Admin A | Compra créditos | Portal `/custody` | POST `/api/checkout` → `webhook-payments` |
| 2 | Admin A | Gera QR para distribuir 10 coins | `staff_generate_qr_screen.dart` | `token-create-intent` |
| 3 | Athlete A1 | Escaneia QR | `athlete_checkin_qr_screen.dart` (ou more_screen scanner) | `token-consume-intent` |
| 4 | Athlete A1 | Vê saldo | `wallet_screen.dart` | SELECT coin_ledger |
| 5 | Sistema | Clearing cron executa | — | `clearing-cron` → clearing_events, clearing_settlements |
| 6 | Admin A | Vê settlement no portal | Portal `/clearing` | SELECT clearing_settlements |

**Resultado esperado:** Compra → Distribuição → Athlete recebe → Clearing gera settlements.

---

### HP-08: Challenge Flow

**Personas:** Athlete A1, Athlete A2

| Step | Actor | Ação | Tela/Rota | Endpoint/RPC |
|------|-------|------|-----------|--------------|
| 1 | Athlete A1 | Cria desafio | `challenge_create_screen.dart` | `challenge-create` |
| 2 | Athlete A1 | Convida Athlete A2 | `challenge_invite_screen.dart` | `challenge-invite-group` |
| 3 | Athlete A2 | Aceita convite | `challenge_join_screen.dart` | `challenge-join` |
| 4 | Athlete A1 | Corre e submete | (tracking) | `submit_run_to_challenge` |
| 5 | Athlete A2 | Corre e submete | (tracking) | `submit_run_to_challenge` |
| 6 | Sistema | Lifecycle encerra | — | `lifecycle-cron` → `settle-challenge` |
| 7 | Athlete A1 | Vê resultado | `challenge_result_screen.dart` | SELECT challenge_results |

**Resultado esperado:** Desafio criado → participação → corridas submetidas → liquidado automaticamente.

---

### HP-09: Risk Alert Pipeline (OS-05)

**Personas:** Sistema, Coach A

| Step | Actor | Ação | Tela/Rota | Endpoint/RPC |
|------|-------|------|-----------|--------------|
| 1 | Sistema | KPI snapshot diário | — | `lifecycle-cron` → INSERT kpi_daily_snapshots |
| 2 | Sistema | Detecta Athlete A2 inativo 14 dias | — | `notify-rules` → INSERT coaching_alerts (type=inactive_14d) |
| 3 | Coach A | Vê alerta no portal | Portal `/risk` | SELECT coaching_alerts WHERE resolved=false |
| 4 | Coach A | Abre CRM do atleta | Portal `/crm/at-risk` → `/crm/[userId]` | SELECT coaching_member_status |
| 5 | Coach A | Resolve alerta | Portal `/risk` | UPDATE coaching_alerts SET resolved=true |
| 6 | Coach A | Exporta alertas | Portal `/exports` | GET `/api/export/alerts` |

**Resultado esperado:** Inatividade detectada → alerta gerado → staff notificado → resolução rastreada.

---

### HP-10: Onboarding Completo de Athlete A2

**Personas:** Admin A, Athlete A2

| Step | Actor | Ação | Tela/Rota | Endpoint/RPC |
|------|-------|------|-----------|--------------|
| 1 | Admin A | Compartilha código/link de convite | Portal settings ou app | invite_codes |
| 2 | Athlete A2 | Abre app pela primeira vez | `welcome_screen.dart` | — |
| 3 | Athlete A2 | Faz login | `login_screen.dart` | Supabase Auth |
| 4 | Athlete A2 | Seleciona role "Atleta" | `onboarding_role_screen.dart` | UPDATE profiles |
| 5 | Athlete A2 | Tour interativo | `onboarding_tour_screen.dart` | — |
| 6 | Athlete A2 | Insere código de convite | `join_assessoria_screen.dart` | `accept_coaching_invite` |
| 7 | Admin A | Aceita pedido | `staff_join_requests_screen.dart` | UPDATE coaching_members SET role='athlete' |
| 8 | Athlete A2 | Vê dashboard com assessoria | `athlete_dashboard_screen.dart` | coaching_members, coaching_groups |

**Resultado esperado:** Convite → Login → Onboarding → Join → Aceito → Dashboard funcional.

---

### HP-11: Portal Exports Multi-Tipo

**Personas:** Admin A

| Step | Actor | Ação | Tela/Rota | Endpoint/RPC |
|------|-------|------|-----------|--------------|
| 1 | Admin A | Acessa Exports | Portal `/exports` | — |
| 2 | Admin A | Define datas from/to | ExportCard component | — |
| 3 | Admin A | Clica "Exportar Atletas" | — | GET `/api/export/athletes?from=...&to=...` |
| 4 | Admin A | Clica "Exportar Presença" | — | GET `/api/export/attendance?from=...&to=...` |
| 5 | Admin A | Clica "Exportar CRM" | — | GET `/api/export/crm?from=...&to=...` |
| 6 | Admin A | Clica "Exportar Financeiro" | — | GET `/api/export/financial?from=...&to=...` |

**Resultado esperado:** 7 tipos de export (athletes, attendance, engagement, crm, alerts, announcements, financial) → CSV válido.

---

### HP-12: Swap de Lastro Inter-Assessoria

**Personas:** Admin A, Admin B

| Step | Actor | Ação | Tela/Rota | Endpoint/RPC |
|------|-------|------|-----------|--------------|
| 1 | Admin A | Cria oferta de venda | Portal `/swap` | POST `/api/swap` (action=create) |
| 2 | Admin B | Vê ofertas abertas | Portal `/swap` | GET swap_orders WHERE status='open' |
| 3 | Admin B | Aceita oferta | Portal `/swap` | PATCH `/api/swap` (action=accept) |
| 4 | Sistema | Settlement processado | — | swap_orders → custody_accounts |
| 5 | Admin A | Vê histórico | Portal `/swap` swap-history | swap_orders |

**Resultado esperado:** Oferta criada → aceita → settlement automático → saldos atualizados.

---

## Bad Paths

### BP-01: Athlete Tenta Criar Template → 403

| Step | Actor | Ação | Esperado |
|------|-------|------|----------|
| 1 | Athlete A1 | Tenta acessar `staff_workout_builder_screen.dart` | Role check falha |
| 2 | Sistema | RLS impede INSERT em coaching_workout_templates | 403 / error |
| 3 | UI | SnackBar "Sem permissão" ou tela inacessível | Sem crash |

**Validação:** RLS policy `coaching_workout_templates` exige role IN (admin_master, coach).

---

### BP-02: Staff A Acessa Dados do Group B → Empty/403

| Step | Actor | Ação | Esperado |
|------|-------|------|----------|
| 1 | Coach A | SELECT coaching_members WHERE group_id = 'GROUP_B_ID' | RLS filtra por group_id do staff |
| 2 | Portal | Coach A tenta `/crm` com cookie de Group B | Middleware bloqueia ou retorna empty |
| 3 | Edge Function | `token-create-intent` com group_id de B | Validação de membership falha |

**Validação:** Multi-tenancy por group_id em todas as tabelas e edge functions.

---

### BP-03: QR de Presença Expirado → Erro

| Step | Actor | Ação | Esperado |
|------|-------|------|----------|
| 1 | Coach A | Gera QR de presença (TTL=15min) | checkin_token criado |
| 2 | (espera 20 minutos) | — | Token expira |
| 3 | Athlete A1 | Escaneia QR expirado | `mark_attendance` verifica expiração |
| 4 | UI | SnackBar "QR expirado, peça um novo ao treinador" | Sem presença registrada |

**Validação:** Campo `expires_at` no token, checado em `mark_attendance`.

---

### BP-04: Presença Duplicada → Idempotente

| Step | Actor | Ação | Esperado |
|------|-------|------|----------|
| 1 | Athlete A1 | Escaneia QR de presença | attendance registrada |
| 2 | Athlete A1 | Escaneia mesmo QR novamente | ON CONFLICT (session_id, athlete_user_id) DO NOTHING |
| 3 | UI | Mensagem "Presença já registrada" | Sem duplicação |

**Validação:** UNIQUE constraint em coaching_training_attendance (session_id, athlete_user_id).

---

### BP-05: Subscription Atrasada → Assignment Bloqueado

| Step | Actor | Ação | Esperado |
|------|-------|------|----------|
| 1 | Admin A | Athlete A1 tem subscription status='late' | — |
| 2 | Coach A | Tenta atribuir treino | `staff_workout_assign_screen.dart` |
| 3 | Sistema | CHECK coaching_subscriptions.status != 'late' | INSERT falha |
| 4 | UI | SnackBar "Atleta com assinatura em atraso" | Assignment não criado |

**Validação:** BLOCO C integration — RLS/check constraint no INSERT de assignments.

---

### BP-06: Token TP Expirado → Refresh Flow

| Step | Actor | Ação | Esperado |
|------|-------|------|----------|
| 1 | Sistema | `trainingpeaks-sync` tenta chamar TP API | 401 Unauthorized |
| 2 | Sistema | Verifica coaching_device_links.expires_at < now() | Token expirado |
| 3 | Sistema | Tenta refresh com refresh_token | Novo access_token salvo |
| 4 | Sistema | Se refresh falha | UPDATE coaching_device_links SET status='expired' |
| 5 | Athlete A1 | Vê "Reconectar TrainingPeaks" | `athlete_device_link_screen.dart` |

**Validação:** `trainingpeaks-oauth` edge function gerencia refresh flow.

---

### BP-07: Import de Execução Duplicada → ON CONFLICT

| Step | Actor | Ação | Esperado |
|------|-------|------|----------|
| 1 | Sistema | `trainingpeaks-sync` importa execução X | INSERT coaching_workout_executions |
| 2 | Sistema | Sync roda novamente, tenta importar X de novo | ON CONFLICT (external_id) DO NOTHING |
| 3 | Portal | `/executions` mostra apenas 1 entrada | Sem duplicação |

**Validação:** UNIQUE constraint em coaching_workout_executions (external_id, source).

---

### BP-08: Rede Offline Durante Save → Feedback de Erro

| Step | Actor | Ação | Esperado |
|------|-------|------|----------|
| 1 | Coach A | Está criando template, perde internet | — |
| 2 | Coach A | Clica "Salvar" | INSERT falha (SocketException) |
| 3 | UI | SnackBar "Erro de conexão. Tente novamente." | Formulário mantido, dados não perdidos |
| 4 | Coach A | Internet volta, clica "Salvar" novamente | INSERT succeeds |

**Validação:** Error handling nos blocs com `try/catch` e estado de erro.

---

### BP-09: Listas Vazias → Empty State Adequado

| Step | Actor | Ação | Esperado |
|------|-------|------|----------|
| 1 | Athlete A2 (novo) | Abre Challenges List | Lista vazia |
| 2 | UI | "Nenhum desafio ativo. Crie o primeiro!" com CTA | Empty state com ação |
| 3 | Coach A | Abre CRM sem atletas | Lista vazia |
| 4 | Portal | "Nenhum atleta encontrado" com dica de convidar | Empty state informativo |

**Validação:** Todos os ListViews e tabelas do portal devem ter empty state.

---

### BP-10: Atribuição Concorrente + Mudança de Status

| Step | Actor | Ação | Esperado |
|------|-------|------|----------|
| 1 | Coach A | Inicia atribuição de treino para Athlete A1 | form aberto |
| 2 | Admin A (concorrente) | Muda status de subscription para 'cancelled' | UPDATE coaching_subscriptions |
| 3 | Coach A | Submete atribuição | INSERT falha na validação |
| 4 | UI | "Assinatura do atleta foi alterada. Recarregue." | Sem assignment inválido |

**Validação:** Optimistic locking via `version` column (migration `20260304700000_optimistic_locking.sql`).

---

### BP-11: Distribuição com Saldo Insuficiente

| Step | Actor | Ação | Esperado |
|------|-------|------|----------|
| 1 | Admin A | Inventário = 5 tokens | coaching_token_inventory.available_tokens = 5 |
| 2 | Admin A | Tenta distribuir 10 coins | POST `/api/distribute-coins` |
| 3 | API | Verifica available_tokens >= amount | 400 "Saldo insuficiente" |
| 4 | Portal | Toast "Créditos insuficientes. Adquira mais." | Sem distribuição |

**Validação:** Check constraint ou RPC validation no distribute-coins.

---

### BP-12: Athlete Tenta Acessar Portal → Redirect

| Step | Actor | Ação | Esperado |
|------|-------|------|----------|
| 1 | Athlete A1 | Acessa portal URL | middleware.ts verifica role |
| 2 | Middleware | coaching_members.role = 'athlete' ∉ allowed roles | — |
| 3 | Sistema | Redirect para `/no-access` | Página de acesso negado |

**Validação:** `middleware.ts` valida cookie `portal_role` contra NAV_ITEMS.roles.

---

### BP-13: Clearing com Fundos Insuficientes

| Step | Actor | Ação | Esperado |
|------|-------|------|----------|
| 1 | Sistema | `clearing-cron` gera settlement | clearing_settlements.status = 'pending' |
| 2 | Sistema | Debtor group tem custody_accounts.available < net_amount | — |
| 3 | Sistema | Settlement marcado status='insufficient' | Não processa pagamento |
| 4 | Admin (debtor) | Vê alerta no portal | Portal `/clearing` mostra badge "Insuficiente" |

**Validação:** `clearing-cron` verifica saldo antes de liquidar.

---

### BP-14: Multiplos Logins Simultâneos

| Step | Actor | Ação | Esperado |
|------|-------|------|----------|
| 1 | Admin A | Login no portal em browser 1 | Session 1 |
| 2 | Admin A | Login no portal em browser 2 | Session 2 |
| 3 | Ambos | Operam concorrentemente | Ambas sessões válidas |
| 4 | Admin A (browser 1) | Salva branding | POST `/api/branding` |
| 5 | Admin A (browser 2) | Vê branding atualizado no refresh | Consistência eventual |

**Validação:** Supabase sessions independentes, portal stateless via cookies.

---

### BP-15: Sessão Auth Expirada → Redirect to Login

| Step | Actor | Ação | Esperado |
|------|-------|------|----------|
| 1 | Athlete A1 | Token JWT expira durante uso | auth.getSession() retorna null/expired |
| 2 | App | `onAuthStateChange` detecta evento SIGNED_OUT | — |
| 3 | App UI | Mostra "Sessão expirada, faça login novamente" | Redirect para login_screen |
| 4 | Portal | middleware.ts detecta sessão inválida | Redirect para /login |
| 5 | Portal UI | Página de login exibida | — |

**Validação:** App: Supabase `onAuthStateChange` listener no `AuthGate`. Portal: `middleware.ts` valida sessão em cada request server-side.

---

## 4. Evidências (SQL + Validação)

### SQL de Validação — Happy Paths

```sql
-- HP-01: Verificar que admin criou grupo e coach está vinculado
SELECT cg.id, cg.name, cm.user_id, cm.role
FROM coaching_groups cg
JOIN coaching_members cm ON cm.group_id = cg.id
WHERE cm.role IN ('admin_master', 'coach')
ORDER BY cg.created_at DESC LIMIT 5;

-- HP-02: Verificar treino criado + presença registrada
SELECT ts.title, ts.starts_at, COUNT(ta.id) AS attendances
FROM coaching_training_sessions ts
LEFT JOIN coaching_training_attendance ta ON ta.session_id = ts.id
WHERE ts.group_id = '<GROUP_A_ID>'
GROUP BY ts.id
ORDER BY ts.starts_at DESC LIMIT 5;

-- HP-03: Verificar plano + subscription ativa
SELECT cs.athlete_user_id, cs.status, cp.name AS plan_name
FROM coaching_subscriptions cs
JOIN coaching_plans cp ON cp.id = cs.plan_id
WHERE cs.group_id = '<GROUP_A_ID>'
ORDER BY cs.created_at DESC LIMIT 5;

-- HP-05: Verificar TP sync
SELECT tps.assignment_id, tps.sync_status, tps.pushed_at, tps.error_message
FROM coaching_tp_sync tps
WHERE tps.group_id = '<GROUP_A_ID>'
ORDER BY tps.updated_at DESC LIMIT 5;
```

### SQL de Validação — Bad Paths

```sql
-- BP-01: Atleta NÃO pode ver templates (RLS)
-- Execute como Athlete A1:
SELECT count(*) FROM coaching_workout_templates
WHERE group_id = '<GROUP_A_ID>';
-- Esperado: 0 (RLS bloqueia)

-- BP-02: Staff A NÃO vê dados do Grupo B
SELECT count(*) FROM coaching_training_sessions
WHERE group_id = '<GROUP_B_ID>';
-- Esperado: 0

-- BP-04: Duplicação de presença
INSERT INTO coaching_training_attendance (session_id, athlete_user_id, group_id, checked_by, status, method)
VALUES ('<SESSION_ID>', '<ATHLETE_A1_ID>', '<GROUP_A_ID>', '<COACH_A_ID>', 'present', 'qr')
ON CONFLICT (session_id, athlete_user_id) DO NOTHING;
-- Esperado: 0 rows inserted (idempotente)

-- BP-07: Import wearable duplicado
SELECT fn_import_execution(
  p_source := 'garmin',
  p_provider_activity_id := 'garmin_12345',
  p_duration_seconds := 1800
);
-- Esperado: {ok: true, code: "DUPLICATE"}
```

### Comandos de Teste

```bash
# Run integration tests against local Supabase
cd /home/usuario/project-running
SUPABASE_URL=http://127.0.0.1:54321 NODE_PATH=portal/node_modules npx tsx tools/integration_tests.ts

# Run Flutter tests
cd omni_runner && flutter test --reporter expanded

# Run portal tests
cd portal && npm test && npx playwright test
```
