# Postmortems — Blameless incident retrospectives

> Audit ref: **L20-08** — Post-mortem template ausente.

## Filosofia

Postmortems aqui seguem o modelo **blameless** do [Google SRE Book ch.15](https://sre.google/sre-book/postmortem-culture/):

- **Foco em sistemas, não em pessoas.** "Operador X executou o comando errado"
  é falha de SISTEMA (faltou guard-rail), não de pessoa.
- **Aprendizado > culpa.** Sucesso = ação concreta capturada, não punição.
- **Compartilhamento amplo.** Postmortem é PR público no repo, lido por
  toda equipe, indexado pelo `index.md`.

## Quando escrever um postmortem

**OBRIGATÓRIO** se qualquer uma:

- Incidente classificado SEV-0 ou SEV-1 (ver `docs/observability/ALERT_POLICY.md`).
- Disponibilidade de qualquer SLO P1 ficou abaixo do target em janela do
  mês corrente (mesmo que ainda dentro de error budget).
- Resposta a incidente expôs gap em runbook OU runbook não existia.
- Customer escalation que chegou a CTO/CEO.
- Restore de backup foi necessário (Modo B do `DR_PROCEDURE.md`).
- Money loss > R$ 100 confirmado.

**RECOMENDADO** se:

- Near-miss (alerta P1 que QUASE causou impacto cliente — quase é
  oportunidade barata de aprender).
- Drill DR (Modo A) revelou tempo de RTO > target.

## Workflow

1. **T+24h após resolução**: criar `docs/postmortems/YYYY-MM-DD-slug.md` a
   partir de `TEMPLATE.md`.
2. **T+48h**: agendar retrospective meeting (30-60min, time + 1
   stakeholder afetado).
3. **T+5d úteis**: meeting → preencher seções "Lessons learned" e
   "Action items" com owners + deadlines.
4. **T+7d**: PR com postmortem mergeado, action items viraram findings
   se forem mudança técnica ou tickets se forem processo.
5. **T+30d**: revisar action items — se algum não tiver owner ativo,
   escalar.

## Convenção de nome

`YYYY-MM-DD-<slug-curto-cinético>.md`

Bons exemplos:
- `2026-04-21-asaas-webhook-storm-saturated-db.md`
- `2026-05-13-coin-ledger-drift-after-failed-rollback.md`
- `2026-07-02-rls-bypass-via-service-role-misuse.md`

Maus exemplos:
- `incident-1.md` (sem data, sem contexto)
- `bug.md` (não-descritivo)
- `pmortem-john.md` (cita pessoa — viola blameless)

## Index

Quando primeiro postmortem for escrito, criar `index.md` aqui listando:

| Data | Slug | Severidade | Duração | SLO impactado | Findings gerados |
|---|---|---|---|---|---|
| YYYY-MM-DD | __ | SEV-_ | __min | __ | LXX-YY |

## Materiais de apoio

- Template canônico: `TEMPLATE.md` (este diretório)
- DR procedure: `docs/runbooks/DR_PROCEDURE.md`
- Alert policy: `docs/observability/ALERT_POLICY.md`
- SLO catalog: `docs/observability/SLO.md`
- Audit findings: `docs/audit/FINDINGS.md`

## Privacidade & LGPD

Postmortems são commitados no repo (público interno). **NUNCA** incluir:
- PII de clientes (CPF, e-mail, telefone, ID interno) → usar
  `<redacted>` ou IDs sintéticos.
- Secrets / chaves / tokens → usar `<redacted>`.
- Dump de logs com health data sensível (HR, GPS) → ver L04-04.

Se preciso citar dado real para reconstruir cenário, fazer em PR
privado fora do repo público (ex. Notion interno) e linkar daqui.
