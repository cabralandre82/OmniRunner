# QA_PHASE_20.md — QA End-to-End de Gamificação (Phase 20)

> **Sprint:** 20.99.0
> **Data:** 2026-02-21
> **Status:** APROVADO

---

## 1. RESUMO

Auditoria completa de todos os sprints da Phase 20 (Gamification Progression Final).
Cada cenário verifica o fluxo ponta-a-ponta: backend → domain → BLoC → UI.

| Categoria | Testes | PASS | FAIL | Nota |
|---|:---:|:---:|:---:|---|
| Corrida válida → XP/level/streak | 8 | 8 | 0 | |
| Badges automáticos | 6 | 6 | 0 | |
| Rankings (3 escopos) | 7 | 7 | 0 | |
| Desafio Agora/Agendado + Ghost | 9 | 9 | 0 | |
| Pós-corrida resultado + pending/liberado | 6 | 6 | 0 | |
| Invalidado/disputa UX | 8 | 8 | 0 | |
| Feed assessoria | 5 | 5 | 0 | |
| Replay/Highlights | 5 | 5 | 0 | |
| Termos proibidos | 14 | 14 | 0 | |
| Análise estática | 4 | 4 | 0 | |
| **TOTAL** | **72** | **72** | **0** | |

---

## 2. CENÁRIO 1 — Corrida válida → XP/level/streak

| # | Teste | Componentes | Status |
|---|---|---|:---:|
| 1.1 | Edge Function `calculate-progression` registrada em config.toml | config.toml | PASS |
| 1.2 | `fn_mark_progression_applied` RPC impede XP duplicado por sessão | 20260226_progression_idempotency.sql | PASS |
| 1.3 | XP breakdown: base 20 + dist + dur + HR (caps diários 1000 XP, 10 sessões) | calculate-progression/index.ts | PASS |
| 1.4 | `fn_update_streak` com freeze logic | 20260226_progression_fields_views.sql | PASS |
| 1.5 | `v_user_progression` view calcula XP, level, streak, xp_to_next | 20260226_progression_fields_views.sql | PASS |
| 1.6 | `ProgressionBloc` busca dados via Supabase RPC | progression_bloc.dart | PASS |
| 1.7 | `ProgressionScreen` mostra 3 blocos: Nível+XP, Streak, Meta semanal | progression_screen.dart | PASS |
| 1.8 | Empty state: "Corra para começar a acumular XP" | progression_screen.dart | PASS |

---

## 3. CENÁRIO 2 — Badges automáticos → coleção

| # | Teste | Componentes | Status |
|---|---|---|:---:|
| 2.1 | Edge Function `evaluate-badges` registrada e funcional | evaluate-badges/index.ts, config.toml | PASS |
| 2.2 | 6 criteria types: count/distance/streak/weekly_distance/challenge_won/championship_completed/personal_record_pace | evaluate-badges/index.ts | PASS |
| 2.3 | Idempotência: badge não duplica (INSERT ON CONFLICT DO NOTHING) | evaluate-badges/index.ts | PASS |
| 2.4 | `BadgesScreen` seção "Desbloqueadas recentemente" (top 6) | badges_screen.dart | PASS |
| 2.5 | Cada badge mostra "Como ganhar" | badges_screen.dart | PASS |
| 2.6 | Empty state motivacional | badges_screen.dart | PASS |

---

## 4. CENÁRIO 3 — Rankings (assessoria/global/campeonato)

| # | Teste | Componentes | Status |
|---|---|---|:---:|
| 3.1 | Edge Function `compute-leaderboard` suporta 3 escopos | compute-leaderboard/index.ts | PASS |
| 3.2 | RPC `compute_leaderboard_global`, `_assessoria`, `_championship` existem | 20260227_leaderboard_v2.sql | PASS |
| 3.3 | RLS scope-aware: membro só vê assessoria própria | 20260227_leaderboard_v2.sql | PASS |
| 3.4 | `LeaderboardsScreen` com TabBar (Assessoria/Campeonato/Global) | leaderboards_screen.dart | PASS |
| 3.5 | Filtro Semana/Mês funcional (FilterChip) | leaderboards_screen.dart | PASS |
| 3.6 | Highlight "Você" no ranking do usuário | leaderboards_screen.dart | PASS |
| 3.7 | `ScoringExplanation` card visível | leaderboards_screen.dart | PASS |

---

## 5. CENÁRIO 4 — Desafio Agora/Agendado + Ghost Runner

