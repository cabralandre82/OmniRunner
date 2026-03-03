# QA-04 — Edge Cases (Crash-Proof)

## OS-01: Agenda de Treinos + Presença

| # | Cenário | Tela | Esperado | UI Rules | Status |
|---|---------|------|----------|----------|--------|
| 1 | Sem treinos no período | `staff_training_list_screen` | Empty state: "Nenhum treino agendado" + hint/CTA | ✅ Tem empty state | ⬜ |
| 2 | Sem treinos no período | `athlete_training_list_screen` | Empty state: "Não há treinos agendados para este grupo." | ✅ Tem empty state | ⬜ |
| 3 | Treino cancelado | `staff_training_detail_screen` | Badge "Cancelado", botões de ação desabilitados | ⬜ Verificar | ⬜ |
| 4 | Treino sem presença registrada | `staff_training_detail_screen` | Lista vazia: "Nenhuma presença registrada" (itálico) | ✅ Tem empty state | ⬜ |
| 5 | Atleta sem membership tenta QR | `fn_mark_attendance` | Retorna `{ok: false, status: 'forbidden'}` | ⬜ Verificar snackbar | ⬜ |
| 6 | Duplicar presença (mesmo atleta, mesmo treino) | `fn_mark_attendance` | `ON CONFLICT DO NOTHING` → `{ok: true, status: 'already_present'}` | ✅ Idempotente no DB | ⬜ |
| 7 | QR expirado (`expires_at` passado) | Scanner screen | Snackbar: "QR expirado" / `{status: 'expired'}` | ⬜ Verificar UX | ⬜ |
| 8 | QR com payload corrompido/inválido | Scanner screen | Snackbar: "QR inválido" | ⬜ Verificar parsing | ⬜ |
| 9 | QR de atleta de outro grupo | `fn_mark_attendance` | `{ok: false, status: 'forbidden'}` — staff não é membro | ⬜ Verificar | ⬜ |
| 10 | QR de treino cancelado | `fn_mark_attendance` | `{ok: false, status: 'invalid'}` — sessão cancelada | ⬜ Verificar | ⬜ |
| 11 | `starts_at` no futuro distante (1 ano) | Training create form | Aceita (sem restrição de range) | ⬜ Decisão | ⬜ |
| 12 | `ends_at` < `starts_at` | Training create form | Validação front: erro inline | ⬜ Verificar | ⬜ |
| 13 | Título vazio | Training create form | Validação: campo obrigatório | ⬜ Verificar | ⬜ |

## OS-02: CRM

| # | Cenário | Tela | Esperado | UI Rules | Status |
|---|---------|------|----------|----------|--------|
| 14 | Atleta sem tags | `staff_athlete_profile_screen` | Aba Tags: "Nenhuma tag atribuída" + botão adicionar | ⬜ Verificar | ⬜ |
| 15 | Atleta sem notas | `staff_athlete_profile_screen` | Aba Notas: "Nenhuma nota registrada" + botão adicionar | ✅ Tem texto | ⬜ |
| 16 | Filtro CRM retorna vazio | `staff_crm_list_screen` | "Nenhum atleta encontrado" | ✅ Tem texto (sem ícone) | ⬜ |
| 17 | Status inexistente/null | `athlete_my_status_screen` | "Status não definido pelo treinador" | ✅ "Status não definido" | ⬜ |
| 18 | Tag duplicada (mesmo nome, mesmo grupo) | `UNIQUE(group_id, name)` | DB rejeita, front mostra erro | ⬜ Verificar snackbar | ⬜ |
| 19 | Nota vazia (texto em branco) | CRM nota form | Validação front: não permite | ⬜ Verificar | ⬜ |
| 20 | Atleta tenta ler notas internas | RLS | 0 linhas retornadas (sem erro, sem dados) | ✅ Policy nega | ⬜ |
| 21 | Tag com nome muito longo (>255 chars) | Tag create | DB `text` aceita, mas UI deveria truncar | ⬜ Verificar | ⬜ |
| 22 | Deletar tag atribuída a atletas | Tag delete | `CASCADE` ou erro de FK | ⬜ Verificar comportamento | ⬜ |

## OS-03: Announcements

