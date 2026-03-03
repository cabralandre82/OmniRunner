# QA-01 — Fluxo Dummy E2E (Personas + Cenários)

## Personas de Teste

| Persona | Role | Grupo | Descrição |
|---------|------|-------|-----------|
| Coach Carlos | `admin_master` | Grupo A | Criador/dono do grupo |
| Assistente Ana | `assistant` | Grupo A | Staff sem permissão de criar avisos |
| Atleta André | `athlete` | Grupo A | Atleta ativo |
| Atleta Bia | `athlete` | Grupo A | Atleta novo (sem presença, será candidato a alerta) |
| Coach Diego | `admin_master` | Grupo B | Dono de outro grupo (isolamento) |

---

## Caminho Feliz — Coach Carlos (admin_master, Grupo A)

| # | Passo | Tela/Ação | Esperado | Status |
|---|-------|-----------|----------|--------|
| 1 | Login | App: auth gate | Direciona para staff dashboard | ⬜ |
| 2 | Criar treino | `staff_training_create_screen` | Form: título*, starts_at*, ends_at | ⬜ |
| 3 | Validação | Preencher e salvar | Tela fecha, treino aparece na lista | ⬜ |
| 4 | Persistência | Fechar e reabrir app | Treino ainda aparece na lista | ⬜ |
| 5 | Ver agenda | `staff_training_list_screen` | Lista paginada com treinos do Grupo A | ⬜ |
| 6 | Detalhe do treino | `staff_training_detail_screen` | Dados do treino + lista de presença (vazia) | ⬜ |
| 7 | Scan QR (André) | `staff_training_scan_screen` | Snackbar "Presença registrada com sucesso" | ⬜ |
| 8 | Verificar presença | Detalhe do treino | André aparece na lista de presença | ⬜ |
| 9 | CRM: ver atletas | `staff_crm_list_screen` | Lista com André e Bia, filtros de tags/status | ⬜ |
| 10 | CRM: criar tag | Ação inline | Tag criada, snackbar confirmação | ⬜ |
| 11 | CRM: atribuir tag | Perfil do atleta | Tag aparece no perfil do André | ⬜ |
| 12 | CRM: adicionar nota | `staff_athlete_profile_screen` | Nota salva, aparece na aba "Notas" | ⬜ |
| 13 | Publicar aviso | `announcement_create_screen` | Aviso criado, aparece no feed | ⬜ |
| 14 | Ver dashboard KPIs | `staff_dashboard_screen` | DAU/WAU/MAU, scores, alerts visíveis | ⬜ |
| 15 | Portal: login | `/` → dashboard | Sidebar com todas as entradas | ⬜ |
| 16 | Portal: presença | `/attendance` | Tabela com treinos + % presença | ⬜ |
| 17 | Portal: CRM | `/crm` | Tabela com atletas, filtros, export CSV | ⬜ |
| 18 | Portal: avisos | `/announcements` | Lista com taxa de leitura | ⬜ |
| 19 | Portal: risco | `/risk` | Alertas high/medium | ⬜ |
| 20 | Portal: export | `/exports` | 5 cards de export, CSV download funciona | ⬜ |

## Caminho Feliz — Assistente Ana (assistant, Grupo A)

| # | Passo | Tela/Ação | Esperado | Status |
|---|-------|-----------|----------|--------|
| 1 | Login | App | Staff dashboard | ⬜ |
| 2 | Ver agenda | `staff_training_list_screen` | Treinos do Grupo A visíveis | ⬜ |
| 3 | Scan QR presença | `staff_training_scan_screen` | Presença registrada | ⬜ |
| 4 | Ver CRM | `staff_crm_list_screen` | Atletas visíveis com filtros | ⬜ |
| 5 | Portal: relatório | `/attendance` | Dados visíveis (se assistant tem acesso) | ⬜ |
| 6 | **Não pode**: criar aviso | `announcement_create_screen` | Botão "+" não aparece ou RLS nega | ⬜ |

## Caminho Feliz — Atleta André (athlete, Grupo A)

