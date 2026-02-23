# QA_PHASE_16_17.md — Smoke Tests (Backend + Frontend)

> **Sprint:** 16.99.0
> **Data:** 2026-02-21
> **Escopo:** Phase 16 (Assessoria Mode) + Phase 17 (Backend Supabase)
> **Método:** curl reprodutível + checklist frontend com estados esperados

---

## PRE-REQUISITOS

```bash
# ── Variáveis de ambiente (ajustar para seu projeto) ──
export SUPA_URL="https://<project-ref>.supabase.co"
export SUPA_ANON="<anon_key>"
export SUPA_SERVICE="<service_role_key>"

# ── Usuários de teste (criados via auth.users) ──
# STAFF_A  = admin_master do GROUP_A (uid: $STAFF_A_UID, jwt: $STAFF_A_JWT)
# STAFF_B  = admin_master do GROUP_B (uid: $STAFF_B_UID, jwt: $STAFF_B_JWT)
# ATHLETE_A = atleta do GROUP_A    (uid: $ATH_A_UID,   jwt: $ATH_A_JWT)
# ATHLETE_B = atleta do GROUP_B    (uid: $ATH_B_UID,   jwt: $ATH_B_JWT)

# ── Criar JWTs de teste ──
# Via Supabase Dashboard > Authentication > Users > copy Access Token
# Ou via:
# curl -s -X POST "$SUPA_URL/auth/v1/token?grant_type=password" \
#   -H "apikey: $SUPA_ANON" -H "Content-Type: application/json" \
#   -d '{"email":"staff_a@test.com","password":"Test1234!"}' | jq -r '.access_token'

export GROUP_A="<uuid>"
export GROUP_B="<uuid>"
```

### Seed Mínimo (SQL via Dashboard ou psql)

```sql
-- Garantir que GROUP_A tenha inventário
INSERT INTO coaching_token_inventory (group_id, available_tokens)
VALUES ('GROUP_A_UUID', 1000)
ON CONFLICT (group_id)
DO UPDATE SET available_tokens = 1000;

-- Garantir wallets existem
INSERT INTO wallets (user_id, balance_coins, pending_coins)
VALUES ('ATH_A_UUID', 100, 0)
ON CONFLICT (user_id)
DO UPDATE SET balance_coins = 100, pending_coins = 0;

INSERT INTO wallets (user_id, balance_coins, pending_coins)
VALUES ('ATH_B_UUID', 50, 0)
ON CONFLICT (user_id)
DO UPDATE SET balance_coins = 50, pending_coins = 0;
```

---

## SEÇÃO A — BACKEND (curl)

### A.1 — Token ISSUE: create intent → consume → wallet aumenta

```bash
# ── A.1.1 Staff cria intent ISSUE_TO_ATHLETE ──
NONCE_ISSUE=$(uuidgen)
EXPIRES_ISSUE=$(date -u -d "+5 minutes" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || date -u -v+5M +%Y-%m-%dT%H:%M:%SZ)

curl -s -X POST "$SUPA_URL/functions/v1/token-create-intent" \
  -H "Authorization: Bearer $STAFF_A_JWT" \
  -H "apikey: $SUPA_ANON" \
  -H "Content-Type: application/json" \
  -d "{
    \"group_id\": \"$GROUP_A\",
    \"type\": \"ISSUE_TO_ATHLETE\",
    \"amount\": 10,
    \"nonce\": \"$NONCE_ISSUE\",
    \"expires_at_iso\": \"$EXPIRES_ISSUE\"
  }" | jq .

# ✅ ESPERADO: { "intent_id": "...", "nonce": "$NONCE_ISSUE", "status": "OPEN", "expires_at": "..." }
```

```bash
# ── A.1.2 Verificar wallet ANTES ──
curl -s "$SUPA_URL/rest/v1/wallets?user_id=eq.$ATH_A_UID&select=balance_coins,pending_coins" \
  -H "Authorization: Bearer $ATH_A_JWT" \
  -H "apikey: $SUPA_ANON" | jq .

# ANOTAR: balance_coins = X_ANTES
```

