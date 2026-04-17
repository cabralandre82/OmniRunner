# PARTE 2 de 8 — LENTES 2 (CTO) e 3 (CFO)

## LENTE 2 — CTO: ARQUITETURA E RACE CONDITIONS

### [2.1] `distribute-coins` — Orquestração não-atômica entre 4 RPCs
- **Camada:** PORTAL + BACKEND
- **Persona principal impactada:** Atleta, Assessoria, Plataforma
- **Veredicto:** 🔴 **CRÍTICO**
- **Achado:** `portal/src/app/api/distribute-coins/route.ts:97-158` chama sequencialmente: (1) `custody_commit_coins`, (2) `decrement_token_inventory`, (3) `increment_wallet_balance`, (4) insert em `coin_ledger`. Cada chamada é uma transação PostgREST separada. **Não há `BEGIN … COMMIT` englobando**. Se Vercel matar a função (timeout 10s Hobby / 60s Pro) entre (2) e (3), o grupo perdeu inventário e o atleta não recebeu as coins. Duplica [1.3].
- **Risco:** Perda silenciosa de inventário; invariante `D_i = R_i + A_i` quebrada (coins removidos da contagem sem correspondência na wallet), mas `check_custody_invariants` não detecta porque apenas compara contabilidade vs ledger, e não compara `token_inventory` vs `coin_ledger`.
- **Correção:** Migrar para função SQL `distribute_coins_atomic` (ver [1.3]) que faz tudo em uma única transação com locks `FOR UPDATE` nas duas tabelas afetadas. Alternativa: usar outbox pattern (registrar intent em tabela + worker idempotente).
- **Teste de regressão:** teste de integração matando a conexão após `decrement_token_inventory` (mock de `createServiceClient` que rejeita na 3ª call) → validar rollback.

---

### [2.2] `execute_burn_atomic` — Exceções engolidas em `custody_release_committed` e `settle_clearing`
- **Camada:** BACKEND (Supabase RPC)
- **Persona principal impactada:** Plataforma, Assessoria
- **Veredicto:** 🔴 **CRÍTICO**
- **Achado:** `supabase/migrations/20260228160001_burn_plan_atomic.sql:159-163, 182-186`:
  ```sql
  BEGIN
    PERFORM public.custody_release_committed(v_issuer, v_issuer_balance);
  EXCEPTION WHEN OTHERS THEN
    NULL; -- Custody not yet active for this club
  END;
  -- ...
  BEGIN
    PERFORM public.settle_clearing(v_settlement_id);
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
  ```
  Silenciar `WHEN OTHERS` inclui `deadlock_detected`, `connection_exception`, constraint violations, check_custody_invariants, OUT OF MEMORY, etc. O atleta é creditado pelo burn, o coin_ledger é atualizado, mas o `total_committed` do clube emissor permanece inflado → **invariante R_i vs M_i quebrada**.
- **Risco:** Violação direta da invariante central do modelo de custódia. `check_custody_invariants` eventualmente detecta e bloqueia operações futuras (linhas 302-321), mas o atleta já consumiu suas coins e a assessoria emissora fica com passivo "fantasma" (R elevado).
- **Correção:**
  - Capturar exceções específicas apenas (connection / undefined_function) para compatibilidade com clubes sem custody:
  ```sql
  BEGIN
    PERFORM public.custody_release_committed(v_issuer, v_issuer_balance);
  EXCEPTION
    WHEN undefined_function THEN NULL;  -- RPC não existe (legacy)
    WHEN OTHERS THEN RAISE;             -- re-raise para abortar a transação
  END;
  ```
  - Para settle_clearing: remover o bloco EXCEPTION — deixar falhar. Se settlement falha, a transação toda rollback (burn não processado). Alternativa: inserir `clearing_settlements` com status `'pending_retry'` e cron faz retries.
- **Teste de regressão:** SQL test que injeta exception em `custody_release_committed` via trigger `BEFORE UPDATE` e valida que `execute_burn_atomic` faz rollback.

---