| # | Passo | Tela/Ação | Esperado | Status |
|---|-------|-----------|----------|--------|
| 1 | Login | App | Athlete dashboard | ⬜ |
| 2 | Ver treinos | `athlete_training_list_screen` | Treinos próximos + histórico do Grupo A | ⬜ |
| 3 | Gerar QR | `athlete_checkin_qr_screen` | QR com timer/countdown de expiração | ⬜ |
| 4 | Ver presença | `athlete_attendance_screen` | Lista de presenças (somente self) | ⬜ |
| 5 | Ver avisos | `announcement_feed_screen` | Feed de avisos do grupo | ⬜ |
| 6 | Marcar leitura | `announcement_detail_screen` | "Lido" marcado automaticamente ou por botão | ⬜ |
| 7 | Ver meu status | `athlete_my_status_screen` | Status definido pelo coach | ⬜ |
| 8 | Ver evolução | `athlete_my_evolution_screen` | Dados de presença/score próprios | ⬜ |
| 9 | **Não pode**: ver notas internas | N/A | RLS nega — 0 linhas retornadas | ⬜ |
| 10 | **Não pode**: acessar portal staff | Portal | Redirect para `/no-access` | ⬜ |

## Caminho Feliz — Coach Diego (admin_master, Grupo B) — Isolamento

| # | Passo | Tela/Ação | Esperado | Status |
|---|-------|-----------|----------|--------|
| 1 | Login | App | Dashboard do Grupo B | ⬜ |
| 2 | Ver treinos | `staff_training_list_screen` | **ZERO** treinos do Grupo A | ⬜ |
| 3 | Ver atletas | `staff_crm_list_screen` | **ZERO** atletas do Grupo A | ⬜ |
| 4 | Ver avisos | `announcement_feed_screen` | **ZERO** avisos do Grupo A | ⬜ |
| 5 | Portal: presença | `/attendance` | Apenas dados do Grupo B | ⬜ |
| 6 | Portal: KPIs | `/engagement` | Apenas snapshots do Grupo B | ⬜ |
| 7 | SQL direto (service_role) | Query com JWT Diego | Confirmar 0 linhas cross-group | ⬜ |

---

## Caminho Ruim — Cenários de Erro

### Sem Internet

| # | Cenário | Tela | Esperado | Status |
|---|---------|------|----------|--------|
| 1 | Abrir app offline | Splash/Auth | Mensagem "Sem conexão" ou cache offline | ⬜ |
| 2 | Criar treino offline | Create screen | Erro claro, dados NÃO salvos localmente como real | ⬜ |
| 3 | Scan QR offline | Scanner | `fn_mark_attendance` falha → snackbar de erro | ⬜ |
| 4 | Portal offline | Qualquer página | Erro de fetch, não crash branco | ⬜ |

### Sessão Expirada

| # | Cenário | Tela | Esperado | Status |
|---|---------|------|----------|--------|
| 5 | Token JWT expirado | Qualquer ação | 401 → redirect para login | ⬜ |
| 6 | Portal cookie expirado | Qualquer página | Redirect para login | ⬜ |

### Sem Permissão (role errado)

| # | Cenário | Tela | Esperado | Status |
|---|---------|------|----------|--------|
| 7 | Atleta tenta criar treino | RPC/RLS | Erro "Sem permissão" | ⬜ |
| 8 | Atleta tenta marcar presença de outro | `fn_mark_attendance` | `forbidden` | ⬜ |
| 9 | Atleta acessa portal staff | `/crm`, `/risk` | Redirect `/no-access` | ⬜ |
| 10 | Coach B tenta editar treino do A | RLS | Policy violation → 0 rows affected | ⬜ |

### QR Expirado / Inválido

| # | Cenário | Tela | Esperado | Status |
|---|---------|------|----------|--------|
| 11 | QR com `expires_at` passado | Scanner | Snackbar "QR expirado" | ⬜ |
| 12 | QR com payload corrompido | Scanner | Snackbar "QR inválido" | ⬜ |
| 13 | QR de atleta de outro grupo | Scanner | `fn_mark_attendance` → `forbidden` | ⬜ |
| 14 | QR de treino cancelado | Scanner | Mensagem "treino cancelado" (ou `invalid`) | ⬜ |