```bash
# ── A.1.3 Atleta consome intent ──
curl -s -X POST "$SUPA_URL/functions/v1/token-consume-intent" \
  -H "Authorization: Bearer $ATH_A_JWT" \
  -H "apikey: $SUPA_ANON" \
  -H "Content-Type: application/json" \
  -d "{\"nonce\": \"$NONCE_ISSUE\"}" | jq .

# ✅ ESPERADO: { "status": "consumed", "type": "ISSUE_TO_ATHLETE", "amount": 10 }
```

```bash
# ── A.1.4 Verificar wallet DEPOIS ──
curl -s "$SUPA_URL/rest/v1/wallets?user_id=eq.$ATH_A_UID&select=balance_coins,pending_coins" \
  -H "Authorization: Bearer $ATH_A_JWT" \
  -H "apikey: $SUPA_ANON" | jq .

# ✅ ESPERADO: balance_coins = X_ANTES + 10
```

```bash
# ── A.1.5 Verificar ledger ──
curl -s "$SUPA_URL/rest/v1/coin_ledger?user_id=eq.$ATH_A_UID&reason=eq.institution_token_issue&order=created_at_ms.desc&limit=1" \
  -H "Authorization: Bearer $ATH_A_JWT" \
  -H "apikey: $SUPA_ANON" | jq .

# ✅ ESPERADO: delta_coins = 10, reason = "institution_token_issue"
```

```bash
# ── A.1.6 Replay attempt (anti-replay) ──
curl -s -X POST "$SUPA_URL/functions/v1/token-consume-intent" \
  -H "Authorization: Bearer $ATH_A_JWT" \
  -H "apikey: $SUPA_ANON" \
  -H "Content-Type: application/json" \
  -d "{\"nonce\": \"$NONCE_ISSUE\"}" | jq .

# ✅ ESPERADO: { "status": "already_consumed" } — nonce não é reutilizado
```

**Resultado A.1:** [ ] PASS / [ ] FAIL — Anotações: _________________

---

### A.2 — Token BURN: create intent → consume → wallet diminui

```bash
# ── A.2.1 Staff cria intent BURN_FROM_ATHLETE ──
NONCE_BURN=$(uuidgen)
EXPIRES_BURN=$(date -u -d "+5 minutes" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || date -u -v+5M +%Y-%m-%dT%H:%M:%SZ)

curl -s -X POST "$SUPA_URL/functions/v1/token-create-intent" \
  -H "Authorization: Bearer $STAFF_A_JWT" \
  -H "apikey: $SUPA_ANON" \
  -H "Content-Type: application/json" \
  -d "{
    \"group_id\": \"$GROUP_A\",
    \"type\": \"BURN_FROM_ATHLETE\",
    \"amount\": 5,
    \"nonce\": \"$NONCE_BURN\",
    \"expires_at_iso\": \"$EXPIRES_BURN\"
  }" | jq .

# ✅ ESPERADO: status "OPEN"
```

```bash
# ── A.2.2 Wallet ANTES ──
curl -s "$SUPA_URL/rest/v1/wallets?user_id=eq.$ATH_A_UID&select=balance_coins" \
  -H "Authorization: Bearer $ATH_A_JWT" \
  -H "apikey: $SUPA_ANON" | jq .[0].balance_coins

# ANOTAR: balance_coins = Y_ANTES
```

```bash
# ── A.2.3 Atleta consome (queima) ──
curl -s -X POST "$SUPA_URL/functions/v1/token-consume-intent" \
  -H "Authorization: Bearer $ATH_A_JWT" \
  -H "apikey: $SUPA_ANON" \
  -H "Content-Type: application/json" \
  -d "{\"nonce\": \"$NONCE_BURN\"}" | jq .

# ✅ ESPERADO: { "status": "consumed", "type": "BURN_FROM_ATHLETE", "amount": 5 }
```

