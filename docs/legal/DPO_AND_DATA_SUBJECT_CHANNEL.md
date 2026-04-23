# Encarregado de Proteção de Dados (DPO) — Canal do Titular

> **Versão:** 1.0
> **Vigência:** 2026-04-23
> **Base legal:** LGPD (Lei 13.709/2018), Art. 41 — designação obrigatória de encarregado pelo controlador.

---

## 1. Identificação do controlador

- **Razão social:** [a definir antes do go-live público — placeholder hoje aceito porque a base de usuários atual é restrita ao programa fechado de assessorias parceiras]
- **CNPJ:** [a definir]
- **Endereço:** [a definir]
- **Site oficial:** https://omnirunner.com.br

> **NOTA OPERACIONAL.** Este documento é o registro canônico do canal do
> titular. Antes da abertura comercial pública (Onda 3) o time legal
> obrigatoriamente substitui os placeholders pelos dados oficiais e
> incrementa a versão deste arquivo (a ser refletido em
> `consent_policy_versions.document_hash` via `npm run legal:check`).

---

## 2. Encarregado de Proteção de Dados (DPO)

- **Nome:** Encarregado por Proteção de Dados — Omni Runner
- **Email:** **`dpo@omnirunner.com.br`** (canal canônico)
- **Forma alternativa:** carta registrada para o endereço oficial do
  controlador (ver §1).
- **Atribuições (Art. 41 §2 LGPD):**
  1. Aceitar reclamações e comunicações dos titulares, prestar
     esclarecimentos e adotar providências.
  2. Receber comunicações da ANPD e adotar providências.
  3. Orientar funcionários e contratados a respeito das práticas a
     serem tomadas em relação à proteção de dados pessoais.
  4. Executar as demais atribuições determinadas pelo controlador.

---

## 3. Canal do titular — direitos garantidos

LGPD Art. 18 confere aos titulares os seguintes direitos. Cada um pode
ser exercido por email ao DPO, indicando claramente qual o pedido:

| # | Direito (LGPD) | Endpoint | Prazo de resposta |
|---|---|---|---|
| 1 | Confirmação de tratamento (Art. 18 I) | `dpo@` ou `/privacy/data` (logado) | 15 dias |
| 2 | Acesso aos dados (Art. 18 II) | `/privacy/data/export` (self-service) | 15 dias |
| 3 | Correção (Art. 18 III) | UI de perfil + `dpo@` para casos não cobertos | 15 dias |
| 4 | Anonimização/bloqueio/eliminação (Art. 18 IV) | `/privacy/data/delete` (self-service) | 15 dias |
| 5 | Portabilidade (Art. 18 V) | `dpo@` ou `/privacy/data/portable` | 15 dias úteis |
| 6 | Eliminação dos dados (Art. 18 VI) | `/privacy/data/delete` (self-service) | 15 dias |
| 7 | Informação sobre compartilhamento (Art. 18 VII) | `dpo@` (relatório individual) | 15 dias |
| 8 | Informação sobre não consentimento (Art. 18 VIII) | `dpo@` | 15 dias |
| 9 | Revogação de consentimento (Art. 18 IX) | UI de privacidade + `dpo@` | imediato (≤24h) |

**Prazo geral:** 15 dias corridos a partir do recebimento da
solicitação completa. Se o pedido for incompleto (faltar
identificação confiável), o DPO solicita complemento antes de iniciar
a contagem.

**Recurso para a ANPD:** caso o titular não obtenha resposta
satisfatória, pode reclamar diretamente em
[https://www.gov.br/anpd/pt-br/canais_atendimento](https://www.gov.br/anpd/pt-br/canais_atendimento).

---

## 4. Página pública

A página `/privacy/dpo` no portal e a tela "Privacidade" no app
(`omni_runner/lib/features/privacy/`) devem expor:

1. Nome e email do encarregado (sempre o mesmo email canônico
   `dpo@omnirunner.com.br`).
2. Endereço físico do controlador.
3. Lista dos 9 direitos do titular (linkando para os endpoints
   self-service quando existirem).
4. Prazo de 15 dias e referência ao Art. 18 LGPD.
5. Link para a Política de Privacidade vigente
   (`/privacy/policy/v<N>`).
6. Link para o canal ANPD.

---

## 5. Operação interna do DPO

- **SLA interno:** 24h úteis para acusar recebimento; 7 dias úteis
  para resposta preliminar; 15 dias corridos para resolução completa.
- **Registro:** toda solicitação é registrada em `audit_logs` com
  `category='lgpd'` + `subject_user_id` (ofuscado quando necessário) +
  hash do email do solicitante (`subject_email_hash`).
- **Escalação:** pedidos com risco regulatório (vazamento, requisição
  judicial, autoridade) escalam imediatamente para o jurídico via
  `legal@omnirunner.com.br`.
- **Backup:** o backup do email `dpo@` é o `legal@`. Se o DPO estiver
  ausente >48h, o `legal@` assume.

---

## 6. Cross-reference

- ADR `docs/legal/README.md` — política geral de privacidade
- Runbook `docs/runbooks/DATA_SUBJECT_REQUEST_RUNBOOK.md` — passo a
  passo operacional para responder cada um dos 9 direitos
- L04-01 — `fn_delete_user_data` (direito de eliminação)
- L04-03 — registro de consentimento (direito de revogação)
- L04-15 — exportação self-service (direito de portabilidade)

---

## 7. Histórico de revisão

| Versão | Data | Autor | Mudança |
|---|---|---|---|
| 1.0 | 2026-04-23 | Audit Wave 2 (Batch K) | Criação inicial — fecha L04-11 |