### [2.3] `execute_burn_atomic` — Function `LANGUAGE plpgsql` sem `SECURITY DEFINER` vs. chamadas a funções `SECURITY DEFINER`
- **Camada:** BACKEND
- **Veredicto:** 🟡 **MÉDIO**
- **Achado:** `execute_burn_atomic` em `20260228160001:80` não é `SECURITY DEFINER`. Mas chama `custody_release_committed` e `settle_clearing` que são `SECURITY DEFINER`. Funciona porque o caller é `service_role`, mas em RLS-strict callers os role context muda. Misturar DEFINER/INVOKER é difícil de raciocinar.
- **Correção:** Marcar `execute_burn_atomic` também como `SECURITY DEFINER` com `SET search_path = public, pg_temp` e conceder `GRANT EXECUTE` apenas a `service_role`. Já existe grant na linha 199.

---

### [2.4] `confirm_custody_deposit` — `FOR UPDATE` + UPSERT
- **Camada:** BACKEND
- **Veredicto:** 🟢 **SEGURO**
- **Achado:** `20260228170000:325-352` faz `SELECT … FOR UPDATE` na linha do depósito (linha 336), depois UPSERT em `custody_accounts` com `ON CONFLICT DO UPDATE`. Seguro contra double-confirmation.
- **Correção:** N/A.

---

### [2.5] `execute_swap` — Deadlock prevention via UUID ordering
- **Camada:** BACKEND
- **Veredicto:** 🟢 **SEGURO**
- **Achado:** `20260228170000:231-241` ordena os locks FOR UPDATE por UUID (`v_seller < p_buyer_group_id`). Previne deadlocks clássicos de circular-wait. Bom design.
- **Correção:** N/A.

---

### [2.6] `execute_withdrawal` — Estado `'processing'` sem transição final
- **Camada:** BACKEND + PORTAL
- **Persona principal impactada:** Assessoria (admin_master)
- **Veredicto:** 🟠 **ALTO**
- **Achado:** `20260228170000:125-127` seta `status='processing'` mas **nenhuma migration posterior adiciona transição para `'completed'`/`'failed'`**. O fluxo é: `pending → processing` (in-RPC) → ??? (fora do sistema). `portal/src/app/api/custody/withdraw/route.ts:104` chama `executeWithdrawal` e retorna a withdrawal — mas na prática a saída de USD para o banco local é manual (TED externo), sem nenhum mecanismo que marque `completed`.
- **Risco:** Withdrawals ficam eternamente em `processing`. Reconciliação impossível via `getWithdrawals()`. Se o TED externo falhar, a assessoria não recupera os USD (foram debitados de `total_deposited_usd`).
- **Correção:**
  1. Criar endpoint `POST /api/platform/custody/withdrawal/[id]/complete` (platform_admin) que seta `status='completed'` + `completed_at=now()` + `payout_reference=` (código do TED).
  2. Criar endpoint `/fail` que reverte `total_deposited_usd += amount_usd` (precisa de RPC atômica `reverse_withdrawal`).
  3. Cron `stale-withdrawals` alerta platform_admin se uma withdrawal fica > 7 dias em processing.

---

### [2.7] `execute_swap` — Buyer funding não é lockado corretamente
- **Camada:** BACKEND
- **Veredicto:** 🟡 **MÉDIO**
- **Achado:** `20260228170000:229-246`: o seller tem `v_seller_avail < v_amount` verificado, mas o **buyer recebe `v_net` sem checar se o buyer tem USD para pagar**. No modelo atual, buyer recebe a credit `D_buyer += net` *sem* débito correspondente — o swap é uma **cessão de crédito de custódia**, não uma transferência monetária bilateral. Se essa é a intenção de produto (liquidez interclub), OK. Se é uma venda (buyer paga cash fora-do-sistema e recebe backing), **faltam validações**: comprovante externo, aprovação dupla, idempotência por order_id.
- **Risco:** Dependente de regra de negócio. Admin_master do buyer pode aceitar ofertas sem ter USD reais, "inflando" a custódia do clube.
- **Correção:** Documentar o modelo em ADR. Se é cessão de crédito: adicionar `swap_external_payment_ref` obrigatório no aceite. Se é matching ativo: atrelar ao fluxo Stripe/MP com checkout.

---