### Lista Vazia

| # | Cenário | Tela | Esperado | Status |
|---|---------|------|----------|--------|
| 15 | Grupo sem treinos | Training list | Empty state com CTA | ⬜ |
| 16 | Grupo sem atletas | CRM list | Empty state "Nenhum atleta" | ⬜ |
| 17 | Sem alerts | Risk page | "Nenhum atleta em risco" | ⬜ |
| 18 | Sem avisos | Feed | Empty state "Nenhum aviso" + CTA (staff) | ⬜ |
| 19 | Compute nunca rodou | Engagement | "Sem dados" / último dia fechado | ⬜ |

---

## Bugs Encontrados (Priorizados)

| # | Severidade | Descrição | Evidência | Patch |
|---|-----------|-----------|-----------|-------|
| B01 | **P0** | Mock fallback silencioso: se `Supabase.initialize()` falha, 4 repos servem dados fake (tokens=1000, profile fake, auth fake) | `core/service_locator.dart:226-242,364-373` | Trocar stubs por `throw StateError` ou retornar zeros |
| B02 | **P0** | Export engagement sem autenticação: `/api/export/engagement/route.ts` não verifica sessão | `portal/src/app/api/export/engagement/route.ts` | Adicionar `getSession()` + role check |
| B03 | **P1** | Atleta screens sem botão "Tentar novamente" no erro | `athlete_training_list_screen.dart`, `athlete_my_status_screen.dart`, `athlete_my_evolution_screen.dart` | Adicionar retry button no error state |
| B04 | **P1** | 9 repos/blocs novos (OS-01/02/03) sem `AppLogger` nos catches | Todos os `supabase_*_repo.dart` e `*_bloc.dart` novos | Adicionar `AppLogger.error()` em cada catch |
| B05 | **P1** | QR nonce gerado mas nunca validado (anti-replay não implementado) | `fn_mark_attendance` em migration OS-01 | Implementar validação de nonce ou documentar como "MVP: TTL-only" |
| B06 | **P1** | `coaching_alerts.resolved` vs `is_read` — nome inconsistente entre Flutter, Portal e migration | Migration, portal risk page, app entities | Padronizar para `resolved` |
| B07 | **P2** | Park screen exibe stats fabricadas (14, 87, 1243) quando offline | `park_screen.dart:64-70` | Retornar null/zeros em vez de números fake |
| B08 | **P2** | Forms (criar treino, criar aviso) não mostram snackbar de sucesso | `staff_training_create_screen.dart`, `announcement_create_screen.dart` | Adicionar `ScaffoldMessenger.showSnackBar` |
| B09 | **P2** | Portal pages novas sem try/catch nos SSR queries | `attendance/page.tsx`, `crm/page.tsx`, `announcements/page.tsx` | Wrap em try/catch + error boundary |

---

## Verificação SQL (Evidências de Isolamento)

```sql
-- Executar com JWT de Coach Diego (Grupo B):
SELECT count(*) FROM coaching_training_sessions WHERE group_id = 'GRUPO_A_ID';
-- Expected: 0

SELECT count(*) FROM coaching_athlete_notes WHERE group_id = 'GRUPO_A_ID';
-- Expected: 0

SELECT count(*) FROM coaching_announcements WHERE group_id = 'GRUPO_A_ID';
-- Expected: 0

-- Executar com JWT de Atleta André (Grupo A):
SELECT count(*) FROM coaching_athlete_notes WHERE group_id = 'GRUPO_A_ID';
-- Expected: 0 (athlete cannot read notes at all)

SELECT count(*) FROM coaching_training_attendance
WHERE group_id = 'GRUPO_A_ID' AND athlete_user_id != auth.uid();
-- Expected: 0 (athlete only sees self)
```