```bash
# ── A.2.4 Wallet DEPOIS ──
curl -s "$SUPA_URL/rest/v1/wallets?user_id=eq.$ATH_A_UID&select=balance_coins" \
  -H "Authorization: Bearer $ATH_A_JWT" \
  -H "apikey: $SUPA_ANON" | jq .[0].balance_coins

# ✅ ESPERADO: balance_coins = Y_ANTES - 5
```

```bash
# ── A.2.5 Verificar ledger ──
curl -s "$SUPA_URL/rest/v1/coin_ledger?user_id=eq.$ATH_A_UID&reason=eq.institution_token_burn&order=created_at_ms.desc&limit=1" \
  -H "Authorization: Bearer $ATH_A_JWT" \
  -H "apikey: $SUPA_ANON" | jq .

# ✅ ESPERADO: delta_coins = -5, reason = "institution_token_burn"
```

**Resultado A.2:** [ ] PASS / [ ] FAIL — Anotações: _________________

---

### A.3 — Troca de Assessoria → queima automática de OmniCoins

```bash
# ── A.3.1 Wallet ANTES ──
curl -s "$SUPA_URL/rest/v1/wallets?user_id=eq.$ATH_A_UID&select=balance_coins,pending_coins" \
  -H "Authorization: Bearer $ATH_A_JWT" \
  -H "apikey: $SUPA_ANON" | jq .

# ANOTAR: balance_coins = Z_ANTES (deve ser > 0 para teste significativo)
```

```bash
# ── A.3.2 Trocar assessoria (GROUP_A → GROUP_B) ──
curl -s -X POST "$SUPA_URL/rest/v1/rpc/fn_switch_assessoria" \
  -H "Authorization: Bearer $ATH_A_JWT" \
  -H "apikey: $SUPA_ANON" \
  -H "Content-Type: application/json" \
  -d "{\"p_new_group_id\": \"$GROUP_B\"}" | jq .

# ✅ ESPERADO: { "status": "switched", "burned": Z_ANTES }
```

```bash
# ── A.3.3 Wallet DEPOIS ──
curl -s "$SUPA_URL/rest/v1/wallets?user_id=eq.$ATH_A_UID&select=balance_coins,pending_coins" \
  -H "Authorization: Bearer $ATH_A_JWT" \
  -H "apikey: $SUPA_ANON" | jq .

# ✅ ESPERADO: balance_coins = 0
```

```bash
# ── A.3.4 Verificar ledger de queima ──
curl -s "$SUPA_URL/rest/v1/coin_ledger?user_id=eq.$ATH_A_UID&reason=eq.institution_switch_burn&order=created_at_ms.desc&limit=1" \
  -H "Authorization: Bearer $ATH_A_JWT" \
  -H "apikey: $SUPA_ANON" | jq .

# ✅ ESPERADO: delta_coins = -Z_ANTES, reason = "institution_switch_burn"
```

```bash
# ── A.3.5 Idempotência (trocar para mesmo grupo) ──
curl -s -X POST "$SUPA_URL/rest/v1/rpc/fn_switch_assessoria" \
  -H "Authorization: Bearer $ATH_A_JWT" \
  -H "apikey: $SUPA_ANON" \
  -H "Content-Type: application/json" \
  -d "{\"p_new_group_id\": \"$GROUP_B\"}" | jq .

# ✅ ESPERADO: { "status": "already_member", "burned": 0 }
```

**Resultado A.3:** [ ] PASS / [ ] FAIL — Anotações: _________________

---

### A.4 — Desafio cross-assessoria → prêmio pendente + clearing case

> **Pré-condição:** Criar desafio 1v1 entre ATH_A (GROUP_A) e ATH_B (GROUP_B) com
> entry_fee > 0, aguardar conclusão, e chamar settle-challenge.