### [2.8] Realtime / Websocket — Cross-tenant leak
- **Camada:** APP (Flutter via `supabase_flutter`) + BACKEND
- **Persona principal impactada:** Atleta, Assessoria
- **Veredicto:** 🟠 **ALTO**
- **Achado:** O projeto usa Realtime (pubspec declara `supabase_flutter`). Tabelas adicionadas a `supabase_realtime` vazam se RLS não filtrar nos eventos. Não verifiquei migration `supabase_realtime` direto, mas o padrão genérico é: Realtime aplica RLS via `auth.uid()` do subscriber. As policies `custody_accounts` estão com role `'professor'` (ver [1.43]) → **atletas e coaches nunca recebem eventos de custody** (bem). Porém, policies de `coaching_members`, `wallets`, `sessions` podem permitir vazamento — atleta A inspeciona seu cliente WebSocket e altera filtros para receber eventos de atleta B. RLS em `wallets` precisa restringir a `user_id = auth.uid()`.
- **Risco:** Vazamento de saldo, sessão, ranking por inspeção de WebSocket.
- **Correção:** Auditar cada tabela com REPLICA IDENTITY ou em `ALTER PUBLICATION supabase_realtime ADD TABLE X`. Confirmar RLS FOR SELECT é restritivo.

---

### [2.9] Migration drift — CHECK `platform_fee_config.fee_type` (duplica 1.44)
- **Camada:** BACKEND
- **Veredicto:** 🔴 **CRÍTICO** (ver [1.44])

---

### [2.10] Cold start + timeout Vercel em operações longas
- **Camada:** PORTAL
- **Persona principal impactada:** Platform admin (relatórios/exports), Coach (batch)
- **Veredicto:** 🟠 **ALTO**
- **Achado:** `createServiceClient` em `portal/src/lib/supabase/service.ts:7-9` tem timeout de 15s. Operações de batch (`settleWindowForDebtor` em `clearing.ts:296-329`) fazem loop síncrono de `settle_clearing` por settlement pending — para 500 settlements pendentes em uma janela, isso pode exceder 60s mesmo em Vercel Pro.
- **Risco:** Deploys em Vercel Hobby (10s) vão falhar imediatamente em batch settlements. Em Pro (60s), acima de ~300 settlements/batch → função morta silenciosamente, settlements parciais, estado inconsistente.
- **Correção:**
  1. Processar em chunks: `LIMIT 50` por invocação, continuação via cron `/api/cron/settle-clearing-batch` a cada minuto.
  2. Para exports: usar Supabase Edge Function (Deno, timeout 150s) em vez de Next.js API.

---

### [2.11] Pool de conexões `createServiceClient` per-request
- **Camada:** PORTAL
- **Veredicto:** 🟡 **MÉDIO**
- **Achado:** `portal/src/lib/supabase/service.ts:10` cria um novo client a cada `createServiceClient()`. Em Vercel Serverless, cold start abre nova connection para PostgREST. Hot invocations reutilizam instance via Node module cache — mas cada request chama `createServiceClient()` nova, criando nova instância. PostgREST REST não mantém pool de DB connections no client-side (é stateless HTTP), então múltiplos clients não saturam connections — **mas** o Supabase Pool (PgBouncer) tem limite de conexões. Em picos com muitas Edge Functions + Portal simultâneos, pode haver starvation.
- **Correção:** Confirmar que Supabase Pool está em transaction-mode (default). Reduzir statement_timeout do service role para 15s para evitar queries longas segurando connection.

---

### [2.12] Zod v4 upgrade — UUID strict validation
- **Camada:** PORTAL
- **Persona principal impactada:** Todos (formulários)
- **Veredicto:** 🟡 **MÉDIO**
- **Achado:** `portal/src/lib/schemas.ts:4,24,76,92,98,108,115` usam `z.string().uuid(...)`. Zod v4 mudou `uuid()` para validar strict RFC 4122 (exige versão 1-5 em posição específica). UUIDs gerados por `gen_random_uuid()` (Postgres) são v4 — ok. Mas UUIDs de integrações externas (Strava `activity_id` legado) **não são UUIDs**, são inteiros. Se algum schema aceita IDs externos como `z.string().uuid()`, vai quebrar.
- **Risco:** Forms/endpoints quebrarem silenciosamente após upgrade de Zod.
- **Correção:** Auditar todos `z.string().uuid()` contra o schema do banco. Para IDs de integrações externas não-UUID, usar `z.string().min(1).max(100)` ou regex específico.

---

### [2.13] `/api/inngest` — Não existe no código
- **Camada:** N/A
- **Veredicto:** ⚪ **NÃO APLICÁVEL**
- **Achado:** O prompt original referenciava Inngest (Clinipharma). **Omni Runner usa `pg_cron` + Supabase Edge Functions**, não Inngest. Não há `/api/inngest` em `portal/src/app/api/`.
- **Correção:** N/A (este item não se aplica ao projeto).