| # | Cenário | Tela | Esperado | UI Rules | Status |
|---|---------|------|----------|----------|--------|
| 23 | Sem anúncios | `announcement_feed_screen` | Empty state: "Nenhum aviso publicado" + ícone + CTA (staff) | ✅ Tem empty state | ⬜ |
| 24 | Anúncio deletado enquanto usuário está na tela detalhe | `announcement_detail_screen` | Refresh falha ou mostra "Aviso não encontrado" | ⬜ Verificar | ⬜ |
| 25 | Read duplicado (marcar leitura 2x) | `UNIQUE(announcement_id, user_id)` | `ON CONFLICT DO NOTHING` → sem erro, sem duplicação | ✅ Idempotente | ⬜ |
| 26 | Título vazio ao criar aviso | Create form | Validação front: campo obrigatório | ⬜ Verificar | ⬜ |
| 27 | Body vazio ao criar aviso | Create form | Aceita (body pode ser vazio/null) ou validação | ⬜ Verificar | ⬜ |
| 28 | Anúncio pinned com muitos outros pinned | Feed | Pinned aparecem no topo, sem limite definido | ⬜ Verificar order | ⬜ |
| 29 | Usuário marca read de aviso de outro grupo | `fn_mark_announcement_read` | RPC valida membership → `forbidden` | ⬜ Verificar | ⬜ |

## PASSO 05 / KPIs / Alerts

| # | Cenário | Tela | Esperado | UI Rules | Status |
|---|---------|------|----------|----------|--------|
| 30 | Sem sessões no período | Staff dashboard | KPIs = 0, sem crash | ⬜ Verificar | ⬜ |
| 31 | Snapshots nunca rodaram (primeiro dia) | Dashboard/Engagement | "Sem dados disponíveis" ou valores zerados | ⬜ Verificar | ⬜ |
| 32 | Dados parciais (hoje sem fechar) | Dashboard | Mostrar "último dia fechado" (D-1) | ⬜ Verificar label | ⬜ |
| 33 | Grupo sem atletas | Compute KPIs | `total_athletes = 0`, sem divisão por zero | ⬜ Verificar SQL | ⬜ |
| 34 | Atleta com `risk_level = null` | Risk page (portal) | Não aparece na lista (ou aparece como "sem risco") | ⬜ Verificar | ⬜ |
| 35 | Alerts vazios | Risk page (portal) | "Nenhum atleta em risco alto/médio" | ✅ Tem empty state | ⬜ |
| 36 | `attendance_rate_7d` com 0 treinos | Compute | `NULL` ou `0.00` (não NaN, não division by zero) | ⬜ Verificar SQL | ⬜ |
| 37 | Compute rodar para dia futuro | `compute_coaching_kpis_daily(future_date)` | Retorna dados zerados ou ignora silenciosamente | ⬜ Verificar | ⬜ |

## Portal — Edge Cases Gerais

| # | Cenário | Página | Esperado | Status |
|---|---------|--------|----------|--------|
| 38 | Cookie `portal_group_id` ausente | Qualquer staff page | Redirect para `/select-group` | ⬜ Verificar |
| 39 | `portal_group_id` de grupo inexistente | Qualquer staff page | Erro "Grupo não encontrado" ou redirect | ⬜ Verificar |
| 40 | Export CSV com 0 linhas | `/exports` → download | CSV com apenas header, sem crash | ⬜ Verificar |
| 41 | Export CSV com 100k linhas | `/exports` → download | Funciona sem timeout (set-based query) | ⬜ Verificar perf |
| 42 | Página carrega com Supabase offline | Qualquer SSR page | Error boundary, não crash branco | ❌ Sem try/catch hoje |

---

## Regras de UI Obrigatórias (Checklist)

| Regra | App (Flutter) | Portal |
|-------|---------------|--------|
| Empty state com CTA | ⚠️ Maioria ok, CRM falta ícone/CTA | ⚠️ `announcements` sem empty state |
| Nenhum `null` exibido cru | ⬜ Verificar mappers | ⬜ Verificar SSR |
| Nenhum crash por `index out of range` | ⬜ Verificar listas com pagination | ⬜ Verificar tabelas |
| Loading sem "piscadas" | ✅ `CircularProgressIndicator` consistente | ⚠️ SSR (sem spinner client-side) |
| Erro com "Tentar de novo" | ❌ 3 telas athlete sem retry | ❌ Portal sem error states |

---

## Bugs por Severidade

| # | Severidade | Cenário | Problema |
|---|-----------|---------|----------|
| E01 | **P1** | #42: Portal SSR com Supabase offline | Crash branco (sem error boundary nos pages novos) |
| E02 | **P1** | #36: `attendance_rate_7d` com 0 treinos | Possível divisão por zero no SQL compute (verificar `NULLIF` ou `CASE WHEN`) |
| E03 | **P1** | #24: Anúncio deletado em tela aberta | Refresh pode retornar null sem tratamento |
| E04 | **P2** | #16: CRM empty state sem ícone/CTA | UX pobre — text solto |
| E05 | **P2** | #40: CSV com 0 linhas | Pode gerar arquivo vazio ou erro |
| E06 | **P2** | #22: Deletar tag com atletas atribuídos | Comportamento não definido |