```bash
# ── A.4.1 Verificar pending no wallet do vencedor ──
# (Após settle-challenge com desafio cross-assessoria)
curl -s "$SUPA_URL/rest/v1/wallets?user_id=eq.$WINNER_UID&select=balance_coins,pending_coins" \
  -H "Authorization: Bearer $WINNER_JWT" \
  -H "apikey: $SUPA_ANON" | jq .

# ✅ ESPERADO: pending_coins > 0 (prêmio do pool aguardando clearing)
```

```bash
# ── A.4.2 Verificar ledger com reason = challenge_prize_pending ──
curl -s "$SUPA_URL/rest/v1/coin_ledger?user_id=eq.$WINNER_UID&reason=eq.challenge_prize_pending&order=created_at_ms.desc&limit=1" \
  -H "Authorization: Bearer $WINNER_JWT" \
  -H "apikey: $SUPA_ANON" | jq .

# ✅ ESPERADO: delta_coins > 0, reason = "challenge_prize_pending"
```

```bash
# ── A.4.3 Verificar clearing_case criado ──
curl -s "$SUPA_URL/rest/v1/clearing_cases?status=eq.OPEN&order=created_at.desc&limit=1" \
  -H "Authorization: Bearer $STAFF_A_JWT" \
  -H "apikey: $SUPA_ANON" | jq .

# ✅ ESPERADO: case com from_group_id e to_group_id, status = "OPEN"
# ANOTAR: case_id = $CASE_ID
```

**Resultado A.4:** [ ] PASS / [ ] FAIL — Anotações: _________________

---

### A.5 — Clearing: confirm-sent + confirm-received → pending vira disponível

```bash
# ── A.5.1 Staff da assessoria devedora confirma envio ──
curl -s -X POST "$SUPA_URL/functions/v1/clearing-confirm-sent" \
  -H "Authorization: Bearer $STAFF_LOSING_JWT" \
  -H "apikey: $SUPA_ANON" \
  -H "Content-Type: application/json" \
  -d "{\"case_id\": \"$CASE_ID\"}" | jq .

# ✅ ESPERADO: { "case_id": "...", "status": "SENT_CONFIRMED" }
```

```bash
# ── A.5.2 Staff da assessoria credora confirma recebimento ──
curl -s -X POST "$SUPA_URL/functions/v1/clearing-confirm-received" \
  -H "Authorization: Bearer $STAFF_WINNING_JWT" \
  -H "apikey: $SUPA_ANON" \
  -H "Content-Type: application/json" \
  -d "{\"case_id\": \"$CASE_ID\"}" | jq .

# ✅ ESPERADO: { "case_id": "...", "status": "PAID_CONFIRMED", "released_total": N }
```

```bash
# ── A.5.3 Verificar wallet do vencedor: pending → balance ──
curl -s "$SUPA_URL/rest/v1/wallets?user_id=eq.$WINNER_UID&select=balance_coins,pending_coins" \
  -H "Authorization: Bearer $WINNER_JWT" \
  -H "apikey: $SUPA_ANON" | jq .

# ✅ ESPERADO: pending_coins diminuiu (ou 0); balance_coins aumentou pelo mesmo valor
```

```bash
# ── A.5.4 Verificar ledger cleared ──
curl -s "$SUPA_URL/rest/v1/coin_ledger?user_id=eq.$WINNER_UID&reason=eq.challenge_prize_cleared&order=created_at_ms.desc&limit=1" \
  -H "Authorization: Bearer $WINNER_JWT" \
  -H "apikey: $SUPA_ANON" | jq .

# ✅ ESPERADO: delta_coins > 0, reason = "challenge_prize_cleared"
```

```bash
# ── A.5.5 Idempotência (re-confirm received) ──
curl -s -X POST "$SUPA_URL/functions/v1/clearing-confirm-received" \
  -H "Authorization: Bearer $STAFF_WINNING_JWT" \
  -H "apikey: $SUPA_ANON" \
  -H "Content-Type: application/json" \
  -d "{\"case_id\": \"$CASE_ID\"}" | jq .

# ✅ ESPERADO: { "status": "PAID_CONFIRMED", "idempotent": true }
```