---

### [2.14] `pg_cron` jobs — Lock contention
- **Camada:** BACKEND
- **Persona principal impactada:** Todos
- **Veredicto:** ⚪ **NÃO AUDITADO NESTA PARTE** (ver LENTE 12)
- **Achado:** Migration `20260221000008_clearing_cron.sql` existe. Análise detalhada em [12.x].

---

### [2.15] `getRedis()` — Module-level cache vs runtime config
- **Camada:** PORTAL
- **Veredicto:** 🟡 **MÉDIO** (duplica 1.21)
- **Correção:** Ver [1.21].

---

## LENTE 3 — CFO: INTEGRIDADE DO DINHEIRO

### [3.1] Divergência de fórmula de fee — TS vs SQL
- **Camada:** PORTAL + BACKEND
- **Persona principal impactada:** Plataforma (receita), Assessoria (pagamentos)
- **Veredicto:** 🔴 **CRÍTICO**
- **Achado:**
  - `portal/src/lib/clearing.ts:115`: `const feeUsd = Math.round(grossUsd * feeRate) / 100;` ← fórmula **legada**.
  - `supabase/migrations/20260303100000_gateway_fee_backing_fix.sql:45-46` mudou `execute_burn_atomic` para `ROUND(v_gross * v_fee_rate / 100, 2)`.
  - `processBurnForClearing` (clearing.ts:57-173) **não é mais chamado** se o fluxo correto usa `executeBurnAtomic` (linha 186-202). Mas o código TS persiste no repo e pode ser chamado por legacy callers.
  - Para `grossUsd = 33.33, feeRate = 3.0`:
    - TS (`Math.round(33.33 * 3.0) / 100`) = `Math.round(99.99) / 100` = `100 / 100` = `1.00`
    - SQL novo (`ROUND(33.33 * 3.0 / 100, 2)`) = `ROUND(0.9999, 2)` = `1.00`
    - **OK neste caso**. Mas para `grossUsd = 16.665, feeRate = 3.0`:
    - TS: `Math.round(49.995) / 100` → **JS `Math.round` usa round-half-away-from-zero**: `Math.round(49.995) = 50` → fee=0.50
    - SQL: `ROUND(0.49995, 2)` → Postgres usa **banker's rounding (half-to-even)**: `ROUND(0.49995, 2) = 0.50`
    - Igual neste caso.
    - Para `grossUsd = 50.005, feeRate = 3.0`:
    - TS: `Math.round(150.015) / 100 = 150/100 = 1.50`
    - SQL: `ROUND(50.005 * 3.0 / 100, 2) = ROUND(1.50015, 2) = 1.50` (banker rounds towards even)
    - Problemas reais aparecem em boundaries: JS e Postgres numeric podem divergir em casos com IEEE 754 imprecisão (`50.005 * 3.0 = 150.01499999...` em IEEE 754 vs exato em Postgres numeric).
- **Risco:** Divergência entre receita esperada (cálculo TS no portal/UI) e receita real (cálculo SQL durante burn). Centavos por burn × milhares de burns/mês = desvio significativo em relatórios. CFO reporta números diferentes do DB.
- **Correção:**
  1. Remover `Math.round(x * y) / 100` e substituir por helper que replica a semântica de `numeric(14,2)`:
  ```typescript
  // portal/src/lib/money.ts
  export function roundCents(value: number): number {
    // Replica Postgres ROUND(value, 2) com banker's rounding
    const x = value * 100;
    const rounded = Math.abs(x % 1) === 0.5
      ? (Math.floor(x) % 2 === 0 ? Math.floor(x) : Math.ceil(x))
      : Math.round(x);
    return rounded / 100;
  }
  export function calcFee(gross: number, ratePct: number): number {
    return roundCents(gross * ratePct / 100);
  }
  ```
  2. Melhor: mover **todo** cálculo financeiro para SQL. TS só exibe valor já calculado.
  3. Adicionar teste property-based que compara cálculo TS vs SQL para 10k valores aleatórios.

---

