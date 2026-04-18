# Postmortem: <SUMÁRIO ATIVO E ESPECÍFICO>

> **Filename**: `YYYY-MM-DD-<slug>.md` (substitua antes de commitar)
> **Status**: `draft` → `in-review` → `published`
> **Audit ref**: L20-08 (template) — ver `docs/postmortems/README.md` para
> filosofia blameless.
>
> **REMOVER ESTAS LINHAS DE INSTRUÇÃO ANTES DE PUBLICAR.** Tudo entre
> `<...>` é placeholder.

---

## Resumo executivo (150 palavras)

> 1 parágrafo. Lê quem só tem 30 segundos. Inclui:
> - O que aconteceu (1 frase)
> - Quem foi afetado e como (1-2 frases)
> - Causa raiz em uma frase
> - O que foi feito para resolver
> - Maior aprendizado / próximo passo prioritário

---

## Metadados

| Campo | Valor |
|---|---|
| **Data do incidente** | YYYY-MM-DD |
| **Detectado em (UTC)** | HH:MM |
| **Mitigado em (UTC)** | HH:MM |
| **Resolvido em (UTC)** | HH:MM |
| **Duração total** | __ min |
| **Severidade** | SEV-0 / SEV-1 / SEV-2 / SEV-3 |
| **Owner do postmortem** | @handle |
| **Incident commander** | @handle |
| **Stakeholders notificados** | @handles |
| **Status page comunicado?** | Yes / No / N/A |
| **Customer escalation?** | Yes / No |
| **Money loss estimado** | R$ ____ ou "nenhum" |
| **SLOs impactados** | `slo_name_1`, `slo_name_2` |
| **Error budget burned** | __% / __min do orçamento mensal |
| **Findings relacionados (auditoria)** | LXX-YY, LXX-YY |
| **Runbook usado** | `docs/runbooks/<nome>.md` ou "nenhum" |

---

## Impacto

### Para usuários
> Quem foi afetado, em que escala, por quanto tempo. Seja CONCRETO.
>
> ❌ Ruim: "Alguns usuários tiveram problemas no checkout."
> ✅ Bom: "1.247 atletas em 8 grupos de coaching foram impedidos de
>   sacar coins entre 14:23 e 15:41 UTC. 87 retentativas falhadas. Zero
>   transações fantoma confirmadas via reconciliação."

### Para a plataforma
> Recursos consumidos, contratos violados (Asaas, etc), exposição
> regulatória, dívida técnica criada para mitigar.

### Para o time
> Horas-pessoa gastas (responder + investigar + escrever postmortem +
> corrigir).

---

## Timeline (UTC)

> Reconstruir minuto a minuto. Cite Slack/Sentry/Grafana links sempre
> que possível. **NÃO** cite pessoas (use "on-call", "SRE", "alguém com
> acesso a vault").

| Time (UTC) | Event |
|---|---|
| HH:MM | <gatilho — push, deploy, condição externa> |
| HH:MM | Alerta Sentry P1 disparou: `<rule>` em `/api/<route>` |
| HH:MM | On-call ackd o pager (latência detect → ack: __ min) |
| HH:MM | Hipótese inicial: <X>. Iniciada investigação. |
| HH:MM | Hipótese descartada após `<query/log/comando>`. |
| HH:MM | Causa raiz identificada: <Y>. |
| HH:MM | Mitigação aplicada: <comando/PR/feature flag>. |
| HH:MM | Smoke test confirmou recovery. |
| HH:MM | Status page atualizado para "operational". |
| HH:MM | All-clear declarado em `#incidents`. |

---

## Causa raiz

> Use o método **"5 whys"** para chegar a uma causa SISTÊMICA, não
> humana. Exemplo:
>
> ❌ "Operador deu DROP TABLE em prod por engano."
> ✅ "Falta de guard-rail (read-only psql wrapper) tornou possível DROP
>   acidental. Procedimento de hotfix exigia conexão direta porque CLI
>   admin não suporta esse fluxo."

### O que deu errado
> Descrição técnica. Cite linhas de código, queries, configs.

### Por que o sistema permitiu
> Onde os guard-rails falharam OU não existiam.

### Por que detectamos quando detectamos (não antes)
> Foi alarme correto? Faltou métrica? Faltou alarme?

---

## O que funcionou bem (★)

> Reconhecimento explícito. Importante para o moral E para PRESERVAR
> os mecanismos que funcionaram.
>
> Exemplos:
> - Alerta Sentry disparou em < 2min do início da degradação.
> - Runbook `<X>` foi seguido sem ambiguidade.
> - Rollback automático preveniu propagação para 95% dos pods.

---

## O que não funcionou (✗)

> Ser específico. Cada item vira candidato a action item.
>
> Exemplos:
> - Não havia runbook para o cenário Z.
> - Métrica `<m>` é coletada mas dashboard `<d>` não a expõe.
> - Tempo de detecção (15min) > target (5min).

---

## Action items

> SMART (Specific, Measurable, Assignable, Realistic, Time-bound).
> CADA item tem **owner + deadline + tipo**. Sem owner = não é action item.
>
> Tipos:
> - **prevent**: evita reocorrência
> - **detect**: melhora detecção
> - **mitigate**: reduz blast radius futuro
> - **process**: muda como respondemos

| # | Tipo | Action | Owner | Deadline | Issue/PR | Status |
|---|---|---|---|---|---|---|
| 1 | prevent | Adicionar constraint `CHECK (...)` em tabela X | @handle | YYYY-MM-DD | #__ | open |
| 2 | detect | Criar SLO para latência da rota Y | @handle | YYYY-MM-DD | #__ | open |
| 3 | mitigate | Documentar runbook para cenário Z | @handle | YYYY-MM-DD | #__ | open |
| 4 | process | Adicionar passo "validar X" ao deploy checklist | @handle | YYYY-MM-DD | #__ | open |

---

## Lessons learned (para o time)

> 3-5 bullets. Conhecimento que TODA a equipe deveria ter após este
> incidente.
>
> Exemplos:
> - Migrations que dropam coluna devem sempre ter `--dry-run` na CI.
> - Quando vir spike em `webhook_queue_depth`, primeiro suspeitar de
>   fila Asaas — historicamente correlaciona em 80% dos casos.
> - Free tier do Supabase tem cap de 60 connections — preferir
>   transaction pooler para Edge Functions.

---

## Findings de auditoria gerados

> Se este incidente expôs gap não-coberto pela auditoria atual:
> - Criar finding novo em `docs/audit/findings/LXX-YY-<slug>.md`.
> - Linkar aqui.
> - Atualizar `docs/audit/ROADMAP.md` se severidade for critical/high.

| Finding ID | Título | Severidade | Wave |
|---|---|---|---|
| LXX-YY | <título> | critical/high/medium | 0/1/2 |

---

## Apêndice — evidências

> Screenshots de Sentry, Grafana, queries SQL relevantes, links a
> commits/PRs. Tudo o que a próxima pessoa lendo este postmortem em
> 2 anos vai precisar para entender o contexto.
>
> **REDACTED**: nunca incluir PII (CPF, email, IDs internos), secrets,
> ou health data. Use `<redacted>` ou IDs sintéticos.

### Queries usadas no diagnóstico
```sql
-- Cole aqui as queries que ajudaram a identificar a causa.
```

### Logs relevantes (redacted)
```
<timestamp> <level> <msg> ... <fields with PII redacted>
```

### Links externos
- Sentry issue: https://sentry.io/...
- Grafana dashboard snapshot: https://grafana.../snapshot/...
- Commit que introduziu o bug: <sha>
- Commit que corrigiu: <sha>
- PR de correção: #__