**Resultado A.5:** [ ] PASS / [ ] FAIL — Anotações: _________________

---

### A.6 — Clearing: dispute → pending permanece

> **Pré-condição:** Criar novo clearing_case OPEN (A.4 com outro desafio).

```bash
# ── A.6.1 Wallet ANTES (verificar pending_coins do vencedor) ──
curl -s "$SUPA_URL/rest/v1/wallets?user_id=eq.$WINNER_UID&select=pending_coins" \
  -H "Authorization: Bearer $WINNER_JWT" \
  -H "apikey: $SUPA_ANON" | jq .[0].pending_coins

# ANOTAR: pending_antes = P
```

```bash
# ── A.6.2 Staff abre disputa ──
curl -s -X POST "$SUPA_URL/functions/v1/clearing-open-dispute" \
  -H "Authorization: Bearer $STAFF_A_JWT" \
  -H "apikey: $SUPA_ANON" \
  -H "Content-Type: application/json" \
  -d "{\"case_id\": \"$CASE_ID_2\", \"reason\": \"Valores discrepantes\"}" | jq .

# ✅ ESPERADO: { "case_id": "...", "status": "DISPUTED" }
```

```bash
# ── A.6.3 Wallet DEPOIS (pending inalterado) ──
curl -s "$SUPA_URL/rest/v1/wallets?user_id=eq.$WINNER_UID&select=pending_coins" \
  -H "Authorization: Bearer $WINNER_JWT" \
  -H "apikey: $SUPA_ANON" | jq .[0].pending_coins

# ✅ ESPERADO: pending_coins = P (inalterado — disputa não libera nem remove)
```

```bash
# ── A.6.4 Idempotência (re-dispute) ──
curl -s -X POST "$SUPA_URL/functions/v1/clearing-open-dispute" \
  -H "Authorization: Bearer $STAFF_B_JWT" \
  -H "apikey: $SUPA_ANON" \
  -H "Content-Type: application/json" \
  -d "{\"case_id\": \"$CASE_ID_2\"}" | jq .

# ✅ ESPERADO: { "status": "DISPUTED", "idempotent": true }
```

**Resultado A.6:** [ ] PASS / [ ] FAIL — Anotações: _________________

---

### A.7 — Intent expirado → rejeição correta

```bash
# ── A.7.1 Criar intent com expiração no passado ──
NONCE_EXP=$(uuidgen)
EXPIRES_PAST=$(date -u -d "-1 minute" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || date -u -v-1M +%Y-%m-%dT%H:%M:%SZ)

curl -s -X POST "$SUPA_URL/functions/v1/token-create-intent" \
  -H "Authorization: Bearer $STAFF_A_JWT" \
  -H "apikey: $SUPA_ANON" \
  -H "Content-Type: application/json" \
  -d "{
    \"group_id\": \"$GROUP_A\",
    \"type\": \"ISSUE_TO_ATHLETE\",
    \"amount\": 1,
    \"nonce\": \"$NONCE_EXP\",
    \"expires_at_iso\": \"$EXPIRES_PAST\"
  }" | jq .
```

```bash
# ── A.7.2 Tentar consumir (deve falhar com 410 INTENT_EXPIRED) ──
curl -s -X POST "$SUPA_URL/functions/v1/token-consume-intent" \
  -H "Authorization: Bearer $ATH_A_JWT" \
  -H "apikey: $SUPA_ANON" \
  -H "Content-Type: application/json" \
  -d "{\"nonce\": \"$NONCE_EXP\"}" | jq .

# ✅ ESPERADO: HTTP 410 — { "code": "INTENT_EXPIRED" }
```