### [3.2] Congelamento de preços / taxas
- **Camada:** BACKEND
- **Persona principal impactada:** Plataforma, Assessoria
- **Veredicto:** 🟠 **ALTO**
- **Achado:**
  - `execute_burn_atomic` (migration 20260228160001:139-142) lê `rate_pct` de `platform_fee_config` **no momento do burn**, não no momento da emissão das coins.
  - Se a plataforma reduzir `clearing` de 3.0% para 1.0% entre emissão (hoje) e queima (daqui 6 meses), as coins "em trânsito" no ecossistema ganham fee histórico diferente do previsto na hora da emissão.
  - **Não existe** coluna `fee_rate_pct_frozen` em `coin_ledger` para registrar a taxa vigente na emissão.
  - Contra-argumento: essa é a semântica do modelo (taxa aplicada no ato do clearing), e plataforma pode defender isso comercialmente.
- **Risco:** Assessorias contestam se taxa sobe inesperadamente. CFO precisa justificar o rate usado em cada settlement.
- **Correção:** Adicionar `fee_rate_pct_snapshot` em `clearing_settlements` (já existe: `fee_rate_pct` — linha 127 do clearing.ts). Confirmar que é o rate no momento do settle, não da emissão. Se quiser congelar no ato da emissão: adicionar `clearing_fee_rate_pct` em `coin_ledger` e reading ali em vez de `platform_fee_config`.

---

### [3.3] `execute_withdrawal` — `total_deposited_usd -= amount_usd` não contabiliza fee do provider
- **Camada:** BACKEND
- **Persona principal impactada:** Assessoria, Plataforma
- **Veredicto:** 🟠 **ALTO**
- **Achado:**
  - `createWithdrawal` (`portal/src/lib/custody.ts:324-370`) calcula `localAmount = convertFromUsdWithSpread(amountUsd - providerFee, fxRate, spreadPct)` — o `providerFeeUsd` reduz o USD antes de converter para local.
  - `execute_withdrawal` (migration 20260228170000:120-123) faz `total_deposited_usd -= v_amount` onde `v_amount = amount_usd = input gross`. 
  - **Não deduz o providerFeeUsd da custódia**. O USD "real" debitado é `amount_usd`, mas apenas `amount_usd - providerFee - spread` chega à assessoria em USD convertido. **Quem absorve os `providerFee` USD? Ninguém, contabilmente.** A tabela `platform_revenue` só recebe `fx_spread`, não `provider_fee_usd`.
- **Risco:** Buraco contábil: USD some da custódia mas não aparece nem como revenue nem como saque. Invariante contábil quebra no balanço total. CFO não consegue explicar.
- **Correção:** Inserir em `platform_revenue` também o `provider_fee_usd` (category `'provider_fee'` ou similar) — mesmo que a plataforma só passe esse dinheiro adiante, precisa ser registrado:
```sql
IF v_provider_fee > 0 THEN
  INSERT INTO platform_revenue (fee_type, amount_usd, source_ref_id, group_id, description)
  VALUES ('provider_fee', v_provider_fee, p_withdrawal_id::text, v_group_id, 'Gateway fee on withdrawal');
END IF;
```
Expandir CHECK de `fee_type` para incluir `'provider_fee'`.

---

### [3.4] 1 Coin = US$ 1.00 (peg enforcement)
- **Camada:** BACKEND
- **Veredicto:** 🟢 **SEGURO**
- **Achado:** `supabase/migrations/20260303100000:24-26`:
```sql
ALTER TABLE public.custody_deposits
  ADD CONSTRAINT chk_peg_1_to_1
    CHECK (amount_usd = coins_equivalent::numeric);
```
**Excelente** — garante ao nível do banco que nenhum depósito pode emitir coins acima do lastro USD recebido líquido.
- **Correção:** N/A.

---

### [3.5] Gateway fee na emissão — `chk_gross_fee_net`
- **Camada:** BACKEND
- **Veredicto:** 🟢 **SEGURO**
- **Achado:** `20260303100000:30-34` garante `gross = net + fee`. Coerente com o modelo Option B (assessoria paga bruto, platform recebe net após Stripe/MP).
- **Correção:** N/A.

---

