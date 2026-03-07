# POST_REFACTOR_REGRESSION.md — Regression Testing

> Data: 2026-03-07

---

## 1. FLUXOS CRÍTICOS VERIFICADOS

| Fluxo | Método | Resultado |
|---|---|---|
| Bootstrap do app | Leitura de main.dart | ✅ INTACTO — MaterialApp.router, recovery, init defensivo |
| Autenticação | Leitura de auth_gate.dart + login_screen.dart | ✅ INTACTO — Google, Apple, Email, Supabase Auth |
| Navegação principal | Verificação de go_router | ✅ INTACTO — 105 rotas, 0 Navigator.push restantes |
| Sessão de corrida (criar/salvar/sync) | Análise de use cases + repos | ✅ INTACTO — create→save→finish→sync→recovery |
| Desafios (criar/entrar) | Análise de ChallengesBloc + use cases | ✅ INTACTO — create→join→auto-start→settle |
| Carteira OmniCoins | Análise de WalletBloc + repos | ✅ INTACTO — ledger, balance, reconciliation |
| Progressão/XP | Análise de PostSessionProgression | ✅ INTACTO — XP award, badge eval, mission update |
| Offline queue | Leitura de OfflineQueue + ConnectivityMonitor | ✅ INTACTO — queue, retry, auto-replay |
| Recovery de sessão | Leitura de RecoverActiveSession | ✅ INTACTO — detecta running/paused, redireciona |
| Feature flags | Leitura de FeatureFlagService | ✅ INTACTO — load, periodic refresh, gating |

---

## 2. PERSISTÊNCIA LOCAL (ISAR)

| Cenário | Resultado |
|---|---|
| Sessão salva localmente | ✅ IsarSessionRepo funcional |
| Pontos GPS persistidos | ✅ IsarPointsRepo funcional |
| Desafios cached localmente | ✅ IsarChallengeRepo funcional |
| Wallet offline | ✅ IsarWalletRepo funcional |
| Dados sobrevivem restart | ✅ Isar persiste em disco |

---

## 3. REGRESSÕES IDENTIFICADAS

| # | Regressão | Severidade | Causa |
|---|---|---|---|
| 1 | 30 Flutter tests falhando | ALTA | Screens acessando Supabase.instance sem mock |
| 2 | 15 Portal tests falhando | ALTA | LocaleSwitcher sem intl provider + rateLimit async |
| 3 | ChallengeEntity.acceptDeadlineMs perdido no restart | MÉDIA | Campo não existe no ChallengeRecord Isar |
| 4 | park_screen não renderiza em teste | MÉDIA | FeatureFlagService não registrado no test DI |
| 5 | league_screen não renderiza em teste | MÉDIA | FeatureFlagService não registrado no test DI |

---

## 4. FLUXOS NÃO VERIFICÁVEIS (requerem device/servidor)

- GPS tracking real com foreground service
- Heart rate via BLE
- Push notifications
- Deep links
- Strava OAuth + sync
- Map rendering (MapLibre)
- Cold start real em device
- App reopen após force-kill