```bash
# ── A.7.3 Wallet inalterada ──
curl -s "$SUPA_URL/rest/v1/wallets?user_id=eq.$ATH_A_UID&select=balance_coins" \
  -H "Authorization: Bearer $ATH_A_JWT" \
  -H "apikey: $SUPA_ANON" | jq .[0].balance_coins

# ✅ ESPERADO: Mesmo valor de antes
```

**Resultado A.7:** [ ] PASS / [ ] FAIL — Anotações: _________________

---

### A.8 — Gating: atleta não pode criar intent

```bash
curl -s -X POST "$SUPA_URL/functions/v1/token-create-intent" \
  -H "Authorization: Bearer $ATH_A_JWT" \
  -H "apikey: $SUPA_ANON" \
  -H "Content-Type: application/json" \
  -d "{
    \"group_id\": \"$GROUP_A\",
    \"type\": \"ISSUE_TO_ATHLETE\",
    \"amount\": 1,
    \"nonce\": \"$(uuidgen)\",
    \"expires_at_iso\": \"$(date -u -d '+5 minutes' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v+5M +%Y-%m-%dT%H:%M:%SZ)\"
  }" | jq .

# ✅ ESPERADO: HTTP 403 — { "code": "FORBIDDEN", "message": "Only staff can create intents" }
```

**Resultado A.8:** [ ] PASS / [ ] FAIL — Anotações: _________________

---

### A.9 — Clearing case expirado → pending permanece

> **Pré-condição:** Criar clearing_case com `deadline_at` no passado (via SQL direto).

```sql
-- Setup: inserir case com deadline já passado
UPDATE clearing_cases SET deadline_at = now() - INTERVAL '1 day'
WHERE id = '<CASE_ID_3>';
```

```bash
# ── A.9.1 Tentar confirm-sent no case expirado ──
curl -s -X POST "$SUPA_URL/functions/v1/clearing-confirm-sent" \
  -H "Authorization: Bearer $STAFF_LOSING_JWT" \
  -H "apikey: $SUPA_ANON" \
  -H "Content-Type: application/json" \
  -d "{\"case_id\": \"$CASE_ID_3\"}" | jq .

# ✅ ESPERADO: HTTP 410 — { "code": "CASE_EXPIRED" }
```

```bash
# ── A.9.2 Verificar wallet (pending inalterado) ──
curl -s "$SUPA_URL/rest/v1/wallets?user_id=eq.$WINNER_UID&select=pending_coins" \
  -H "Authorization: Bearer $WINNER_JWT" \
  -H "apikey: $SUPA_ANON" | jq .[0].pending_coins

# ✅ ESPERADO: pending_coins inalterado
```

**Resultado A.9:** [ ] PASS / [ ] FAIL — Anotações: _________________

---

## SEÇÃO B — FRONTEND (Flutter — Estados e Logs)

### B.1 — Wallet Screen: 3 estados

| # | Ação | Estado BLoC Esperado | UI Esperada |
|---|------|---------------------|-------------|
| B.1.1 | Abrir Wallet Screen | `WalletLoaded` | Card com Total, Disponível (verde), Pendente (laranja) |
| B.1.2 | Atleta com pending_coins > 0 | `WalletLoaded` | "Pendente" mostra valor > 0; mensagem italic "Aguardando confirmação entre assessorias" |
| B.1.3 | Atleta com pending_coins = 0 | `WalletLoaded` | "Pendente" = 0; sem mensagem italic |
| B.1.4 | Total = disponível + pendente | `WalletLoaded` | Soma correta no header |
| B.1.5 | Histórico com entry tipo `crossAssessoriaPending` | `WalletLoaded` | Label "Pendente (entre assessorias)" |
| B.1.6 | Histórico com entry tipo `crossAssessoriaCleared` | `WalletLoaded` | Label "Liberado (clearing confirmado)" |
| B.1.7 | Histórico com entry tipo `crossAssessoriaBurned` | `WalletLoaded` | Label "Invalidado (troca de assessoria)" |
| B.1.8 | Pull refresh | `WalletLoading` → `WalletLoaded` | Spinner → dados atualizados |