### [3.6] FX spread — Cálculo simétrico entrada/saída
- **Camada:** PORTAL
- **Veredicto:** 🟡 **MÉDIO**
- **Achado:** `portal/src/lib/custody.ts:214-243`:
  - **Entrada (`convertToUsdWithSpread`):** `rawUsd = localAmount / fxRate; spreadUsd = rawUsd * (spread/100); amountUsd = rawUsd - spreadUsd`.
  - **Saída (`convertFromUsdWithSpread`):** `spreadUsd = amountUsd * (spread/100); netUsd = amountUsd - spreadUsd; localAmount = netUsd * fxRate`.
  
  Em entrada, o spread é descontado de `rawUsd` (USD bruto); em saída, é descontado de `amountUsd` (USD bruto também). **A aplicação é consistente** (platform cobra spread nos dois sentidos).
  
  Porém: um round-trip (deposit $100 local → withdraw mesma quantia) resulta em perda composta: `depositUsd = 100/fx * (1-s); withdrawLocal = depositUsd * (1-s) * fx = 100 * (1-s)² ≈ 100 - 2s*100`. Com s=0.75%, perda = ~1.5% por round-trip. Esperado pelo modelo. Documentar.
- **Risco:** Baixo-médio — usuários podem achar que perda é 0.75% (single leg) e se surpreender com 1.5% round-trip.
- **Correção:** Documentar em ajuda/FAQ. Opcional: cobrar spread só no on-ramp (entrada), mantendo saída a FX mid-market.

---

### [3.7] Cupom 100% / pedido de $0.00
- **Camada:** PORTAL
- **Persona principal impactada:** Atleta, Plataforma
- **Veredicto:** ⚪ **NÃO AUDITADO** — `billing_auto_topup_settings` sugere fluxo de compra que não foi auditado nesta parte.
- **Correção:** Auditar `create-checkout-session` e `create-checkout-mercadopago` Edge Functions. Confirmar que rejeitam `price_cents = 0`.

---

### [3.8] Custody `check_custody_invariants` — Valida R_i vs M_i mas não total_settled
- **Camada:** BACKEND
- **Persona principal impactada:** Plataforma
- **Veredicto:** 🟡 **MÉDIO**
- **Achado:** `20260228170000:273-322` valida:
  1. `committed ≥ 0`, `deposited ≥ 0`, `deposited ≥ committed`.
  2. `total_committed = SUM(coin_ledger.delta_coins WHERE issuer=X)`.
  
  **Não valida:**
  - `total_settled_usd` não é comparado com soma de settlements `status='settled'`.
  - Não há check de conservação global: `SUM(total_deposited_usd) = SUM(custody_deposits confirmed) - SUM(custody_withdrawals completed) + SUM(clearing flows) - SUM(platform_revenue)`.
- **Risco:** Drift acumulativo não-detectado. Após meses, somas globais divergem da contabilidade sintética.
- **Correção:** Expandir `check_custody_invariants` com conservação global:
```sql
-- Check 3: global conservation
SELECT NULL::uuid, ..., 'global_deposit_mismatch'
WHERE (SELECT SUM(total_deposited_usd) FROM custody_accounts)
   <> (SELECT SUM(amount_usd) FROM custody_deposits WHERE status='confirmed')
      - (SELECT SUM(amount_usd) FROM custody_withdrawals WHERE status='completed')
      - (SELECT SUM(amount_usd) FROM platform_revenue);
```

---

### [3.9] `platform_revenue.fee_type` CHECK
- **Camada:** BACKEND
- **Veredicto:** 🟠 **ALTO**
- **Achado:** `20260228170000:11`: CHECK `('clearing', 'swap', 'fx_spread', 'maintenance')` — **não inclui `'billing_split'` nem `'provider_fee'`**. `platform_revenue` insere `fee_type='clearing'`, `'swap'`, `'fx_spread'`. Maintenance é inserido por `asaas-webhook/index.ts:216+` (não totalmente lido). Se `billing_split` for inserido, CHECK rejeita — perda silenciosa.
- **Risco:** Insert falha, erro engolido (várias rotas têm `try/catch`), receita não registrada.
- **Correção:** Alinhar CHECK de `platform_revenue.fee_type` com `platform_fee_config.fee_type`:
```sql
ALTER TABLE platform_revenue DROP CONSTRAINT platform_revenue_fee_type_check;
ALTER TABLE platform_revenue ADD CONSTRAINT platform_revenue_fee_type_check
  CHECK (fee_type IN ('clearing','swap','maintenance','billing_split','fx_spread','provider_fee'));
```

---

