# Production-Ready Checklist — Custódia & Clearing

## Modelo Financeiro

- [x] Custódia real em USD com lastro fixo 1 coin = US$ 1
- [x] Conta segregada por clube (total_deposited_usd, total_committed, available)
- [x] Emissão condicionada a lastro (custody_commit_coins)
- [x] Clearing interclub com taxa 3% (configurable)
- [x] Swap de lastro com taxa 1% (configurable)
- [x] Spread cambial entrada/saída 0,75% (configurable)
- [x] Platform revenue tracking (clearing, swap, fx_spread)
- [x] Retirada limitada ao saldo disponível

## Segurança

- [x] Webhook signature verification (Stripe + MercadoPago)
- [x] Idempotência por payment_reference (UNIQUE constraint)
- [x] Idempotência por burn_ref_id (UNIQUE constraint)
- [x] CSRF protection em rotas mutáveis
- [x] Rate limiting plugável (in-memory + Redis-ready)
- [x] Content-Security-Policy hardened
- [x] Auth: admin_master required para operações de custódia
- [x] Timing-safe signature comparison

## Invariantes

- [x] D = R + A (por definição, computado)
- [x] R_i = M_i (check_custody_invariants com join em coin_ledger)
- [x] D ≥ 0, R ≥ 0, D ≥ R (CHECK constraints + invariant function)
- [x] Pre-operation invariant gate (distribute-coins, clearing)
- [x] Health check com invariant check (/api/health → 503 se falhar)
- [x] Platform invariant endpoint (/api/platform/invariants)

## Atomicidade e Concorrência

- [x] execute_burn_atomic: burn + breakdown + clearing em 1 transação
- [x] settle_clearing: FOR UPDATE locks no settlement e custody
- [x] execute_swap: UUID-ordered locking para deadlock prevention
- [x] execute_withdrawal: FOR UPDATE no custody account
- [x] Netting por janela (aggregate_clearing_window)

## Auditoria

- [x] Audit log para depósitos (created, confirmed, webhook_confirmed)
- [x] Audit log para burns (clearing.burn.processed)
- [x] Audit log para settlements (clearing.settlement.settled)
- [x] Audit log para withdrawals (custody.withdrawal.executed)
- [x] Audit log para swaps
- [x] Audit log para distribute-coins

## App Compliance

- [x] Varredura automatizada: no_money_in_app_test.dart
- [x] CI falha se termos monetários aparecem no app
- [x] App é coins-only (zero referência a dinheiro)

## Testes

- [x] Unit: burn plan determinístico
- [x] Unit: cálculo de taxas (clearing 3%, swap 1%)
- [x] Unit: validações de custódia
- [x] Unit: webhook verification
- [x] Unit: CSRF protection
- [x] Unit: rate limiting
- [x] Unit: DataTable, Sparkline, BarChart components
- [x] Unit: format utilities
- [x] Unit: metrics library
- [x] Unit: health check with invariants
- [x] E2E (model): burn → clearing → settlement
- [x] Compliance: no monetary terms in app

## CI/CD

- [x] GitHub Actions: lint, typecheck, test, build
- [x] Coverage reporting (v8 + lcov)
- [x] Coverage thresholds (70% statements/branches)
- [x] Flutter: analyze, test, build APK

## Documentação

- [x] B2B Custody Guide (docs/B2B_CUSTODY_GUIDE.md)
- [x] ADR-007: Custody & Clearing Model
- [x] Portal API Surface (README.md)
- [x] E2E Audit Report
- [x] Termos Operacionais B2B (docs/TERMOS_OPERACIONAIS.md)
- [x] Production Checklist (this file)

## Observabilidade

- [x] MetricsCollector interface com structured logging
- [x] withMetrics wrapper para timing/error counting
- [x] Health check: DB + custody invariants
- [x] Platform revenue table (receipts de todas as taxas)

## Portal Pages (especificação profissional)

- [x] Custódia: KPIs (total/reservado/disponível/coins vivas), invariant badges, tabs (Extrato/Depósitos/Retiradas), export CSV
- [x] Clearing: KPIs (a receber/pagar/taxas/SLA), filtros profissionais, detalhe contábil inline, export CSV
- [x] Swap: KPIs (disponível/volume/taxas/ofertas), RFQ, histórico com export CSV
- [x] FX: KPIs, simulador interativo (BRL↔USD), política de câmbio, withdraw button, export CSV
- [x] Auditoria: busca global (burn ID/athlete/clube), timeline visual, chain completa (burn→settlements→custody), export CSV
- [x] Settings: taxas aplicadas (clearing/swap/fx), status de custódia, tier/bloqueio
- [x] Header: badge de ambiente (PROD/SANDBOX), role do usuário, indicador de bloqueio
- [x] ExportButton: componente reutilizável CSV em todas as páginas
- [x] Auto-bloqueio de contas via POST /api/platform/invariants/enforce

## Pendentes (pós-launch)

- [ ] Integration test contra Postgres real (burn → settlement → wallet)
- [ ] Redis-backed rate limiter em produção
- [ ] Alerting/PagerDuty para invariant violations
- [ ] Dashboard de platform_revenue para admin