**Resultado B.1:** [ ] PASS / [ ] FAIL — Anotações: _________________

---

### B.2 — Minha Assessoria Screen

| # | Ação | Estado BLoC Esperado | UI Esperada |
|---|------|---------------------|-------------|
| B.2.1 | Abrir tela (atleta com 1 grupo) | `MyAssessoriaLoaded` | Assessoria atual exibida; lista de outras vazia |
| B.2.2 | Abrir tela (atleta com 2+ grupos) | `MyAssessoriaLoaded` | Assessoria atual + lista de alternativas |
| B.2.3 | Tap em "Trocar" em grupo alternativo | — | Modal AlertDialog com ícone warning laranja |
| B.2.4 | Modal: texto contém "invalidados" | — | "tokens da assessoria atual que não foram utilizados serão invalidados" |
| B.2.5 | Modal: confirmar troca | `MyAssessoriaSwitching` → `MyAssessoriaSwitched` | Spinner → mensagem de sucesso |
| B.2.6 | Modal: cancelar | volta a `MyAssessoriaLoaded` | Modal fecha, nada muda |

**Resultado B.2:** [ ] PASS / [ ] FAIL — Anotações: _________________

---

### B.3 — Staff QR Hub (Gating)

| # | Ação | Estado Esperado | UI Esperada |
|---|------|----------------|-------------|
| B.3.1 | Atleta tenta abrir "Operações QR (Staff)" via More | — | SnackBar: "Acesso restrito a staff..." |
| B.3.2 | Staff (admin_master) abre Hub | — | 3 cards: "Emitir Token", "Queimar Token", "Ativar Badge"; + "Ler QR Code" |
| B.3.3 | Staff (professor) abre Hub | — | Mesmo acesso que admin_master |
| B.3.4 | Staff (assistente) abre Hub | — | Mesmo acesso (isStaff = true) |
| B.3.5 | Info banner visível | — | Texto sobre nonce/expiração visível |

**Resultado B.3:** [ ] PASS / [ ] FAIL — Anotações: _________________

---

### B.4 — Gerar QR (Staff)

| # | Ação | Estado BLoC | UI Esperada |
|---|------|------------|-------------|
| B.4.1 | Tela "Emitir Token" aberta | `StaffQrInitial` | Ícone, descrição, seletor de quantidade, botão "Gerar QR" |
| B.4.2 | Ajustar quantidade (1→5) | `StaffQrInitial` | Número atualiza, botão "-" e "+" funcionam |
| B.4.3 | Tap "Gerar QR" | `StaffQrGenerating` → `StaffQrGenerated` | Spinner → QR code + countdown MM:SS |
| B.4.4 | Countdown decrementa | `StaffQrGenerated` | Timer diminui a cada segundo |
| B.4.5 | QR expira (countdown = 00:00) | `StaffQrGenerated` (expired) | QR substituído por overlay "QR Expirado" + ícone timer_off |
| B.4.6 | Tap "Gerar Novo" | `StaffQrInitial` | Volta ao formulário |
| B.4.7 | Tela "Ativar Badge" aberta | `StaffQrInitial` | Sem seletor de quantidade (fixo = 1) |

**Resultado B.4:** [ ] PASS / [ ] FAIL — Anotações: _________________

---

### B.5 — Escanear QR

| # | Ação | Estado BLoC | UI Esperada |
|---|------|------------|-------------|
| B.5.1 | Abrir tela Scan | `StaffQrInitial` | Câmera ativa com viewfinder |
| B.5.2 | Escanear QR válido | `StaffQrConsuming` → `StaffQrConsumed` | Spinner → SnackBar verde "Tokens recebidos" → pop |
| B.5.3 | Escanear QR expirado | `StaffQrError` | SnackBar vermelho "QR expirado" |
| B.5.4 | Escanear QR inválido (não OmniRunner) | `StaffQrError` | SnackBar "QR inválido" |
| B.5.5 | Escanear QR já consumido | `StaffQrError` | SnackBar com erro do servidor |
| B.5.6 | Texto informativo visível | — | "Aponte a câmera..." + "O QR possui validade limitada" |