### [3.10] `custody_commit_coins` — Reserva ANTES de crédito ao atleta
- **Camada:** BACKEND + PORTAL
- **Veredicto:** 🟡 **MÉDIO**
- **Achado:** O flow atual é: `custody_commit_coins` (reserva R) → `decrement_token_inventory` (decremento de inventário do grupo) → `increment_wallet_balance` (atleta recebe). Se qualquer etapa após (1) falhar, `R_i` fica elevado sem coin correspondente. A invariante R=M é quebrada temporariamente.
- **Risco:** Janela de inconsistência entre etapas (não-atomic — ver [2.1]).
- **Correção:** Ver [2.1] e [1.3] — migrar para `distribute_coins_atomic` em SQL.

---

### [3.11] Pedido de R$ 0 via cupom 100% (duplica 3.7)
- **Veredicto:** ⚪ **NÃO AUDITADO**

---

### [3.12] `clearing_settlements` — Fees concedidas nulas
- **Camada:** BACKEND
- **Veredicto:** 🟢 **SEGURO**
- **Achado:** `settle_clearing` (`20260228170000:186-190`) só insere em `platform_revenue` se `v_fee > 0`. Para fee_rate=0 (custom), nenhum insert. OK.
- **Correção:** N/A.

---

### [3.13] Reembolso / Estorno — Não há função `reverse_burn` ou `refund_deposit`
- **Camada:** BACKEND
- **Persona principal impactada:** Atleta, Assessoria, Plataforma
- **Veredicto:** 🔴 **CRÍTICO**
- **Achado:** Grepping por `refund`, `reverse`, `chargeback` em `supabase/migrations/` não encontra funções de reversão de: (a) emissão de coins após chargeback do gateway; (b) burn (coins queimadas por engano); (c) withdrawal falha externamente.
- **Risco:** Chargeback Stripe/MP deixa coins emitidas sem lastro ↔ invariante quebra. Sem função de reversão, admin precisa fazer SQL manual — erro humano catastrófico.
- **Correção:** Criar funções:
```sql
CREATE FUNCTION reverse_custody_deposit(p_deposit_id uuid, p_reason text)
  RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- 1. Lock deposit, verify status='confirmed'
  -- 2. Set status='refunded'
  -- 3. UPDATE custody_accounts SET total_deposited_usd -= amount_usd (with FOR UPDATE)
  -- 4. If total_committed > total_deposited, raise exception (can't refund what's already circulating)
  -- 5. INSERT INTO audit_log
END; $$;

CREATE FUNCTION reverse_burn(p_ref_id uuid, p_reason text) ...
CREATE FUNCTION reverse_withdrawal(p_withdrawal_id uuid, p_reason text) ...
```

---

### [3.14] Cancelamento após `PAYMENT_CONFIRMED`
- **Camada:** BACKEND
- **Veredicto:** ⚪ **NÃO AUDITADO** — depende do endpoint de cancelamento de subscription.

---

### [3.15] Pedido eternamente pendente
- **Camada:** BACKEND
- **Persona principal impactada:** Atleta
- **Veredicto:** 🟡 **MÉDIO**
- **Achado:** `custody_deposits.status='pending'` sem cron que expira. Em casos reais, Stripe pode enviar webhook muito depois, ou nunca.
- **Correção:** Cron `expire-stale-deposits` que marca `status='expired'` após 48h sem confirmação. Separar de `refunded` (que exige ação explícita).

---

### [3.16] Consistência entrada–saída de FX
- **Camada:** PORTAL
- **Veredicto:** 🟡 **MÉDIO** (duplica 1.2/3.6)
- **Correção:** Remover `fx_rate` do client-side; buscar rate server-side.

---

### [3.17] Arredondamento IEEE 754 em TypeScript
- **Camada:** PORTAL
- **Veredicto:** 🟠 **ALTO**
- **Achado:** `portal/src/lib/custody.ts:223,224,240,241,115 (clearing.ts),56 (swap.ts)`: uso generalizado de `Math.round(x * 100) / 100`. Para valores onde `x * 100` não é representável exatamente (IEEE 754), há erro silencioso:
  - `0.1 + 0.2 = 0.30000000000000004` — `Math.round(0.30000000000000004 * 100) / 100 = 0.3` ✓
  - `1.005 * 100 = 100.49999999999999` (**não 100.5**) → `Math.round(100.4999...) = 100` → `1.00` (**esperado 1.01 bancário**)