| # | Teste | Componentes | Status |
|---|---|---|:---:|
| 4.1 | `ChallengeCreateScreen` 2 modos: Agora (chips 5/10/30min/1h/24h) e Agendado (date/time picker) | challenge_create_screen.dart | PASS |
| 4.2 | Regras de validação visíveis no card "Como funciona" | challenge_details_screen.dart | PASS |
| 4.3 | Accept/Decline card para convidados | challenge_details_screen.dart | PASS |
| 4.4 | `ChallengeGhostProvider` polls a cada 15s sem expor GPS | challenge_ghost_provider.dart | PASS |
| 4.5 | `ChallengeGhostOverlay` mostra "X m à frente/atrás" + barras dual | challenge_ghost_overlay.dart | PASS |
| 4.6 | Offline indicator com tooltip "Último sync há mais de 2 min" | challenge_ghost_overlay.dart | PASS |
| 4.7 | `SetChallengeContext` event + `TrackingActive` expanded fields | tracking_state.dart, tracking_bloc.dart | PASS |
| 4.8 | Mode tag (Imediato/Agendado) na lista de desafios | challenges_list_screen.dart | PASS |
| 4.9 | "Inscrição" (não "Taxa") para entry fee | challenge_create_screen.dart, challenge_details_screen.dart | PASS |

---

## 6. CENÁRIO 5 — Pós-corrida resultado + pending/liberado

| # | Teste | Componentes | Status |
|---|---|---|:---:|
| 5.1 | `ChallengeResultScreen` HeroSection com troféu/outcome contextual | challenge_result_screen.dart | PASS |
| 5.2 | Classificação com rank + nome + valor + OmniCoins | challenge_result_screen.dart | PASS |
| 5.3 | RewardCard "Recompensa liberada" / "Recompensa pendente" | challenge_result_screen.dart | PASS |
| 5.4 | CTAs: Desafiar novamente, Ver ranking, Compartilhar | challenge_result_screen.dart | PASS |
| 5.5 | `ChallengeSessionBanner` no RunSummaryScreen | challenge_session_banner.dart, run_summary_screen.dart | PASS |
| 5.6 | `_ClearingInfo` mostra `DisputeStatusCard` em challenges concluídos | challenge_details_screen.dart | PASS |

---

## 7. CENÁRIO 6 — Invalidado/disputa UX

| # | Teste | Componentes | Status |
|---|---|---|:---:|
| 6.1 | `InvalidatedRunCard` mapeia flags técnicos → razões amigáveis PT-BR | invalidated_run_card.dart | PASS |
| 6.2 | Headline "Não conseguimos validar esta atividade" (não acusatório) | invalidated_run_card.dart | PASS |
| 6.3 | CTAs: Tentar novamente, Enviar para revisão, Ver dicas de GPS | invalidated_run_card.dart | PASS |
| 6.4 | `GpsTipsSheet` com 6 dicas práticas | gps_tips_sheet.dart | PASS |
| 6.5 | TrackingScreen banner: "GPS instável — pode afetar a validação" | tracking_screen.dart | PASS |
| 6.6 | `DisputeStatusCard` 5 fases com textos empáticos | dispute_status_card.dart | PASS |
| 6.7 | `StaffDisputesScreen` com ações contextuais (confirmar/revisão) | staff_disputes_screen.dart | PASS |
| 6.8 | StaffDashboardScreen card "Confirmações" com badge de pendentes | staff_dashboard_screen.dart | PASS |

---

## 8. CENÁRIO 7 — Feed assessoria + Replay

| # | Teste | Componentes | Status |
|---|---|---|:---:|
| 7.1 | `assessoria_feed` table com RLS member-only | 20260228_assessoria_feed.sql | PASS |
| 7.2 | `fn_get_assessoria_feed` RPC paginado (cursor-based, max 50) | 20260228_assessoria_feed.sql | PASS |
| 7.3 | `AssessoriaFeedScreen` pull-to-refresh + infinite scroll | assessoria_feed_screen.dart | PASS |
| 7.4 | 7 event types com ícones/cores contextuais | assessoria_feed_screen.dart | PASS |
| 7.5 | Feed scoped ao grupo (sem feed global, sem cross-grupo) | assessoria_feed_screen.dart, RLS policies | PASS |
| 7.6 | `ReplayAnalyzer` km splits + sprint detection (últimos 40%, ≥200m) | replay_analyzer.dart | PASS |
| 7.7 | `RunReplayScreen` polyline animada + splits table + sprint card | run_replay_screen.dart | PASS |
| 7.8 | Botão "Replay da corrida" aparece com ≥10 pontos GPS | summary_metrics_panel.dart | PASS |
| 7.9 | Replay usa apenas dados locais (sem envio ao servidor) | run_replay_screen.dart | PASS |
| 7.10 | SummaryMetricsPanel labels traduzidos PT-BR | summary_metrics_panel.dart | PASS |

---

## 9. CENÁRIO 8 — Termos proibidos (GAMIFICATION_POLICY.md §5)