**Resultado B.5:** [ ] PASS / [ ] FAIL — Anotações: _________________

---

### B.6 — Coaching Roles (UI Labels)

| # | Ação | UI Esperada |
|---|------|-------------|
| B.6.1 | Membro com role adminMaster | Label "Admin Master" |
| B.6.2 | Membro com role professor | Label "Professor" |
| B.6.3 | Membro com role assistente | Label "Assistente" |
| B.6.4 | Membro com role atleta | Label "Atleta" |

**Resultado B.6:** [ ] PASS / [ ] FAIL — Anotações: _________________

---

## SEÇÃO C — VERIFICAÇÕES GLOBAIS

### C.1 — Termos proibidos

```bash
# Verificar ausência de termos proibidos no código Flutter
cd /home/usuario/project-running/omni_runner
rg -i 'money|cashout|cash.out|aposta|bet\b|wager|ganhar dinheiro|sacar|withdraw|payout|jackpot|lottery|loteria|gambling|jogo de azar|dinheiro real|real money|prize pool|bolsa de prêmios|buy coins|comprar moedas|stake|staking|invest\b|investir' lib/ --type dart

# ✅ ESPERADO: 0 resultados
```

**Resultado C.1:** [ ] PASS / [ ] FAIL — Anotações: _________________

### C.2 — Flutter Analyze

```bash
cd /home/usuario/project-running/omni_runner
flutter analyze 2>&1 | grep -E "error|warning" | grep -v "info"

# ✅ ESPERADO: 0 errors, 0 warnings
```

**Resultado C.2:** [ ] PASS / [ ] FAIL — Anotações: _________________

### C.3 — Anti-replay: todo QR tem nonce + expiração

```bash
rg "nonce|expiresAtMs|expires_at" \
  lib/domain/entities/token_intent_entity.dart \
  lib/data/repositories_impl/stub_token_intent_repo.dart \
  lib/data/repositories_impl/remote_token_intent_repo.dart

# ✅ ESPERADO: nonce e expires_at presentes em payload, stub gera TTL, remote lê do servidor
```

**Resultado C.3:** [ ] PASS / [ ] FAIL — Anotações: _________________

---

## RESUMO

| Teste | Status |
|-------|--------|
| A.1 — Token ISSUE (create → consume → wallet +) | [ ] |
| A.2 — Token BURN (create → consume → wallet -) | [ ] |
| A.3 — Troca assessoria (queima automática) | [ ] |
| A.4 — Desafio cross → pending + case | [ ] |
| A.5 — Clearing confirm sent/received → pending → disponível | [ ] |
| A.6 — Dispute → pending permanece | [ ] |
| A.7 — Intent expirado → rejeição 410 | [ ] |
| A.8 — Atleta não pode criar intent (403) | [ ] |
| A.9 — Case expirado → pending permanece | [ ] |
| B.1 — Wallet UI 3 estados | [ ] |
| B.2 — Minha Assessoria + modal troca | [ ] |
| B.3 — Staff QR Hub (gating) | [ ] |
| B.4 — Gerar QR (countdown + expiração) | [ ] |
| B.5 — Escanear QR (valid/expired/invalid) | [ ] |
| B.6 — Coaching Roles labels | [ ] |
| C.1 — Zero termos proibidos | [ ] |
| C.2 — Flutter analyze clean | [ ] |
| C.3 — Anti-replay verificado | [ ] |

**Total: 18 testes | Pass: __ | Fail: __ | Bloqueado: __**

---

*Documento gerado em 16.99.0 — reprodutível, copiável, sem termos proibidos.*