- **Risco:** Centavos faltantes em operações de saldo formatadas para display. Divergência UI vs DB.
- **Correção:** Usar library `decimal.js` ou `big.js` para toda matemática financeira no TS. Exemplo:
```typescript
import Decimal from "decimal.js";
Decimal.set({ rounding: Decimal.ROUND_HALF_EVEN }); // banker's
export function roundCents(v: number | string): number {
  return new Decimal(v).toDecimalPlaces(2, Decimal.ROUND_HALF_EVEN).toNumber();
}
```

---

### [3.18] `coin_ledger.delta_coins` — Tipo integer
- **Camada:** BACKEND
- **Veredicto:** 🟢 **SEGURO**
- **Achado:** `coin_ledger.delta_coins integer` (migration base 20260221000022). Integer evita IEEE 754 e arredondamento. Bom design. Peg 1 coin = $1 USD → coin count = USD integer.
- **Correção:** N/A.

---

### [3.19] NFS-e / fiscal — Não observado
- **Camada:** N/A
- **Veredicto:** ⚪ **NÃO APLICÁVEL / NÃO AUDITADO**
- **Achado:** Não encontrei integração com Nuvem Fiscal ou qualquer provedor de NFS-e no repo. O modelo B2B de custódia/clearing gera **receita da plataforma** (platform_revenue) — essa receita é sujeita a PIS/COFINS/ISS no Brasil. Não ver código de emissão fiscal é uma bandeira de "não-conformidade operacional".
- **Risco:** Receita Federal / prefeitura autua a plataforma por falta de emissão de NFS-e sobre fees B2B.
- **Correção:** Consultar contador e implementar emissão mensal de NFS-e sobre agregado de `platform_revenue` para cada assessoria (devedor). Adicionar job `monthly-invoice-generation`.

---

### [3.20] Disputa / chargeback Stripe
- **Camada:** BACKEND
- **Persona principal impactada:** Plataforma, Assessoria
- **Veredicto:** 🔴 **CRÍTICO**
- **Achado:** `supabase/functions/asaas-webhook/index.ts` mapeia `PAYMENT_REFUNDED → cancelled` mas isso só altera `coaching_subscriptions.status`. **Não reverte custody_deposit nem retira coins já emitidas**. Para custody webhooks (`/api/custody/webhook` Stripe/MP), nenhum caminho trata `payment_intent.succeeded` vs `charge.dispute.created` — apenas confirma depósitos.
- **Risco:** Chargeback 60-120 dias após depósito: dinheiro volta ao usuário, mas coins já foram distribuídas a atletas. Invariante quebrada, plataforma absorve prejuízo.
- **Correção:** Adicionar handler de `charge.dispute.created` e `charge.refunded` no webhook:
```typescript
if (event.type === "charge.dispute.created" || event.type === "charge.refunded") {
  await db.rpc("reverse_custody_deposit", { p_deposit_id, p_reason: event.type });
}
```
Se o deposit já tem coins committed > 0 e atletas gastaram: `reverse_custody_deposit` falha → notifica platform_admin + abre caso de `clearing_cases` para resolução manual.

---

## Fim da PARTE 2 de 8

**Resumo da PARTE 2 (Lentes 2-3 — CTO + CFO):**
- 🔴 **Críticos:** 5 — [2.1 non-atomic distribute], [2.2 burn atomic swallows exceptions], [2.9 migration drift], [3.1 TS vs SQL fee formula], [3.13 no refund/reverse functions], [3.20 chargeback não tratado]
- 🟠 **Altos:** 5 — [2.6 withdrawal stuck processing], [2.8 realtime cross-tenant], [2.10 Vercel timeout batch], [3.2 fee snapshot], [3.3 provider_fee bookkeeping], [3.9 platform_revenue CHECK], [3.17 IEEE 754]
- 🟡 **Médios:** 7 — [2.3, 2.7, 2.11, 2.12, 2.15, 3.6, 3.8, 3.10, 3.15, 3.16]
- 🟢 **Seguros:** 5 — [2.4, 2.5, 3.4, 3.5, 3.12, 3.18]
- ⚪ **Não auditados:** 4 — [2.13 N/A, 2.14, 3.7, 3.11, 3.14, 3.19]

**Total até aqui:** 70 itens analisados (50 Lente 1 + 20 Lentes 2-3).

---

**CONTINUA NA PARTE 3** — Lentes 4 (CLO — LGPD) e 5 (CPO — Produto/Edge cases), ~35 itens.

Digite **"continue"** para prosseguir para a PARTE 3.