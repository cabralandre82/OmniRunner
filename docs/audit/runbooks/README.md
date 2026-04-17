# runbooks/ — Procedimentos operacionais derivados da auditoria

Runbooks são criados sob demanda quando um finding requer um procedimento operacional passo-a-passo (não apenas uma correção de código).

## Convenção de nome

`runbooks/<área>-<procedimento>.md`

Exemplos (esperados após início da Onda 0/1):

- `custody-reconciliation.md` — passos para reconciliar drift entre `custody_accounts` e `coin_ledger`.
- `rollback-migration.md` — como reverter uma migration com dados inconsistentes.
- `partial-failure-recovery.md` — investigação e correção manual de partial-failures em `distribute-coins` (antes da correção atomic).
- `incident-coin-emission.md` — resposta a alerta de emissão anômala.

## Template

```md
# Runbook: <Título>

> **Gatilho:** <alerta, incidente ou procedimento que ativa este runbook>
> **Severidade esperada:** P0 / P1 / P2
> **SLO:** resolução em <tempo>
> **Linked findings:** LXX-YY, LXX-YY
> **Última revisão:** YYYY-MM-DD

## 1. Identificação

Como detectar que este é o cenário correto.

## 2. Contenção

Passos imediatos para parar o sangramento.

## 3. Diagnóstico

Queries, logs, comandos para entender causa raiz.

## 4. Correção

Passos operacionais (SQL, kubectl, etc).

## 5. Validação

Como confirmar que o problema foi resolvido.

## 6. Postmortem

- Criar issue com label `postmortem`.
- Atualizar findings afetados com `linked_prs`.
- Se novo gap: criar novo finding.
```

Runbooks referenciados por findings via frontmatter `runbook: runbooks/<nome>.md` são automaticamente incluídos em `FINDINGS.md`.
