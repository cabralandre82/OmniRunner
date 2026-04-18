# FINDINGS — Índice Geral

> **Gerado automaticamente** por `tools/audit/build-registry.ts`. **Não editar à mão.**
> Atualizado em 2026-04-18 20:12:11 UTC.
>
> Fonte: `docs/audit/findings/*.md` — editar lá. Rodar `npx tsx tools/audit/build-registry.ts` para regenerar.

Total: **348** findings.

| Sev | Status | ID | Onda | Lente | Título | Owner |
|-----|--------|----|------|-------|--------|-------|
| 🟠 high | ⏳ fix-pending | [L01-01](./findings/L01-01-post-api-custody-webhook-webhook-de-custodia-stripe.md) | 1 | L01 · CISO | POST /api/custody/webhook — Webhook de custódia (Stripe + MercadoPago) | unassigned |
| 🔴 critical | ✅ fixed | [L01-02](./findings/L01-02-post-api-custody-withdraw-criacao-e-execucao-de.md) | 0 | L01 · CISO | POST /api/custody/withdraw — Criação e execução de saque em um único request | unassigned |
| 🔴 critical | ✅ fixed | [L01-03](./findings/L01-03-post-api-distribute-coins-distribuicao-de-coins-a.md) | 0 | L01 · CISO | POST /api/distribute-coins — Distribuição de coins a atleta | unassigned |
| 🟠 high | ✅ fixed | [L01-04](./findings/L01-04-post-api-custody-create-deposit-confirm-sem-idempotency.md) | 1 | L01 · CISO | POST /api/custody (create deposit / confirm) — Sem idempotency-key | platform |
| 🟡 medium | ⏳ fix-pending | [L01-05](./findings/L01-05-post-api-swap-criacao-aceite-cancelamento.md) | 2 | L01 · CISO | POST /api/swap — Criação/aceite/cancelamento | unassigned |
| 🟠 high | ⏳ fix-pending | [L01-06](./findings/L01-06-get-api-swap-get-api-clearing-get-api.md) | 1 | L01 · CISO | GET /api/swap, GET /api/clearing, GET /api/custody — Autorização por cookie | unassigned |
| 🟡 medium | ⏳ fix-pending | [L01-07](./findings/L01-07-get-api-health-information-disclosure.md) | 2 | L01 · CISO | GET /api/health — Information disclosure | unassigned |
| 🟢 safe | ✅ fixed | [L01-08](./findings/L01-08-get-api-liveness-ok.md) | 3 | L01 · CISO | GET /api/liveness — OK | unassigned |
| 🟠 high | ⏳ fix-pending | [L01-09](./findings/L01-09-post-api-checkout-gateway-proxy.md) | 1 | L01 · CISO | POST /api/checkout — Gateway proxy | unassigned |
| 🟡 medium | ⏳ fix-pending | [L01-10](./findings/L01-10-get-api-auth-callback-open-redirect-candidato.md) | 2 | L01 · CISO | GET /api/auth/callback — Open redirect candidato | unassigned |
| ⚪ na | ⏳ fix-pending | [L01-11](./findings/L01-11-post-api-workouts-assign-api-workouts-templates-autorizacao.md) | 3 | L01 · CISO | POST /api/workouts/assign, /api/workouts/templates — Autorização cross-athlete | unassigned |
| 🟢 safe | ✅ fixed | [L01-12](./findings/L01-12-post-api-verification-evaluate-ownership.md) | 3 | L01 · CISO | POST /api/verification/evaluate — Ownership | unassigned |
| 🟡 medium | 🚧 in-progress | [L01-13](./findings/L01-13-post-api-platform-fees-alteracao-de-taxas.md) | 2 | L01 · CISO | POST /api/platform/fees — Alteração de taxas | unassigned |
| 🟡 medium | ⏳ fix-pending | [L01-14](./findings/L01-14-sessao-supabase-auth-getsession-no-middleware-auth-getuser.md) | 2 | L01 · CISO | Sessão Supabase.auth.getSession() no middleware + auth.getUser() em updateSession | unassigned |
| 🟡 medium | ⏳ fix-pending | [L01-15](./findings/L01-15-jwt-expiry-window-logout-forcado.md) | 2 | L01 · CISO | JWT expiry window — Logout forçado | unassigned |
| ⚪ na | ⏳ fix-pending | [L01-16](./findings/L01-16-upload-de-documentos-cnh-comprovantes-de-liga.md) | 3 | L01 · CISO | Upload de documentos — CNH, comprovantes de liga | unassigned |
| 🔴 critical | ✅ fixed | [L01-17](./findings/L01-17-post-api-billing-asaas-armazenamento-de-api-key.md) | 0 | L01 · CISO | POST /api/billing/asaas — Armazenamento de API Key | unassigned |
| 🟠 high | ⏳ fix-pending | [L01-18](./findings/L01-18-asaas-webhook-supabase-functions-asaas-webhook-index-ts.md) | 1 | L01 · CISO | Asaas Webhook — supabase/functions/asaas-webhook/index.ts | unassigned |
| 🟡 medium | ⏳ fix-pending | [L01-19](./findings/L01-19-edge-functions-verify-jwt-false-com-auth-manual.md) | 2 | L01 · CISO | Edge Functions — verify_jwt = false com auth manual | unassigned |
| 🟢 safe | ✅ fixed | [L01-20](./findings/L01-20-checkratelimit-via-rpc-fail-closed.md) | 3 | L01 · CISO | checkRateLimit via RPC — Fail-closed | unassigned |
| 🟡 medium | ⏳ fix-pending | [L01-21](./findings/L01-21-ratelimit-no-portal-fail-open-para-memory.md) | 2 | L01 · CISO | rateLimit no portal — Fail-open para memory | unassigned |
| ⚪ na | ⏳ fix-pending | [L01-22](./findings/L01-22-get-terms-get-privacy-outras-rotas-publicas.md) | 3 | L01 · CISO | GET /terms, GET /privacy, outras rotas públicas | unassigned |
| ⚪ na | ⏳ fix-pending | [L01-23](./findings/L01-23-challenge-id-rota-publica.md) | 3 | L01 · CISO | /challenge/[id] — Rota pública | unassigned |
| ⚪ na | ⏳ fix-pending | [L01-24](./findings/L01-24-invite-code-rota-publica-de-aceite-de-convite.md) | 3 | L01 · CISO | /invite/[code] — Rota pública de aceite de convite | unassigned |
| 🟡 medium | ⏳ fix-pending | [L01-25](./findings/L01-25-middleware-public-prefixes-some-p-pathname-startswith-p.md) | 2 | L01 · CISO | Middleware — PUBLIC_PREFIXES.some(p => pathname.startsWith(p)) | unassigned |
| 🟡 medium | ⏳ fix-pending | [L01-26](./findings/L01-26-middleware-platform-role-check-sem-cache.md) | 2 | L01 · CISO | Middleware — platform role check sem cache | unassigned |
| 🟢 safe | ✅ fixed | [L01-27](./findings/L01-27-requireadminmaster-em-rotas-de-custody-service-client-sem.md) | 3 | L01 · CISO | requireAdminMaster em rotas de custody — Service client sem RLS | unassigned |
| 🟡 medium | ⏳ fix-pending | [L01-28](./findings/L01-28-deep-link-handler-extractinvitecode-aceita-qualquer-string.md) | 2 | L01 · CISO | Deep link handler — extractInviteCode aceita qualquer string | unassigned |
| 🟠 high | ⏳ fix-pending | [L01-29](./findings/L01-29-deep-link-strava-callback-sem-state-csrf.md) | 1 | L01 · CISO | Deep link — Strava callback sem state/CSRF | unassigned |
| 🟠 high | ⏳ fix-pending | [L01-30](./findings/L01-30-android-falta-de-proguard-r8.md) | 1 | L01 · CISO | Android — Falta de ProGuard/R8 | unassigned |
| 🟠 high | ⏳ fix-pending | [L01-31](./findings/L01-31-android-release-assina-com-debug-key-se-key.md) | 1 | L01 · CISO | Android — Release assina com debug key se key.properties não existir | unassigned |
| 🟡 medium | ⏳ fix-pending | [L01-32](./findings/L01-32-flutter-flutter-secure-storage-sem-setsharedpreferences.md) | 2 | L01 · CISO | Flutter — flutter_secure_storage sem setSharedPreferences | unassigned |
| 🟡 medium | ⏳ fix-pending | [L01-33](./findings/L01-33-flutter-db-key-storage-fallback-ausente.md) | 2 | L01 · CISO | Flutter — DB key storage fallback ausente | unassigned |
| 🟢 safe | ✅ fixed | [L01-34](./findings/L01-34-flutter-getorcreatekey-sha-256-ofuscacao-e-redundante.md) | 3 | L01 · CISO | Flutter — getOrCreateKey SHA-256 ofuscação é redundante | unassigned |
| 🟢 safe | ✅ fixed | [L01-35](./findings/L01-35-supabase-functions-delete-account-admin-master-nao-pode.md) | 3 | L01 · CISO | supabase/functions/delete-account — Admin master não pode se auto-deletar | unassigned |
| 🟠 high | ⏳ fix-pending | [L01-36](./findings/L01-36-delete-account-fn-delete-user-data-nao-aborta.md) | 1 | L01 · CISO | delete-account — fn_delete_user_data não-aborta no erro | unassigned |
| 🟢 safe | ✅ fixed | [L01-37](./findings/L01-37-set-user-role-aceita-so-strings-explicitas.md) | 3 | L01 · CISO | set-user-role — Aceita só strings explícitas | unassigned |
| 🟠 high | ⏳ fix-pending | [L01-38](./findings/L01-38-csp-unsafe-inline-unsafe-eval-em-script-src.md) | 1 | L01 · CISO | CSP 'unsafe-inline' + 'unsafe-eval' em script-src | unassigned |
| 🟡 medium | ⏳ fix-pending | [L01-39](./findings/L01-39-csp-style-src-unsafe-inline.md) | 2 | L01 · CISO | CSP — style-src 'unsafe-inline' | unassigned |
| 🟢 safe | ✅ fixed | [L01-40](./findings/L01-40-google-services-google-services-json-commitado.md) | 3 | L01 · CISO | Google services — google-services.json commitado | unassigned |
| 🟡 medium | ⏳ fix-pending | [L01-41](./findings/L01-41-coin-ledger-sem-assinatura-criptografica.md) | 2 | L01 · CISO | coin_ledger — Sem assinatura criptográfica | unassigned |
| 🟡 medium | ⏳ fix-pending | [L01-42](./findings/L01-42-platform-fee-config-rls-for-select-using-true.md) | 2 | L01 · CISO | platform_fee_config — RLS FOR SELECT USING (true) | unassigned |
| 🟡 medium | ⏳ fix-pending | [L01-43](./findings/L01-43-custody-accounts-rls-role-professor-nunca-corresponde.md) | 2 | L01 · CISO | custody_accounts RLS — role 'professor' nunca corresponde | unassigned |
| 🔴 critical | ✅ fixed | [L01-44](./findings/L01-44-migration-drift-platform-fee-config-fee-type-check.md) | 0 | L01 · CISO | Migration drift — platform_fee_config.fee_type CHECK + INSERT 'fx_spread' | unassigned |
| 🟠 high | ⏳ fix-pending | [L01-45](./findings/L01-45-fee-type-fx-spread-ausente-do-endpoint-admin.md) | 1 | L01 · CISO | fee_type — 'fx_spread' ausente do endpoint admin | unassigned |
| 🟢 safe | ✅ fixed | [L01-46](./findings/L01-46-execute-swap-locks-for-update-com-ordering.md) | 3 | L01 · CISO | execute_swap — Locks FOR UPDATE com ordering | unassigned |
| ⚪ na | ⏳ fix-pending | [L01-47](./findings/L01-47-executewithdrawal-execute-withdrawal-rpc-sem-codigo-mostrado.md) | 3 | L01 · CISO | executeWithdrawal — execute_withdrawal RPC sem código mostrado | unassigned |
| 🟢 safe | ✅ fixed | [L01-48](./findings/L01-48-aggregateclearingwindow-aggregation-only.md) | 3 | L01 · CISO | aggregateClearingWindow — Aggregation only | unassigned |
| 🟡 medium | ⏳ fix-pending | [L01-49](./findings/L01-49-processburnforclearing-audit-actor-id-system.md) | 2 | L01 · CISO | processBurnForClearing — Audit actor_id = "system" | unassigned |
| 🟡 medium | ⏳ fix-pending | [L01-50](./findings/L01-50-getswapordersforgroup-query-string-interpolation.md) | 2 | L01 · CISO | getSwapOrdersForGroup — Query string interpolation | unassigned |
| 🔴 critical | ✅ fixed | [L02-01](./findings/L02-01-distribute-coins-orquestracao-nao-atomica-entre-4-rpcs.md) | 0 | L02 · CTO | distribute-coins — Orquestração não-atômica entre 4 RPCs (partial-failure silencioso) | unassigned |
| 🔴 critical | ✅ fixed | [L02-02](./findings/L02-02-execute-burn-atomic-excecoes-engolidas-em-custody-release.md) | 0 | L02 · CTO | execute_burn_atomic — Exceções engolidas em custody_release_committed e settle_clearing | unassigned |
| 🟡 medium | ⏳ fix-pending | [L02-03](./findings/L02-03-execute-burn-atomic-function-language-plpgsql-sem-security.md) | 2 | L02 · CTO | execute_burn_atomic — Function LANGUAGE plpgsql sem SECURITY DEFINER vs. chamadas a funções SECURITY DEFINER | unassigned |
| 🟢 safe | ✅ fixed | [L02-04](./findings/L02-04-confirm-custody-deposit-for-update-upsert.md) | 3 | L02 · CTO | confirm_custody_deposit — FOR UPDATE + UPSERT | unassigned |
| 🟢 safe | ✅ fixed | [L02-05](./findings/L02-05-execute-swap-deadlock-prevention-via-uuid-ordering.md) | 3 | L02 · CTO | execute_swap — Deadlock prevention via UUID ordering | unassigned |
| 🟠 high | ⏳ fix-pending | [L02-06](./findings/L02-06-execute-withdrawal-estado-processing-sem-transicao-final.md) | 1 | L02 · CTO | execute_withdrawal — Estado 'processing' sem transição final | unassigned |
| 🟡 medium | ✅ fixed | [L02-07](./findings/L02-07-execute-swap-buyer-funding-nao-e-lockado-corretamente.md) | 1 | L02 · CTO | execute_swap — Buyer funding não é lockado corretamente | unassigned |
| 🟠 high | ⏳ fix-pending | [L02-08](./findings/L02-08-realtime-websocket-cross-tenant-leak.md) | 1 | L02 · CTO | Realtime / Websocket — Cross-tenant leak | unassigned |
| 🔴 critical | ⏳ fix-pending | [L02-09](./findings/L02-09-migration-drift-check-platform-fee-config-fee-type.md) | 1 | L02 · CTO | Migration drift — CHECK platform_fee_config.fee_type (duplica 1.44) | unassigned |
| 🟠 high | ⏳ fix-pending | [L02-10](./findings/L02-10-cold-start-timeout-vercel-em-operacoes-longas.md) | 1 | L02 · CTO | Cold start + timeout Vercel em operações longas | unassigned |
| 🟡 medium | ⏳ fix-pending | [L02-11](./findings/L02-11-pool-de-conexoes-createserviceclient-per-request.md) | 2 | L02 · CTO | Pool de conexões createServiceClient per-request | unassigned |
| 🟡 medium | ⏳ fix-pending | [L02-12](./findings/L02-12-zod-v4-upgrade-uuid-strict-validation.md) | 2 | L02 · CTO | Zod v4 upgrade — UUID strict validation | unassigned |
| ⚪ na | ⏳ fix-pending | [L02-13](./findings/L02-13-api-inngest-nao-existe-no-codigo.md) | 3 | L02 · CTO | /api/inngest — Não existe no código | unassigned |
| ⚪ na | ⏳ fix-pending | [L02-14](./findings/L02-14-pg-cron-jobs-lock-contention.md) | 3 | L02 · CTO | pg_cron jobs — Lock contention | unassigned |
| 🟡 medium | ⏳ fix-pending | [L02-15](./findings/L02-15-getredis-module-level-cache-vs-runtime-config.md) | 2 | L02 · CTO | getRedis() — Module-level cache vs runtime config | unassigned |
| 🔴 critical | ⏳ fix-pending | [L03-01](./findings/L03-01-divergencia-de-formula-de-fee-ts-vs-sql.md) | 1 | L03 · CFO | Divergência de fórmula de fee — TS vs SQL | unassigned |
| 🟠 high | ⏳ fix-pending | [L03-02](./findings/L03-02-congelamento-de-precos-taxas.md) | 1 | L03 · CFO | Congelamento de preços / taxas | unassigned |
| 🟠 high | ⏳ fix-pending | [L03-03](./findings/L03-03-execute-withdrawal-total-deposited-usd-amount-usd-nao.md) | 1 | L03 · CFO | execute_withdrawal — total_deposited_usd -= amount_usd não contabiliza fee do provider | unassigned |
| 🟢 safe | ✅ fixed | [L03-04](./findings/L03-04-1-coin-us-1-00-peg-enforcement.md) | 3 | L03 · CFO | 1 Coin = US$ 1.00 (peg enforcement) | unassigned |
| 🟢 safe | ✅ fixed | [L03-05](./findings/L03-05-gateway-fee-na-emissao-chk-gross-fee-net.md) | 3 | L03 · CFO | Gateway fee na emissão — chk_gross_fee_net | unassigned |
| 🟡 medium | ⏳ fix-pending | [L03-06](./findings/L03-06-fx-spread-calculo-simetrico-entrada-saida.md) | 2 | L03 · CFO | FX spread — Cálculo simétrico entrada/saída | unassigned |
| ⚪ na | ⏳ fix-pending | [L03-07](./findings/L03-07-cupom-100-pedido-de-0-00.md) | 3 | L03 · CFO | Cupom 100% / pedido de $0.00 | unassigned |
| 🟡 medium | ⏳ fix-pending | [L03-08](./findings/L03-08-custody-check-custody-invariants-valida-r-i-vs.md) | 2 | L03 · CFO | Custody check_custody_invariants — Valida R_i vs M_i mas não total_settled | unassigned |
| 🟠 high | ⏳ fix-pending | [L03-09](./findings/L03-09-platform-revenue-fee-type-check.md) | 1 | L03 · CFO | platform_revenue.fee_type CHECK | unassigned |
| 🟡 medium | ⏳ fix-pending | [L03-10](./findings/L03-10-custody-commit-coins-reserva-antes-de-credito-ao.md) | 2 | L03 · CFO | custody_commit_coins — Reserva ANTES de crédito ao atleta | unassigned |
| ⚪ na | ⏳ fix-pending | [L03-11](./findings/L03-11-pedido-de-r-0-via-cupom-100-duplica.md) | 3 | L03 · CFO | Pedido de R$ 0 via cupom 100% (duplica 3.7) | unassigned |
| 🟢 safe | ✅ fixed | [L03-12](./findings/L03-12-clearing-settlements-fees-concedidas-nulas.md) | 3 | L03 · CFO | clearing_settlements — Fees concedidas nulas | unassigned |
| 🔴 critical | ⏳ fix-pending | [L03-13](./findings/L03-13-reembolso-estorno-nao-ha-funcao-reverse-burn-ou.md) | 1 | L03 · CFO | Reembolso / Estorno — Não há função reverse_burn ou refund_deposit | unassigned |
| ⚪ na | ⏳ fix-pending | [L03-14](./findings/L03-14-cancelamento-apos-payment-confirmed.md) | 3 | L03 · CFO | Cancelamento após PAYMENT_CONFIRMED | unassigned |
| 🟡 medium | ⏳ fix-pending | [L03-15](./findings/L03-15-pedido-eternamente-pendente.md) | 2 | L03 · CFO | Pedido eternamente pendente | unassigned |
| 🟡 medium | ⏳ fix-pending | [L03-16](./findings/L03-16-consistencia-entrada-saida-de-fx.md) | 2 | L03 · CFO | Consistência entrada–saída de FX | unassigned |
| 🟠 high | ⏳ fix-pending | [L03-17](./findings/L03-17-arredondamento-ieee-754-em-typescript.md) | 1 | L03 · CFO | Arredondamento IEEE 754 em TypeScript | unassigned |
| 🟢 safe | ✅ fixed | [L03-18](./findings/L03-18-coin-ledger-delta-coins-tipo-integer.md) | 3 | L03 · CFO | coin_ledger.delta_coins — Tipo integer | unassigned |
| ⚪ na | ⏳ fix-pending | [L03-19](./findings/L03-19-nfs-e-fiscal-nao-observado.md) | 3 | L03 · CFO | NFS-e / fiscal — Não observado | unassigned |
| 🔴 critical | ⏳ fix-pending | [L03-20](./findings/L03-20-disputa-chargeback-stripe.md) | 1 | L03 · CFO | Disputa / chargeback Stripe | unassigned |
| 🔴 critical | ✅ fixed | [L04-01](./findings/L04-01-fn-delete-user-data-e-incompleta-multiplas-tabelas.md) | 0 | L04 · CLO | fn_delete_user_data é incompleta — múltiplas tabelas com PII não cobertas | unassigned |
| 🔴 critical | ⏳ fix-pending | [L04-02](./findings/L04-02-edge-function-delete-account-deleta-auth-users-mesmo.md) | 1 | L04 · CLO | Edge Function delete-account deleta auth.users mesmo quando fn_delete_user_data falha | unassigned |
| 🔴 critical | ✅ fixed | [L04-03](./findings/L04-03-nao-ha-registro-de-consentimento-opt-in-explicito.md) | 0 | L04 · CLO | Não há registro de consentimento (opt-in explícito LGPD Art. 8) | platform-privacy |
| 🔴 critical | ✅ fixed | [L04-04](./findings/L04-04-dados-de-saude-biometricos-dados-sensiveis-lgpd-art.md) | 0 | L04 · CLO | Dados de saúde/biométricos (dados sensíveis, LGPD Art. 11) sem proteção reforçada | unassigned |
| 🟠 high | ⏳ fix-pending | [L04-05](./findings/L04-05-trajetorias-gps-brutas-sem-opcao-de-privacy-zones.md) | 1 | L04 · CLO | Trajetórias GPS brutas sem opção de privacy zones (home/work zones) | unassigned |
| 🟠 high | ⏳ fix-pending | [L04-06](./findings/L04-06-campo-instagram-handle-tiktok-handle-em-profiles-sem.md) | 1 | L04 · CLO | Campo instagram_handle, tiktok_handle em profiles sem política de uso | unassigned |
| 🟠 high | ⏳ fix-pending | [L04-07](./findings/L04-07-coin-ledger-retem-reason-com-pii-embutida.md) | 1 | L04 · CLO | coin_ledger retém reason com PII embutida | unassigned |
| 🟠 high | ⏳ fix-pending | [L04-08](./findings/L04-08-backups-supabase-sem-politica-de-retencao-documentada.md) | 1 | L04 · CLO | Backups Supabase — sem política de retenção documentada | unassigned |
| 🟠 high | ⏳ fix-pending | [L04-09](./findings/L04-09-terceiros-strava-trainingpeaks-nao-ha-processo-de-revogacao.md) | 1 | L04 · CLO | Terceiros (Strava, TrainingPeaks) — não há processo de revogação | unassigned |
| 🟠 high | ⏳ fix-pending | [L04-10](./findings/L04-10-transferencia-internacional-de-dados-supabase-us-sentry-us.md) | 1 | L04 · CLO | Transferência internacional de dados (Supabase US, Sentry US) sem cláusulas | unassigned |
| 🟡 medium | ⏳ fix-pending | [L04-11](./findings/L04-11-nao-ha-dpo-nomeado-canal-de-titular-publicado.md) | 2 | L04 · CLO | Não há DPO nomeado / canal de titular publicado | unassigned |
| 🟡 medium | ⏳ fix-pending | [L04-12](./findings/L04-12-portal-admin-expoe-dados-sensiveis-sem-masking.md) | 2 | L04 · CLO | Portal admin expõe dados sensíveis sem masking | unassigned |
| 🟡 medium | ⏳ fix-pending | [L04-13](./findings/L04-13-logs-estruturados-enviam-user-id-e-podem-enviar.md) | 2 | L04 · CLO | Logs estruturados enviam user_id e podem enviar ip_address ao Sentry | unassigned |
| 🟡 medium | ⏳ fix-pending | [L04-14](./findings/L04-14-ausencia-de-verificacao-de-idade-coppa-eca.md) | 2 | L04 · CLO | Ausência de verificação de idade (COPPA/ECA) | unassigned |
| 🟡 medium | ⏳ fix-pending | [L04-15](./findings/L04-15-right-to-portability-nao-ha-export-self-service.md) | 2 | L04 · CLO | Right to portability — não há export self-service | unassigned |
| 🔴 critical | ✅ fixed | [L05-01](./findings/L05-01-swap-race-entre-accept-e-cancel-do-dono.md) | 0 | L05 · CPO | Swap: race entre accept e cancel do dono da oferta | unassigned |
| 🔴 critical | ✅ fixed | [L05-02](./findings/L05-02-swap-nao-tem-ttl-expiracao-ofertas-ficam-para.md) | 1 | L05 · CPO | Swap não tem TTL/expiração — ofertas ficam para sempre | unassigned |
| 🔴 critical | ⏳ fix-pending | [L05-03](./findings/L05-03-post-api-distribute-coins-amount-max-1000-conflita.md) | 1 | L05 · CPO | POST /api/distribute-coins: amount max 1000 — conflita com grandes clubes | unassigned |
| 🟠 high | ⏳ fix-pending | [L05-04](./findings/L05-04-challenge-championship-participante-pode-retirar-se-withdraw.md) | 1 | L05 · CPO | Challenge/Championship: participante pode retirar-se (withdraw) durante disputa — sem regra de cutoff | unassigned |
| 🟠 high | ⏳ fix-pending | [L05-05](./findings/L05-05-challenge-ganhador-de-zero-participantes.md) | 1 | L05 · CPO | Challenge: ganhador de zero participantes | unassigned |
| 🟠 high | ⏳ fix-pending | [L05-06](./findings/L05-06-championship-champ-cancel-refund-de-badges-parcial-e.md) | 1 | L05 · CPO | Championship champ-cancel: refund de badges parcial e silencioso | unassigned |
| 🟠 high | ⏳ fix-pending | [L05-07](./findings/L05-07-swap-amount-minimo-us-100-inviabiliza-grupos-pequenos.md) | 1 | L05 · CPO | Swap: amount mínimo US$ 100 inviabiliza grupos pequenos | unassigned |
| 🟠 high | ⏳ fix-pending | [L05-08](./findings/L05-08-withdraw-nenhuma-tela-de-progresso-para-pending-processing.md) | 1 | L05 · CPO | Withdraw: nenhuma tela de progresso para pending→processing→completed | unassigned |
| 🟠 high | ⏳ fix-pending | [L05-09](./findings/L05-09-deposit-custody-deposits-sem-cap-diario-antifraude.md) | 1 | L05 · CPO | Deposit custody_deposits — sem cap diário antifraude | unassigned |
| 🟡 medium | ⏳ fix-pending | [L05-10](./findings/L05-10-swap-offers-visivel-para-todos-os-grupos-sem.md) | 2 | L05 · CPO | Swap offers: visível para todos os grupos, sem filtro de contraparte | unassigned |
| 🟡 medium | ⏳ fix-pending | [L05-11](./findings/L05-11-ui-distribute-coins-sem-confirmacao-dupla-de-grandes.md) | 2 | L05 · CPO | UI distribute-coins: sem confirmação dupla de grandes valores | unassigned |
| 🟡 medium | ⏳ fix-pending | [L05-12](./findings/L05-12-challenges-sem-regras-de-tie-break.md) | 2 | L05 · CPO | Challenges sem regras de tie-break | unassigned |
| 🟡 medium | ⏳ fix-pending | [L05-13](./findings/L05-13-mobile-corrida-sem-gps-salvo-como-0-km.md) | 2 | L05 · CPO | Mobile: corrida sem GPS salvo como 0 km não invalidada | unassigned |
| 🟡 medium | ⏳ fix-pending | [L05-14](./findings/L05-14-feed-social-sem-report-moderacao.md) | 2 | L05 · CPO | Feed social: sem "report" / moderação | unassigned |
| 🟡 medium | ⏳ fix-pending | [L05-15](./findings/L05-15-mobile-logout-nao-revoga-tokens-strava-trainingpeaks.md) | 2 | L05 · CPO | Mobile: logout não revoga tokens Strava/TrainingPeaks | unassigned |
| 🟡 medium | ⏳ fix-pending | [L05-16](./findings/L05-16-workout-delivery-sem-reagendamento-do-atleta.md) | 2 | L05 · CPO | Workout delivery: sem reagendamento do atleta | unassigned |
| 🟡 medium | ⏳ fix-pending | [L05-17](./findings/L05-17-gamificacao-badges-permanentes-sem-prazo.md) | 2 | L05 · CPO | Gamificação: badges permanentes sem prazo | unassigned |
| 🟡 medium | ⏳ fix-pending | [L05-18](./findings/L05-18-moeda-fica-em-wallet-do-atleta-que-saiu.md) | 2 | L05 · CPO | Moeda fica em wallet do atleta que saiu do grupo | unassigned |
| 🟡 medium | ⏳ fix-pending | [L05-19](./findings/L05-19-offline-first-flutter-sessoes-ficam-em-drift-ate.md) | 2 | L05 · CPO | Offline-first Flutter: sessões ficam em drift até sincronizar | unassigned |
| 🟢 safe | ✅ fixed | [L05-20](./findings/L05-20-delete-account-bloqueia-admin-master-boa-pratica.md) | 3 | L05 · CPO | delete-account bloqueia admin_master (boa prática) | unassigned |
| 🔴 critical | ✅ fixed | [L06-01](./findings/L06-01-zero-runbook-financeiro-custodia-clearing-swap-withdraw.md) | 1 | L06 · COO | Zero runbook financeiro — custódia, clearing, swap, withdraw | unassigned |
| 🔴 critical | ⏳ fix-pending | [L06-02](./findings/L06-02-health-check-exibe-contagem-exata-de-violacoes-info.md) | 1 | L06 · COO | Health check exibe contagem exata de violações (info leak operacional) | unassigned |
| 🟠 high | ⏳ fix-pending | [L06-03](./findings/L06-03-reconcile-wallets-cron-sem-alerta-em-drift-0.md) | 1 | L06 · COO | reconcile-wallets-cron sem alerta em drift > 0 | unassigned |
| 🟠 high | ⏳ fix-pending | [L06-04](./findings/L06-04-pg-cron-jobs-sem-monitoramento-de-execucao.md) | 1 | L06 · COO | pg_cron jobs sem monitoramento de execução | unassigned |
| 🟠 high | ⏳ fix-pending | [L06-05](./findings/L06-05-edge-functions-sem-retry-em-falha-de-pg.md) | 1 | L06 · COO | Edge Functions sem retry em falha de pg_net | unassigned |
| 🟠 high | ✅ fixed | [L06-06](./findings/L06-06-sem-feature-flags-para-desligar-subsistemas.md) | 1 | L06 · COO | Sem feature flags para desligar subsistemas | unassigned |
| 🟠 high | ⏳ fix-pending | [L06-07](./findings/L06-07-global-error-do-next-js-nao-reporta-a.md) | 1 | L06 · COO | Global error do Next.js não reporta a Sentry | unassigned |
| 🟠 high | ⏳ fix-pending | [L06-08](./findings/L06-08-delete-account-executa-deleteuser-sem-audit-log.md) | 1 | L06 · COO | delete-account executa deleteUser sem audit_log | unassigned |
| 🟡 medium | ⏳ fix-pending | [L06-09](./findings/L06-09-metricas-portal-src-lib-metrics-ts-so-geram.md) | 2 | L06 · COO | Métricas (portal/src/lib/metrics.ts) só geram log JSON, sem exporter real | unassigned |
| 🟡 medium | ⏳ fix-pending | [L06-10](./findings/L06-10-nao-ha-slo-documentado.md) | 2 | L06 · COO | Não há SLO documentado | unassigned |
| 🟡 medium | ⏳ fix-pending | [L06-11](./findings/L06-11-secret-rotation-sem-playbook.md) | 2 | L06 · COO | Secret rotation sem playbook | unassigned |
| 🟡 medium | ⏳ fix-pending | [L06-12](./findings/L06-12-api-liveness-trivial-mas-api-readiness-inexistente.md) | 2 | L06 · COO | /api/liveness trivial mas /api/readiness inexistente | unassigned |
| 🟡 medium | ⏳ fix-pending | [L06-13](./findings/L06-13-logs-estruturados-sem-request-id-propagado-do-portal.md) | 2 | L06 · COO | Logs estruturados sem request_id propagado do portal | unassigned |
| 🔴 critical | ⏳ fix-pending | [L07-01](./findings/L07-01-mensagens-de-erro-em-portugues-hardcoded-no-backend.md) | 1 | L07 · CXO | Mensagens de erro em português hardcoded no backend | unassigned |
| 🔴 critical | ⏳ fix-pending | [L07-02](./findings/L07-02-onboarding-nao-distingue-papeis-atleta-coach-admin-master.md) | 1 | L07 · CXO | Onboarding não distingue papéis (atleta, coach, admin_master) | unassigned |
| 🟠 high | ⏳ fix-pending | [L07-03](./findings/L07-03-app-mobile-sem-modo-offline-robusto-para-corridas.md) | 1 | L07 · CXO | App mobile sem modo offline robusto para corridas | unassigned |
| 🟠 high | ⏳ fix-pending | [L07-04](./findings/L07-04-flutter-deep-link-strava-oauth-sem-state-validation.md) | 1 | L07 · CXO | Flutter deep link Strava OAuth sem state validation (CSRF) | unassigned |
| 🟠 high | ⏳ fix-pending | [L07-05](./findings/L07-05-portal-sem-acessibilidade-a11y-declarada.md) | 1 | L07 · CXO | Portal sem acessibilidade (a11y) declarada | unassigned |
| 🟠 high | ⏳ fix-pending | [L07-06](./findings/L07-06-timezone-sem-configuracao-do-usuario.md) | 1 | L07 · CXO | Timezone sem configuração do usuário | unassigned |
| 🟡 medium | ⏳ fix-pending | [L07-07](./findings/L07-07-icones-sem-fallback-mobile-offline.md) | 2 | L07 · CXO | Ícones sem fallback (mobile offline) | unassigned |
| 🟡 medium | ⏳ fix-pending | [L07-08](./findings/L07-08-dark-mode-parcial.md) | 2 | L07 · CXO | Dark mode parcial | unassigned |
| 🟡 medium | ⏳ fix-pending | [L07-09](./findings/L07-09-notificacoes-push-sem-deep-link-preciso.md) | 2 | L07 · CXO | Notificações push: sem deep link preciso | unassigned |
| 🟡 medium | ⏳ fix-pending | [L07-10](./findings/L07-10-empty-states-genericos.md) | 2 | L07 · CXO | Empty states genéricos | unassigned |
| 🟡 medium | ⏳ fix-pending | [L07-11](./findings/L07-11-loading-states-inconsistentes.md) | 2 | L07 · CXO | Loading states inconsistentes | unassigned |
| 🟡 medium | ⏳ fix-pending | [L07-12](./findings/L07-12-copy-financeiro-confunde-atleta.md) | 2 | L07 · CXO | Copy financeiro confunde atleta | unassigned |
| 🟡 medium | ⏳ fix-pending | [L07-13](./findings/L07-13-confirmacoes-destrutivas-sem-confirm-dialog.md) | 2 | L07 · CXO | Confirmações destrutivas sem confirm dialog | unassigned |
| 🔴 critical | ⏳ fix-pending | [L08-01](./findings/L08-01-producteventtracker-trackonce-tem-race-toctou.md) | 1 | L08 · CDO | ProductEventTracker.trackOnce tem race TOCTOU | unassigned |
| 🔴 critical | ⏳ fix-pending | [L08-02](./findings/L08-02-product-events-properties-jsonb-aceita-qualquer-payload-pii.md) | 1 | L08 · CDO | product_events.properties jsonb aceita qualquer payload — PII leak risk | unassigned |
| 🟠 high | ⏳ fix-pending | [L08-03](./findings/L08-03-sem-indice-de-analytics-time-series-em-sessions.md) | 1 | L08 · CDO | Sem índice de analytics time-series em sessions | unassigned |
| 🟠 high | ⏳ fix-pending | [L08-04](./findings/L08-04-analise-de-sessions-pelo-moving-ms-mas-coluna.md) | 1 | L08 · CDO | Análise de sessions pelo moving_ms mas coluna aceita NULL e 0 | unassigned |
| 🟠 high | ⏳ fix-pending | [L08-05](./findings/L08-05-views-de-progressao-sem-filtro-de-atletas-inativos.md) | 1 | L08 · CDO | Views de progressão sem filtro de atletas inativos | unassigned |
| 🟠 high | ⏳ fix-pending | [L08-06](./findings/L08-06-sem-staging-de-data-warehouse-queries-olap-contra.md) | 1 | L08 · CDO | Sem staging de data warehouse — queries OLAP contra OLTP | unassigned |
| 🟠 high | ⏳ fix-pending | [L08-07](./findings/L08-07-drift-potencial-entre-coin-ledger-e-wallets-fora.md) | 1 | L08 · CDO | Drift potencial entre coin_ledger e wallets fora do horário do cron | unassigned |
| 🟠 high | ⏳ fix-pending | [L08-08](./findings/L08-08-audit-logs-sem-retencao-particionamento.md) | 1 | L08 · CDO | audit_logs sem retenção / particionamento | unassigned |
| 🟡 medium | ⏳ fix-pending | [L08-09](./findings/L08-09-event-schema-sem-registry-contract.md) | 2 | L08 · CDO | Event schema sem registry / contract | unassigned |
| 🟡 medium | ⏳ fix-pending | [L08-10](./findings/L08-10-sem-cohort-analysis-estruturada.md) | 2 | L08 · CDO | Sem cohort analysis estruturada | unassigned |
| 🟡 medium | ⏳ fix-pending | [L08-11](./findings/L08-11-feature-flags-quando-6-6-implementar-precisam-de.md) | 2 | L08 · CDO | Feature flags (quando [6.6] implementar) precisam de metrics | unassigned |
| 🟡 medium | ⏳ fix-pending | [L08-12](./findings/L08-12-mobile-analytics-nao-enviados-quando-offline.md) | 2 | L08 · CDO | Mobile: analytics não enviados quando offline | unassigned |
| 🔴 critical | ⏳ fix-pending | [L09-01](./findings/L09-01-modelo-de-coin-us-1-pode-ser-classificado.md) | 1 | L09 · CRO | Modelo de "Coin = US$ 1" pode ser classificado como arranjo de pagamento (BCB Circ. 3.885/2018) | unassigned |
| 🔴 critical | ⏳ fix-pending | [L09-02](./findings/L09-02-ausencia-de-kyc-aml-para-grupos-com-custodia.md) | 1 | L09 · CRO | Ausência de KYC/AML para grupos com custódia | unassigned |
| 🔴 critical | ⏳ fix-pending | [L09-03](./findings/L09-03-relatorio-de-operacoes-sos-coaf-inexistente.md) | 1 | L09 · CRO | Relatório de Operações (SOS COAF) inexistente | unassigned |
| 🔴 critical | ✅ fixed | [L09-04](./findings/L09-04-nota-fiscal-recibo-fiscal-nao-emitida-em-withdrawals.md) | 0 | L09 · CRO | Nota fiscal / recibo fiscal não emitida em withdrawals | unassigned |
| 🔴 critical | ⏳ fix-pending | [L09-05](./findings/L09-05-iof-nao-recolhido-em-swap-inter-cliente.md) | 1 | L09 · CRO | IOF não recolhido em swap inter-cliente | unassigned |
| 🟠 high | ⏳ fix-pending | [L09-06](./findings/L09-06-gateway-de-pagamento-asaas-chave-armazenada-em-plaintext.md) | 1 | L09 · CRO | Gateway de pagamento Asaas: chave armazenada em plaintext na DB | unassigned |
| 🟠 high | ⏳ fix-pending | [L09-07](./findings/L09-07-politica-de-reembolso-chargeback-sem-prazo-sla.md) | 1 | L09 · CRO | Política de reembolso/chargeback sem prazo SLA | unassigned |
| 🟠 high | ⏳ fix-pending | [L09-08](./findings/L09-08-provider-fee-usd-2-12-onus-ao-cliente.md) | 1 | L09 · CRO | provider_fee_usd ([2.12]) — ônus ao cliente ou à plataforma? | unassigned |
| 🟠 high | ⏳ fix-pending | [L09-09](./findings/L09-09-contratos-privados-termo-de-adesao-do-clube-termo.md) | 1 | L09 · CRO | Contratos privados (termo de adesão do clube, termo de atleta) inexistentes no repo | unassigned |
| 🟡 medium | ⏳ fix-pending | [L09-10](./findings/L09-10-relatorio-anual-de-transparencia-marco-civil-art-11.md) | 2 | L09 · CRO | Relatório anual de transparência (Marco Civil Art. 11) | unassigned |
| 🟡 medium | ⏳ fix-pending | [L09-11](./findings/L09-11-cessao-de-credito-implicita-em-clearing-settlements-document.md) | 2 | L09 · CRO | Cessão de crédito implícita em clearing_settlements — documentar | unassigned |
| 🟡 medium | ⏳ fix-pending | [L09-12](./findings/L09-12-auditoria-externa-financeira-inexistente.md) | 2 | L09 · CRO | Auditoria externa financeira — inexistente | unassigned |
| 🔴 critical | ⏳ fix-pending | [L10-01](./findings/L10-01-nenhum-bug-bounty-disclosure-policy.md) | 1 | L10 · CSO | Nenhum bug bounty / disclosure policy | unassigned |
| 🔴 critical | ⏳ fix-pending | [L10-02](./findings/L10-02-threat-model-formal-nao-documentado.md) | 1 | L10 · CSO | Threat model formal não documentado | unassigned |
| 🔴 critical | ⏳ fix-pending | [L10-03](./findings/L10-03-service-role-key-distribuida-amplamente.md) | 1 | L10 · CSO | Service-role key distribuída amplamente | unassigned |
| 🟠 high | ⏳ fix-pending | [L10-04](./findings/L10-04-sem-waf-explicito.md) | 1 | L10 · CSO | Sem WAF explícito | unassigned |
| 🟠 high | ⏳ fix-pending | [L10-05](./findings/L10-05-csp-hardened-1-31-mas-sem-report-uri.md) | 1 | L10 · CSO | CSP hardened ([1.31]) mas sem report-uri | unassigned |
| 🟠 high | ⏳ fix-pending | [L10-06](./findings/L10-06-segregacao-de-funcao-sod-ausente-em-platform-admin.md) | 1 | L10 · CSO | Segregação de função (SoD) ausente em platform_admin | unassigned |
| 🟠 high | ⏳ fix-pending | [L10-07](./findings/L10-07-zero-trust-entre-microservicos-edge-functions-confiam-no.md) | 1 | L10 · CSO | Zero-trust entre microserviços — Edge Functions confiam no JWT sem validar audience | unassigned |
| 🟠 high | ⏳ fix-pending | [L10-08](./findings/L10-08-logs-de-acesso-sensiveis-sem-imutabilidade.md) | 1 | L10 · CSO | Logs de acesso sensíveis sem imutabilidade | unassigned |
| 🟠 high | ⏳ fix-pending | [L10-09](./findings/L10-09-falta-defesa-anti-credential-stuffing-no-mobile-portal.md) | 1 | L10 · CSO | Falta defesa anti credential stuffing no Mobile/Portal | unassigned |
| 🟡 medium | ⏳ fix-pending | [L10-10](./findings/L10-10-nao-ha-pentest-externo-documentado.md) | 2 | L10 · CSO | Não há pentest externo documentado | unassigned |
| 🟡 medium | ⏳ fix-pending | [L10-11](./findings/L10-11-sem-inventario-de-chaves-de-api-terceiros.md) | 2 | L10 · CSO | Sem inventário de chaves de API terceiros | unassigned |
| 🟡 medium | ⏳ fix-pending | [L10-12](./findings/L10-12-csrf-no-portal-confiando-apenas-em-samesite-lax.md) | 2 | L10 · CSO | CSRF no portal confiando apenas em SameSite=Lax | unassigned |
| 🟡 medium | ⏳ fix-pending | [L10-13](./findings/L10-13-sem-dpi-device-posture-no-flutter.md) | 2 | L10 · CSO | Sem DPI (Device Posture) no Flutter | unassigned |
| 🟡 medium | ⏳ fix-pending | [L10-14](./findings/L10-14-jwts-sem-rotacao-de-refresh-token.md) | 2 | L10 · CSO | JWTs sem rotação de refresh_token | unassigned |
| 🔴 critical | ✅ fixed | [L11-01](./findings/L11-01-ci-sem-npm-audit-flutter-pub-audit.md) | 1 | L11 · Supply Chain | CI sem npm audit / flutter pub audit | unassigned |
| 🔴 critical | ✅ fixed | [L11-02](./findings/L11-02-sem-sbom-software-bill-of-materials.md) | 1 | L11 · Supply Chain | Sem SBOM (Software Bill of Materials) | unassigned |
| 🔴 critical | ✅ fixed | [L11-03](./findings/L11-03-sem-gitleaks-trufflehog-no-ci.md) | 1 | L11 · Supply Chain | Sem gitleaks / trufflehog no CI | unassigned |
| 🟠 high | ✅ fixed | [L11-04](./findings/L11-04-dependabot-agrupa-todas-as-minor-patch-pr-monstro.md) | 1 | L11 · Supply Chain | Dependabot agrupa todas as minor+patch — PR monstro | unassigned |
| 🟠 high | ⏳ fix-pending | [L11-05](./findings/L11-05-flutter-secure-storage-10-0-0-mas-release.md) | 1 | L11 · Supply Chain | flutter_secure_storage: ^10.0.0 mas release inclui shared_preferences | unassigned |
| 🟠 high | ⏳ fix-pending | [L11-06](./findings/L11-06-dependencias-com-permitem-breaking-minor.md) | 1 | L11 · Supply Chain | Dependências com ^ permitem breaking minor | unassigned |
| 🟠 high | ⏳ fix-pending | [L11-07](./findings/L11-07-sqlcipher-flutter-libs-0-7-0-eol-eol.md) | 1 | L11 · Supply Chain | sqlcipher_flutter_libs: ^0.7.0+eol — "eol" = end of life | unassigned |
| 🟠 high | ⏳ fix-pending | [L11-08](./findings/L11-08-flutter-sdk-3-8-0-4-0-0.md) | 1 | L11 · Supply Chain | Flutter sdk: '>=3.8.0 <4.0.0' — permite 3.9, 3.10… | unassigned |
| 🟡 medium | ⏳ fix-pending | [L11-09](./findings/L11-09-github-actions-sem-oidc-para-deploys.md) | 2 | L11 · Supply Chain | GitHub Actions sem OIDC para deploys | unassigned |
| 🟡 medium | ⏳ fix-pending | [L11-10](./findings/L11-10-actions-checkout-v4-sha-nao-pinned.md) | 2 | L11 · Supply Chain | actions/checkout@v4 SHA não pinned | unassigned |
| 🟡 medium | ⏳ fix-pending | [L11-11](./findings/L11-11-sem-renovate-como-alternativa.md) | 2 | L11 · Supply Chain | Sem Renovate como alternativa | unassigned |
| 🟡 medium | ⏳ fix-pending | [L11-12](./findings/L11-12-npm-ci-sem-ignore-scripts.md) | 2 | L11 · Supply Chain | npm ci sem --ignore-scripts | unassigned |
| 🟡 medium | ⏳ fix-pending | [L11-13](./findings/L11-13-lockfile-drift-nao-validado.md) | 2 | L11 · Supply Chain | Lockfile drift não validado | unassigned |
| 🟡 medium | ⏳ fix-pending | [L11-14](./findings/L11-14-omni-runner-pubspec-lock-commitado.md) | 2 | L11 · Supply Chain | omni_runner/pubspec.lock commitado? | unassigned |
| 🔴 critical | ⏳ fix-pending | [L12-01](./findings/L12-01-reconcile-wallets-cron-existe-mas-nao-esta-agendado.md) | 1 | L12 · Cron/Scheduler | reconcile-wallets-cron existe mas NÃO está agendado | unassigned |
| 🔴 critical | ⏳ fix-pending | [L12-02](./findings/L12-02-thundering-herd-em-02-00-04-00-utc.md) | 1 | L12 · Cron/Scheduler | Thundering herd em 02:00–04:00 UTC | unassigned |
| 🔴 critical | ⏳ fix-pending | [L12-03](./findings/L12-03-5-crons-sem-lock-overlap-risk.md) | 1 | L12 · Cron/Scheduler | */5 * * * * crons sem lock — overlap risk | unassigned |
| 🟠 high | ⏳ fix-pending | [L12-04](./findings/L12-04-pg-cron-nao-monitora-sla-de-execucao.md) | 1 | L12 · Cron/Scheduler | pg_cron não monitora SLA de execução | unassigned |
| 🟠 high | ⏳ fix-pending | [L12-05](./findings/L12-05-auto-topup-hourly-cobranca-automatica-sem-cap-diario.md) | 1 | L12 · Cron/Scheduler | auto-topup-hourly — cobrança automática sem cap diário | unassigned |
| 🟠 high | ⏳ fix-pending | [L12-06](./findings/L12-06-archive-old-sessions-roda-como-funcao-pesada-sem.md) | 1 | L12 · Cron/Scheduler | archive-old-sessions roda como função pesada sem batch | unassigned |
| 🟠 high | ⏳ fix-pending | [L12-07](./findings/L12-07-horario-utc-usuarios-br-veem-meia-noite-brasil.md) | 1 | L12 · Cron/Scheduler | Horário UTC → usuários BR veem "meia-noite Brasil" | unassigned |
| 🟠 high | ⏳ fix-pending | [L12-08](./findings/L12-08-clearing-cron-em-02-00-consolidacao-de-d.md) | 1 | L12 · Cron/Scheduler | clearing-cron em 02:00 — consolidação de D-1 antes de fim do dia | unassigned |
| 🟠 high | ⏳ fix-pending | [L12-09](./findings/L12-09-lifecycle-cron-dispara-notificacoes-idempotencia-nao-garanti.md) | 1 | L12 · Cron/Scheduler | lifecycle-cron dispara notificações idempotência não garantida | unassigned |
| 🟡 medium | ⏳ fix-pending | [L12-10](./findings/L12-10-jobs-pg-cron-executam-como-superuser-padrao.md) | 2 | L12 · Cron/Scheduler | Jobs pg_cron executam como superuser (padrão) | unassigned |
| 🟡 medium | ⏳ fix-pending | [L12-11](./findings/L12-11-cron-schedule-em-migration-duplicada-corre-risco.md) | 2 | L12 · Cron/Scheduler | cron.schedule em migration duplicada corre risco | unassigned |
| 🟡 medium | ⏳ fix-pending | [L12-12](./findings/L12-12-timezone-do-cron-utc-ok-mas-horario-dst.md) | 2 | L12 · Cron/Scheduler | Timezone do cron = UTC ok, mas horário DST? | unassigned |
| 🔴 critical | ⏳ fix-pending | [L13-01](./findings/L13-01-admin-only-routes-admin-professor-routes-ordem-importa.md) | 1 | L13 · Middleware | ADMIN_ONLY_ROUTES + ADMIN_PROFESSOR_ROUTES — ordem importa, e está errada | unassigned |
| 🔴 critical | ⏳ fix-pending | [L13-02](./findings/L13-02-nome-da-constante-ainda-em-portugues-admin-professor.md) | 1 | L13 · Middleware | Nome da constante ainda em português (ADMIN_PROFESSOR_ROUTES) | unassigned |
| 🔴 critical | ⏳ fix-pending | [L13-03](./findings/L13-03-middleware-executa-query-db-a-cada-request-autenticado.md) | 1 | L13 · Middleware | Middleware executa query DB a cada request autenticado | unassigned |
| 🟠 high | ⏳ fix-pending | [L13-04](./findings/L13-04-select-group-nao-esta-em-auth-only-prefixes.md) | 1 | L13 · Middleware | /select-group não está em AUTH_ONLY_PREFIXES nem PUBLIC → comportamento indefinido | unassigned |
| 🟠 high | ⏳ fix-pending | [L13-05](./findings/L13-05-cookies-sem-secure-explicito.md) | 1 | L13 · Middleware | Cookies sem Secure explícito | unassigned |
| 🟠 high | ⏳ fix-pending | [L13-06](./findings/L13-06-x-request-id-nao-propagado-ao-supabase-lib.md) | 1 | L13 · Middleware | x-request-id não propagado ao supabase/lib downstream | unassigned |
| 🟠 high | ⏳ fix-pending | [L13-07](./findings/L13-07-public-routes-contem-api-custody-webhook-sem-ip.md) | 1 | L13 · Middleware | PUBLIC_ROUTES contém /api/custody/webhook sem IP allow-list | unassigned |
| 🟡 medium | ⏳ fix-pending | [L13-08](./findings/L13-08-public-prefixes-challenge-invite-podem-colidir-com-api.md) | 2 | L13 · Middleware | PUBLIC_PREFIXES /challenge/, /invite/ podem colidir com /api/challenge/ | unassigned |
| 🟡 medium | ⏳ fix-pending | [L13-09](./findings/L13-09-middleware-redirect-chain-em-single-membership-causa-duplo.md) | 2 | L13 · Middleware | Middleware redirect chain em single-membership causa duplo round-trip | unassigned |
| 🔴 critical | ⏳ fix-pending | [L14-01](./findings/L14-01-74-route-handlers-46-documentados-em-openapi.md) | 1 | L14 · Contracts | 74 route handlers, 46 documentados em OpenAPI | unassigned |
| 🔴 critical | ⏳ fix-pending | [L14-02](./findings/L14-02-sem-versionamento-de-path-api-v1.md) | 1 | L14 · Contracts | Sem versionamento de path (/api/v1) | unassigned |
| 🔴 critical | ✅ fixed | [L14-03](./findings/L14-03-api-docs-carrega-swagger-ui-de-unpkg-sem.md) | 0 | L14 · Contracts | /api/docs carrega Swagger-UI de unpkg sem SRI | unassigned |
| 🟠 high | ⏳ fix-pending | [L14-04](./findings/L14-04-rate-limit-por-ip-em-swap-custody-vs.md) | 1 | L14 · Contracts | Rate-limit por IP em swap/custody vs por user/group | unassigned |
| 🟠 high | ⏳ fix-pending | [L14-05](./findings/L14-05-respostas-de-erro-nao-padronizadas-error-string-vs.md) | 1 | L14 · Contracts | Respostas de erro não padronizadas (error: string vs error: { code, message }) | unassigned |
| 🟠 high | ⏳ fix-pending | [L14-06](./findings/L14-06-pagination-inconsistente-ou-inexistente.md) | 1 | L14 · Contracts | Pagination inconsistente (ou inexistente) | unassigned |
| 🟡 medium | ⏳ fix-pending | [L14-07](./findings/L14-07-sem-idempotency-key-header-em-posts-financeiros.md) | 2 | L14 · Contracts | Sem idempotency-key header em POSTs financeiros | unassigned |
| 🟡 medium | ⏳ fix-pending | [L14-08](./findings/L14-08-content-negotiation-inexistente.md) | 2 | L14 · Contracts | Content negotiation inexistente | unassigned |
| 🟡 medium | ⏳ fix-pending | [L14-09](./findings/L14-09-sem-quota-por-parceiro-api-key-tier.md) | 2 | L14 · Contracts | Sem quota por parceiro (API key tier) | unassigned |
| 🟠 high | ⏳ fix-pending | [L15-01](./findings/L15-01-zero-utm-tracking-no-produto.md) | 1 | L15 · CMO | Zero UTM tracking no produto | unassigned |
| 🟠 high | ⏳ fix-pending | [L15-02](./findings/L15-02-sem-sistema-de-referral-convite-viral.md) | 1 | L15 · CMO | Sem sistema de referral/convite viral | unassigned |
| 🟠 high | ⏳ fix-pending | [L15-03](./findings/L15-03-social-sharing-sem-open-graph-dinamico.md) | 1 | L15 · CMO | Social sharing sem Open Graph dinâmico | unassigned |
| 🟠 high | ⏳ fix-pending | [L15-04](./findings/L15-04-sem-email-transactional-platform.md) | 1 | L15 · CMO | Sem email transactional platform | unassigned |
| 🟡 medium | ⏳ fix-pending | [L15-05](./findings/L15-05-sem-landing-pages-seo-otimizadas.md) | 2 | L15 · CMO | Sem landing pages SEO-otimizadas | unassigned |
| 🟡 medium | ⏳ fix-pending | [L15-06](./findings/L15-06-sem-a-b-testing-framework.md) | 2 | L15 · CMO | Sem A/B testing framework | unassigned |
| 🟡 medium | ⏳ fix-pending | [L15-07](./findings/L15-07-wrapped-ja-existe-nao-e-compartilhavel-fora-do.md) | 2 | L15 · CMO | Wrapped (já existe) não é compartilhável fora do app | unassigned |
| 🟡 medium | ⏳ fix-pending | [L15-08](./findings/L15-08-sem-push-segmentation.md) | 2 | L15 · CMO | Sem push segmentation | unassigned |
| 🟠 high | ⏳ fix-pending | [L16-01](./findings/L16-01-sem-white-label-branding-customizado-por-grupo.md) | 1 | L16 · CAO | Sem white-label / branding customizado por grupo | unassigned |
| 🟠 high | ⏳ fix-pending | [L16-02](./findings/L16-02-sem-custom-domain-por-assessoria.md) | 1 | L16 · CAO | Sem custom domain por assessoria | unassigned |
| 🔴 critical | ⏳ fix-pending | [L16-03](./findings/L16-03-sem-api-publica-para-parceiros-b2b.md) | 1 | L16 · CAO | Sem API pública para parceiros B2B | unassigned |
| 🟠 high | ⏳ fix-pending | [L16-04](./findings/L16-04-sem-outbound-webhooks-para-parceiros.md) | 1 | L16 · CAO | Sem outbound webhooks para parceiros | unassigned |
| 🟠 high | ⏳ fix-pending | [L16-05](./findings/L16-05-integracoes-de-marcas-esportivas-sem-schema.md) | 1 | L16 · CAO | Integrações de marcas esportivas sem schema | unassigned |
| 🟠 high | ⏳ fix-pending | [L16-06](./findings/L16-06-strava-trainingpeaks-oauth-sem-telemetria-de-uso.md) | 1 | L16 · CAO | Strava / TrainingPeaks OAuth sem telemetria de uso | unassigned |
| 🟡 medium | ⏳ fix-pending | [L16-07](./findings/L16-07-trainingpeaks-oauth-client-credentials-em-env.md) | 2 | L16 · CAO | TrainingPeaks OAuth client credentials em env | unassigned |
| 🟡 medium | ⏳ fix-pending | [L16-08](./findings/L16-08-sem-marketplace-de-treinos-planos.md) | 2 | L16 · CAO | Sem marketplace de treinos/planos | unassigned |
| 🟡 medium | ⏳ fix-pending | [L16-09](./findings/L16-09-sso-saml-oidc-para-enterprise.md) | 2 | L16 · CAO | SSO SAML/OIDC para enterprise | unassigned |
| 🟡 medium | ⏳ fix-pending | [L16-10](./findings/L16-10-sem-tier-free-trial-sandbox-para-parceiros.md) | 2 | L16 · CAO | Sem tier "free trial" / sandbox para parceiros | unassigned |
| 🔴 critical | ⏳ fix-pending | [L17-01](./findings/L17-01-witherrorhandler-nao-e-usado-em-endpoints-financeiros-critic.md) | 1 | L17 · VP Eng | withErrorHandler não é usado em endpoints financeiros críticos | unassigned |
| 🔴 critical | ⏳ fix-pending | [L17-02](./findings/L17-02-5378-linhas-em-portal-src-lib-ts-e.md) | 1 | L17 · VP Eng | 5378 linhas em portal/src/lib/*.ts e sem segregação por bounded context | unassigned |
| 🟠 high | ⏳ fix-pending | [L17-03](./findings/L17-03-witherrorhandler-usa-any-em-routeargs.md) | 1 | L17 · VP Eng | withErrorHandler usa any em routeArgs | unassigned |
| 🟠 high | ⏳ fix-pending | [L17-04](./findings/L17-04-testes-unitarios-em-portal-src-lib-qa-test.md) | 1 | L17 · VP Eng | Testes unitários em portal/src/lib/qa-*.test.ts — arquivos >800 linhas | unassigned |
| 🟠 high | ⏳ fix-pending | [L17-05](./findings/L17-05-logger-silencia-errors-nao-error.md) | 1 | L17 · VP Eng | Logger silencia errors não-Error | unassigned |
| 🟠 high | ⏳ fix-pending | [L17-06](./findings/L17-06-csrfcheck-nao-e-chamado-no-middleware-central.md) | 1 | L17 · VP Eng | csrfCheck não é chamado no middleware central | unassigned |
| 🟡 medium | ⏳ fix-pending | [L17-07](./findings/L17-07-nao-ha-docs-adr-ativo-para-decisoes-arquiteturais.md) | 2 | L17 · VP Eng | Não há docs/adr/ ativo para decisões arquiteturais | unassigned |
| 🟡 medium | ⏳ fix-pending | [L17-08](./findings/L17-08-ausencia-de-monorepo-tooling-turbo-nx-pnpm-workspaces.md) | 2 | L17 · VP Eng | Ausência de monorepo tooling (turbo, nx, pnpm-workspaces) | unassigned |
| 🟡 medium | ⏳ fix-pending | [L17-09](./findings/L17-09-sem-shared-types-ts-dart-entre-portal-e.md) | 2 | L17 · VP Eng | Sem shared types TS/Dart entre portal e mobile | unassigned |
| 🔴 critical | ⏳ fix-pending | [L18-01](./findings/L18-01-duas-fontes-da-verdade-para-balance-de-wallet.md) | 1 | L18 · Principal Eng | Duas fontes da verdade para balance de wallet (wallets.balance_coins vs SUM(coin_ledger)) | unassigned |
| 🔴 critical | ⏳ fix-pending | [L18-02](./findings/L18-02-idempotencia-ad-hoc-em-cada-rpc-padrao-nao.md) | 1 | L18 · Principal Eng | Idempotência ad-hoc em cada RPC — padrão não unificado | unassigned |
| 🔴 critical | ✅ fixed | [L18-03](./findings/L18-03-security-definer-sem-set-search-path-em-funcoes.md) | 0 | L18 · Principal Eng | SECURITY DEFINER sem SET search_path em funções antigas | unassigned |
| 🔴 critical | ⏳ fix-pending | [L18-04](./findings/L18-04-architecture-flutter-viola-clean-arch-em-varios-pontos.md) | 1 | L18 · Principal Eng | Architecture: Flutter viola Clean Arch em vários pontos | unassigned |
| 🟠 high | ⏳ fix-pending | [L18-05](./findings/L18-05-event-bus-inexistente-cascatas-de-efeitos-em-codigo.md) | 1 | L18 · Principal Eng | Event bus inexistente — cascatas de efeitos em código imperativo | unassigned |
| 🟠 high | ⏳ fix-pending | [L18-06](./findings/L18-06-cachedflags-em-feature-flags-ts-cache-de-modulo.md) | 1 | L18 · Principal Eng | cachedFlags em feature-flags.ts — cache de módulo com TTL racional | unassigned |
| 🟠 high | ⏳ fix-pending | [L18-07](./findings/L18-07-userbucket-em-feature-flags-usa-hash-java-style.md) | 1 | L18 · Principal Eng | userBucket em feature-flags usa hash Java-style (inseguro, colisões) | unassigned |
| 🟠 high | ⏳ fix-pending | [L18-08](./findings/L18-08-edge-functions-vs-route-handlers-responsabilidade-duplicada.md) | 1 | L18 · Principal Eng | Edge Functions vs Route Handlers — responsabilidade duplicada | unassigned |
| 🟡 medium | ⏳ fix-pending | [L18-09](./findings/L18-09-sem-domain-events-em-audit-log.md) | 2 | L18 · Principal Eng | Sem domain events em audit_log | unassigned |
| 🟡 medium | ⏳ fix-pending | [L18-10](./findings/L18-10-sem-health-check-de-business-logic-vs-infra.md) | 2 | L18 · Principal Eng | Sem health-check de business logic (vs infra) | unassigned |
| 🔴 critical | ✅ fixed | [L19-01](./findings/L19-01-coin-ledger-nao-e-particionada-tabela-crescendo-sem.md) | 0 | L19 · DBA | coin_ledger não é particionada — tabela crescendo sem controle | unassigned |
| 🔴 critical | ⏳ fix-pending | [L19-02](./findings/L19-02-delete-em-archive-cron-gera-table-bloat-massivo.md) | 1 | L19 · DBA | DELETE em archive cron gera table bloat massivo | unassigned |
| 🔴 critical | ⏳ fix-pending | [L19-03](./findings/L19-03-indexes-redundantes-em-sessions.md) | 1 | L19 · DBA | Indexes redundantes em sessions | unassigned |
| 🟠 high | ⏳ fix-pending | [L19-04](./findings/L19-04-idx-ledger-user-vs-idx-coin-ledger-user.md) | 1 | L19 · DBA | idx_ledger_user vs idx_coin_ledger_user_created — evoluções sem limpeza | unassigned |
| 🔴 critical | ✅ fixed | [L19-05](./findings/L19-05-falta-for-update-nowait-em-funcoes-de-lock.md) | 0 | L19 · DBA | Falta FOR UPDATE NOWAIT em funções de lock crítico | unassigned |
| 🟠 high | ⏳ fix-pending | [L19-06](./findings/L19-06-jsonb-em-audit-logs-metadata-sem-indice-gin.md) | 1 | L19 · DBA | JSONB em audit_logs.metadata sem índice GIN | unassigned |
| 🟠 high | ⏳ fix-pending | [L19-07](./findings/L19-07-pg-stat-statements-nao-referenciado-em-tuning.md) | 1 | L19 · DBA | pg_stat_statements não referenciado em tuning | unassigned |
| 🟠 high | ⏳ fix-pending | [L19-08](./findings/L19-08-constraints-check-sem-name-padronizado.md) | 1 | L19 · DBA | Constraints CHECK sem name padronizado | unassigned |
| 🟡 medium | ⏳ fix-pending | [L19-09](./findings/L19-09-connection-pooling-nao-documentado.md) | 2 | L19 · DBA | Connection pooling não documentado | unassigned |
| 🟡 medium | ⏳ fix-pending | [L19-10](./findings/L19-10-sem-autovacuum-tuning-para-tabelas-hot.md) | 2 | L19 · DBA | Sem autovacuum tuning para tabelas hot | unassigned |
| 🔴 critical | ✅ fixed | [L20-01](./findings/L20-01-sem-dashboard-consolidado-de-operacoes-financeiras.md) | 1 | L20 · SRE | Sem dashboard consolidado de operações financeiras | unassigned |
| 🔴 critical | ✅ fixed | [L20-02](./findings/L20-02-sem-slo-sli-definidos-impossivel-ter-alert-policy.md) | 1 | L20 · SRE | Sem SLO/SLI definidos → impossível ter alert policy razoável | unassigned |
| 🔴 critical | ⏳ fix-pending | [L20-03](./findings/L20-03-sem-tracing-distribuido-opentelemetry.md) | 1 | L20 · SRE | Sem tracing distribuído (OpenTelemetry) | unassigned |
| 🟠 high | ✅ fixed | [L20-04](./findings/L20-04-sentry-sem-tracessamplerate-tuning-documentado.md) | 1 | L20 · SRE | Sentry sem tracesSampleRate tuning documentado | unassigned |
| 🟠 high | ✅ fixed | [L20-05](./findings/L20-05-alerts-sem-canal-de-severidade.md) | 1 | L20 · SRE | Alerts sem canal de severidade | unassigned |
| 🟠 high | ⏳ fix-pending | [L20-06](./findings/L20-06-status-page-publica-inexistente.md) | 1 | L20 · SRE | Status page pública inexistente | unassigned |
| 🟠 high | ✅ fixed | [L20-07](./findings/L20-07-backup-testado-zero-evidence.md) | 1 | L20 · SRE | Backup testado — zero evidence | unassigned |
| 🟠 high | ✅ fixed | [L20-08](./findings/L20-08-post-mortem-template-ausente.md) | 1 | L20 · SRE | Post-mortem template ausente | unassigned |
| 🟡 medium | ⏳ fix-pending | [L20-09](./findings/L20-09-chaos-engineering-inexistente.md) | 2 | L20 · SRE | Chaos engineering inexistente | unassigned |
| 🟡 medium | ⏳ fix-pending | [L20-10](./findings/L20-10-logs-de-producao-nao-searchable.md) | 2 | L20 · SRE | Logs de produção não-searchable | unassigned |
| 🟡 medium | ⏳ fix-pending | [L20-11](./findings/L20-11-cost-observability-inexistente.md) | 2 | L20 · SRE | Cost observability inexistente | unassigned |
| 🟡 medium | ⏳ fix-pending | [L20-12](./findings/L20-12-capacity-planning-sem-modelo.md) | 2 | L20 · SRE | Capacity planning sem modelo | unassigned |
| 🟡 medium | ⏳ fix-pending | [L20-13](./findings/L20-13-error-budget-policy-ausente.md) | 2 | L20 · SRE | Error budget policy ausente | unassigned |
| 🔴 critical | ⏳ fix-pending | [L21-01](./findings/L21-01-max-speed-ms-12-5-m-s-invalida.md) | 1 | L21 · Atleta Pro | MAX_SPEED_MS = 12.5 m/s invalida velocistas profissionais | unassigned |
| 🔴 critical | ⏳ fix-pending | [L21-02](./findings/L21-02-max-hr-bpm-220-inferior-a-realidade-de.md) | 1 | L21 · Atleta Pro | MAX_HR_BPM = 220 inferior à realidade de atletas jovens | unassigned |
| 🔴 critical | ⏳ fix-pending | [L21-03](./findings/L21-03-dados-gps-e-biometricos-sem-controle-de-propriedade.md) | 1 | L21 · Atleta Pro | Dados GPS e biométricos sem controle de propriedade (dilema do patrocínio) | unassigned |
| 🔴 critical | ⏳ fix-pending | [L21-04](./findings/L21-04-ausencia-de-training-load-tss-ctl-atl.md) | 1 | L21 · Atleta Pro | Ausência de "training load" / TSS / CTL / ATL | unassigned |
| 🔴 critical | ⏳ fix-pending | [L21-05](./findings/L21-05-zonas-de-treino-pace-hr-nao-personalizaveis.md) | 1 | L21 · Atleta Pro | Zonas de treino (pace/HR) não personalizáveis | unassigned |
| 🟠 high | ⏳ fix-pending | [L21-06](./findings/L21-06-polyline-gps-resolucao-baixa-5m-distancefilter.md) | 1 | L21 · Atleta Pro | Polyline GPS resolução baixa (5m distanceFilter) | unassigned |
| 🟠 high | ⏳ fix-pending | [L21-07](./findings/L21-07-sem-interoperabilidade-com-fit-real-time.md) | 1 | L21 · Atleta Pro | Sem interoperabilidade com .fit real-time | unassigned |
| 🟠 high | ⏳ fix-pending | [L21-08](./findings/L21-08-lap-splits-manuais-inexistentes-em-tela-de-corrida.md) | 1 | L21 · Atleta Pro | Lap splits manuais inexistentes em tela de corrida | unassigned |
| 🟠 high | ⏳ fix-pending | [L21-09](./findings/L21-09-calibracao-de-gps-em-pista-400-m-outdoor.md) | 1 | L21 · Atleta Pro | Calibração de GPS em pista (400 m outdoor) | unassigned |
| 🟠 high | ⏳ fix-pending | [L21-10](./findings/L21-10-anti-cheat-pode-publicamente-marcar-elite-como-suspeito.md) | 1 | L21 · Atleta Pro | Anti-cheat pode publicamente marcar elite como suspeito | unassigned |
| 🟠 high | ⏳ fix-pending | [L21-11](./findings/L21-11-ghost-mode-nao-funciona-para-competicoes-reais.md) | 1 | L21 · Atleta Pro | Ghost mode não funciona para competições reais | unassigned |
| 🟠 high | ⏳ fix-pending | [L21-12](./findings/L21-12-sem-team-dashboard-para-staff-tecnica.md) | 1 | L21 · Atleta Pro | Sem "team dashboard" para staff técnica | unassigned |
| 🟡 medium | ⏳ fix-pending | [L21-13](./findings/L21-13-recovery-sleep-tracking-ausente.md) | 2 | L21 · Atleta Pro | Recovery/sleep tracking ausente | unassigned |
| 🟡 medium | ⏳ fix-pending | [L21-14](./findings/L21-14-sem-race-predictor-vdot-riegel.md) | 2 | L21 · Atleta Pro | Sem race predictor (VDOT/Riegel) | unassigned |
| 🟡 medium | ⏳ fix-pending | [L21-15](./findings/L21-15-weather-enrichment-sessao-historica.md) | 2 | L21 · Atleta Pro | Weather enrichment (sessão histórica) | unassigned |
| 🟡 medium | ⏳ fix-pending | [L21-16](./findings/L21-16-competicoes-oficiais-nao-categorizadas.md) | 2 | L21 · Atleta Pro | Competições oficiais não categorizadas | unassigned |
| 🟡 medium | ⏳ fix-pending | [L21-17](./findings/L21-17-sponsorship-disclosure-automatico-ausente.md) | 2 | L21 · Atleta Pro | Sponsorship disclosure automático ausente | unassigned |
| 🟡 medium | ⏳ fix-pending | [L21-18](./findings/L21-18-heart-rate-ble-drop-sem-recovery-visual.md) | 2 | L21 · Atleta Pro | Heart-rate BLE drop sem recovery visual | unassigned |
| 🟡 medium | ⏳ fix-pending | [L21-19](./findings/L21-19-post-run-nutrition-log-esquecido.md) | 2 | L21 · Atleta Pro | Post-run nutrition log esquecido | unassigned |
| 🟡 medium | ⏳ fix-pending | [L21-20](./findings/L21-20-privacy-mode-para-competicoes.md) | 2 | L21 · Atleta Pro | Privacy mode para competições | unassigned |
| 🔴 critical | ⏳ fix-pending | [L22-01](./findings/L22-01-onboarding-nao-inclui-primeira-corrida-guiada.md) | 1 | L22 · Atleta Amador | Onboarding não inclui "primeira corrida guiada" | unassigned |
| 🔴 critical | ⏳ fix-pending | [L22-02](./findings/L22-02-conceito-de-moeda-omnicoin-confunde-amador.md) | 1 | L22 · Atleta Amador | Conceito de "moeda / OmniCoin" confunde amador | unassigned |
| 🔴 critical | ⏳ fix-pending | [L22-03](./findings/L22-03-plano-semanal-pessoal-ausente-para-solo-runner.md) | 1 | L22 · Atleta Amador | Plano semanal pessoal ausente para solo runner | unassigned |
| 🟠 high | ⏳ fix-pending | [L22-04](./findings/L22-04-feedback-de-ritmo-so-pos-corrida.md) | 1 | L22 · Atleta Amador | Feedback de ritmo só pós-corrida | unassigned |
| 🟠 high | ⏳ fix-pending | [L22-05](./findings/L22-05-grupos-locais-sem-descoberta-por-proximidade.md) | 1 | L22 · Atleta Amador | Grupos locais sem descoberta por proximidade | unassigned |
| 🟠 high | ⏳ fix-pending | [L22-06](./findings/L22-06-voice-coaching-parcial.md) | 1 | L22 · Atleta Amador | Voice coaching parcial | unassigned |
| 🟠 high | ⏳ fix-pending | [L22-07](./findings/L22-07-compra-parcelada-para-assessoria-brasileira.md) | 1 | L22 · Atleta Amador | Compra parcelada para assessoria brasileira | unassigned |
| 🟠 high | ⏳ fix-pending | [L22-08](./findings/L22-08-desafio-de-grupo-viralizacao-entre-amigos.md) | 1 | L22 · Atleta Amador | Desafio de grupo (viralização entre amigos) | unassigned |
| 🟠 high | ⏳ fix-pending | [L22-09](./findings/L22-09-progress-celebration-timida.md) | 1 | L22 · Atleta Amador | Progress celebration tímida | unassigned |
| 🟡 medium | ⏳ fix-pending | [L22-10](./findings/L22-10-apple-watch-wear-os-nativo.md) | 2 | L22 · Atleta Amador | Apple Watch / Wear OS nativo | unassigned |
| 🟡 medium | ⏳ fix-pending | [L22-11](./findings/L22-11-corrida-em-esteira-sem-gps.md) | 2 | L22 · Atleta Amador | Corrida em esteira sem GPS | unassigned |
| 🟡 medium | ⏳ fix-pending | [L22-12](./findings/L22-12-streaks-dias-consecutivos-correndo-sem-grace-period.md) | 2 | L22 · Atleta Amador | Streaks (dias consecutivos correndo) sem grace period | unassigned |
| 🟡 medium | ⏳ fix-pending | [L22-13](./findings/L22-13-menstrual-cycle-tracking-tabu-mas-importante.md) | 2 | L22 · Atleta Amador | Menstrual cycle tracking — tabu mas importante | unassigned |
| 🟡 medium | ⏳ fix-pending | [L22-14](./findings/L22-14-recuperacao-ativa-nao-sugerida.md) | 2 | L22 · Atleta Amador | Recuperação ativa não sugerida | unassigned |
| 🟡 medium | ⏳ fix-pending | [L22-15](./findings/L22-15-formato-de-exportacao-pessoal-apenas-tecnico.md) | 2 | L22 · Atleta Amador | Formato de exportação pessoal apenas técnico | unassigned |
| 🟡 medium | ⏳ fix-pending | [L22-16](./findings/L22-16-primeira-experiencia-de-injury-sem-onboarding.md) | 2 | L22 · Atleta Amador | Primeira experiência de injury sem onboarding | unassigned |
| 🟡 medium | ⏳ fix-pending | [L22-17](./findings/L22-17-clima-local-nao-informa-decisao.md) | 2 | L22 · Atleta Amador | Clima local não informa decisão | unassigned |
| 🟡 medium | ⏳ fix-pending | [L22-18](./findings/L22-18-onboarding-nao-pergunta-objetivo.md) | 2 | L22 · Atleta Amador | Onboarding não pergunta objetivo | unassigned |
| 🟡 medium | ⏳ fix-pending | [L22-19](./findings/L22-19-social-comparison-saudavel-vs-toxica.md) | 2 | L22 · Atleta Amador | Social comparison saudável vs tóxica | unassigned |
| 🟡 medium | ⏳ fix-pending | [L22-20](./findings/L22-20-retencao-d30-d90-hooks-especificos.md) | 2 | L22 · Atleta Amador | Retenção D30/D90 — hooks específicos | unassigned |
| 🔴 critical | ⏳ fix-pending | [L23-01](./findings/L23-01-workout-delivery-em-massa-sem-preview-por-atleta.md) | 1 | L23 · Treinador | Workout delivery em massa sem preview por atleta | unassigned |
| 🔴 critical | ⏳ fix-pending | [L23-02](./findings/L23-02-dashboard-de-overview-diario-para-coach-tem-100.md) | 1 | L23 · Treinador | Dashboard de overview diário para coach tem 100-500 atletas | unassigned |
| 🔴 critical | ⏳ fix-pending | [L23-03](./findings/L23-03-comunicacao-coach-atleta-carece.md) | 1 | L23 · Treinador | Comunicação coach ↔ atleta carece | unassigned |
| 🔴 critical | ⏳ fix-pending | [L23-04](./findings/L23-04-bulk-assign-semanal-ver-20260416000000-bulk-assign-and.md) | 1 | L23 · Treinador | Bulk assign semanal (ver 20260416000000_bulk_assign_and_week_templates.sql) sem rollback | unassigned |
| 🟠 high | ⏳ fix-pending | [L23-05](./findings/L23-05-workout-template-library-pobre.md) | 1 | L23 · Treinador | Workout template library pobre | unassigned |
| 🟠 high | ⏳ fix-pending | [L23-06](./findings/L23-06-plano-mensal-trimestral-nao-periodizado.md) | 1 | L23 · Treinador | Plano mensal/trimestral não periodizado | unassigned |
| 🟠 high | ⏳ fix-pending | [L23-07](./findings/L23-07-analise-coletiva-grupo-limitada.md) | 1 | L23 · Treinador | Análise coletiva (grupo) limitada | unassigned |
| 🟠 high | ⏳ fix-pending | [L23-08](./findings/L23-08-presenca-em-treinos-coletivos-via-qr-code-staff.md) | 1 | L23 · Treinador | Presença em treinos coletivos via QR code (staff_training_scan_screen.dart existe) | unassigned |
| 🟠 high | ⏳ fix-pending | [L23-09](./findings/L23-09-billing-integrado-cobranca-de-mensalidade-aos-atletas.md) | 1 | L23 · Treinador | Billing integrado (cobrança de mensalidade aos atletas) | unassigned |
| 🟠 high | ⏳ fix-pending | [L23-10](./findings/L23-10-treinos-com-dependencia-entre-atletas-par-grupo.md) | 1 | L23 · Treinador | Treinos com dependência entre atletas (par/grupo) | unassigned |
| 🟠 high | ⏳ fix-pending | [L23-11](./findings/L23-11-relatorios-para-atleta-resumo-mensal-do-coach.md) | 1 | L23 · Treinador | Relatórios para atleta (resumo mensal do coach) | unassigned |
| 🟠 high | ⏳ fix-pending | [L23-12](./findings/L23-12-onboarding-de-novo-atleta-no-clube.md) | 1 | L23 · Treinador | Onboarding de novo atleta no clube | unassigned |
| 🟠 high | ⏳ fix-pending | [L23-13](./findings/L23-13-feedback-do-atleta-rpe-dor-humor-nao-requerido.md) | 1 | L23 · Treinador | Feedback do atleta (RPE, dor, humor) não requerido | unassigned |
| 🟠 high | ⏳ fix-pending | [L23-14](./findings/L23-14-corrida-de-teste-time-trial-agendada.md) | 1 | L23 · Treinador | "Corrida de teste" (time trial) agendada | unassigned |
| 🟡 medium | ⏳ fix-pending | [L23-15](./findings/L23-15-crm-para-captacao-de-atletas.md) | 2 | L23 · Treinador | CRM para captação de atletas | unassigned |
| 🟡 medium | ⏳ fix-pending | [L23-16](./findings/L23-16-repasse-financeiro-transparente-para-coach-como-pj.md) | 2 | L23 · Treinador | Repasse financeiro transparente para coach como PJ | unassigned |
| 🟡 medium | ⏳ fix-pending | [L23-17](./findings/L23-17-certificados-cref-validacao.md) | 2 | L23 · Treinador | Certificados CREF validação | unassigned |
| 🟡 medium | ⏳ fix-pending | [L23-18](./findings/L23-18-ghost-assistente-virtual-para-coaches-novatos.md) | 2 | L23 · Treinador | Ghost/assistente virtual para coaches novatos | unassigned |
| 🟡 medium | ⏳ fix-pending | [L23-19](./findings/L23-19-multiplos-clubes-coach-atende-em-3-clubes.md) | 2 | L23 · Treinador | Múltiplos clubes (coach atende em 3 clubes) | unassigned |
| 🟡 medium | ⏳ fix-pending | [L23-20](./findings/L23-20-integracao-calendario-google-calendar-ical.md) | 2 | L23 · Treinador | Integração calendário (Google Calendar / iCal) | unassigned |