| # | Termo buscado | Escopo | Resultado | Status |
|---|---|---|---|:---:|
| 8.1 | aposta/bet/wager/gambling/lottery/jackpot/payout/staking | lib/ (dart) | 0 ocorrências | PASS |
| 8.2 | ganhar dinheiro/earn money/cash out/redeem/cash prize | lib/ (dart) | 0 ocorrências | PASS |
| 8.3 | buy coins/comprar moedas/trade coins | lib/ (dart) | 0 ocorrências | PASS |
| 8.4 | loot box/pay to win/prize pool | lib/ (dart) | 0 ocorrências | PASS |
| 8.5 | saldo (user-facing) | presentation/ (dart) | 0 ocorrências | PASS |
| 8.6 | carteira (user-facing) | presentation/ (dart) | 0 ocorrências | PASS |
| 8.7 | pagamento/payment | presentation/ (dart) | 0 ocorrências | PASS |
| 8.8 | Taxa (user-facing; deve ser "Inscrição") | presentation/ (dart) | 0 ocorrências | PASS |
| 8.9 | Token/Tokens (user-facing; deve ser "OmniCoins") | presentation/ (dart) | 0 ocorrências (code comments only) | PASS |
| 8.10 | fraude/cheat/hack (user-facing) | presentation/ (dart) | 0 ocorrências | PASS |
| 8.11 | "plataforma decide" | presentation/ (dart) | 0 ocorrências | PASS |
| 8.12 | dinheiro/money/deposit/withdraw | presentation/ (dart) | 0 ocorrências | PASS |
| 8.13 | nonce (user-facing) | presentation/ (dart) | 0 ocorrências | PASS |
| 8.14 | real money/dinheiro real | lib/ (dart) | 0 ocorrências | PASS |

---

## 10. CENÁRIO 9 — Análise estática

| # | Verificação | Resultado | Status |
|---|---|---|:---:|
| 9.1 | `flutter analyze` — 0 errors | 0 errors | PASS |
| 9.2 | `flutter analyze` — 0 new warnings | 1 pre-existing warning (dimmed param) | PASS |
| 9.3 | `flutter analyze` — info issues consistent | 57 info (stable, pre-existing pattern) | PASS |
| 9.4 | Nenhum `print()` em código de produção | Verified | PASS |

---

## 11. CORREÇÕES APLICADAS DURANTE QA

| # | Arquivo | Antes | Depois | Motivo |
|---|---|---|---|---|
| QA-FIX-01 | staff_dashboard_screen.dart | "Saldo OmniCoins" | "Seus OmniCoins" | Termo proibido "saldo" |
| QA-FIX-02 | progress_hub_screen.dart | "Saldo e movimentações" | "Créditos e movimentações" | Termo proibido "saldo" |
| QA-FIX-03 | athlete_dashboard_screen.dart | "Saldo OmniCoins" | "Seus OmniCoins" | Termo proibido "saldo" |
| QA-FIX-04 | challenges_bloc.dart | "Saldo insuficiente de OmniCoins." | "OmniCoins insuficientes para participar." | Termo proibido "saldo" |
| QA-FIX-05 | staff_generate_qr_screen.dart | "...na carteira" / "...da carteira" | "...receber OmniCoins" / "...devolver OmniCoins" | Termo proibido "carteira" |
| QA-FIX-06 | wallet_bloc.dart | "Erro ao carregar carteira" | "Erro ao carregar OmniCoins" | Termo proibido "carteira" |
| QA-FIX-07 | staff_scan_qr_screen.dart | "Tokens recebidos/devolvidos" | "OmniCoins recebidos/devolvidos" | Termo proibido "Token" |

---

## 12. SPRINTS PHASE 20 — STATUS FINAL

| Sprint | Descrição | Status |
|---|---|:---:|
| 20.1.0 | Travar Modelo de Progressão (Docs) | ✅ |
| 20.1.1 | Backend: profile_progress + views + RPCs | ✅ |
| 20.1.2 | Edge Function: calculate-progression | ✅ |
| 20.1.3 | UI: Progresso do Atleta | ✅ |
| 20.2.0 | Catálogo de Badges (Docs) | ✅ |
| 20.2.1 | Backend: evaluate-badges expandido | ✅ |
| 20.2.2 | UI: Tela de Badges | ✅ |
| 20.3.0 | Backend: Leaderboards v2 (3 escopos) | ✅ |
| 20.3.1 | UI: Rankings com Tabs + Filtros | ✅ |
| 20.4.0 | UX: Desafio Criar/Aceitar/Agendar | ✅ |
| 20.4.1 | Race Mode: Ghost Runner | ✅ |
| 20.4.2 | Pós-corrida: Resultado + CTAs | ✅ |
| 20.5.0 | Feed da Assessoria (social leve) | ✅ |
| 20.5.1 | Replays/Highlights | ✅ |
| 20.6.0 | UX: Corrida invalidada | ✅ |
| 20.6.1 | UX: Disputa do Desafio | ✅ |
| 20.99.0 | QA End-to-End (este documento) | ✅ |

---

## 13. CONCLUSÃO

**72 testes / 72 PASS / 0 FAIL**

A Phase 20 está completa e em conformidade com:
- GAMIFICATION_POLICY.md (§1-§10)
- DEFINITION_OF_DONE.md (D1-D7)
- Princípio "app para dummies" (UX clara, sem jargão técnico)
- PT-BR completo em todas as telas de gamificação
- Zero termos proibidos em texto visível ao usuário
- 7 correções de termos proibidos aplicadas durante QA

---

*Documento gerado no Sprint 20.99.0*
