# parts/ — Relatórios originais da auditoria

Esta pasta armazena os **8 relatórios narrativos** produzidos na execução da auditoria de 2026-04-17, organizados pelas 23 lentes:

| Arquivo | Lentes | Itens |
|---|---|---|
| `01-ciso.md`            | 1 (CISO)                                    | 50 |
| `02-cto-cfo.md`         | 2 (CTO) + 3 (CFO)                           | 35 |
| `03-clo-cpo.md`         | 4 (CLO) + 5 (CPO)                           | 35 |
| `04-coo-cxo-cdo.md`     | 6 (COO) + 7 (CXO) + 8 (CDO)                 | 40 |
| `05-cro-cso-supply-cron.md` | 9 (CRO) + 10 (CSO) + 11 + 12            | 50 |
| `06-middleware-contracts-cmo-cao.md` | 13 + 14 + 15 (CMO) + 16 (CAO)  | 25 |
| `07-vp-principal-dba-sre.md` | 17 + 18 + 19 (DBA) + 20 (SRE)           | 40 |
| `08-personas.md`        | 21 (Atleta Pro) + 22 (Amador) + 23 (Treinador) | 60 |

Os arquivos ainda não foram persistidos — a narrativa completa está no histórico da conversa.

**Próximo passo**: transcrever cada parte para o arquivo correspondente (fonte de contexto para futuros devs + auditores). Os **findings machine-readable** são rastreados em `docs/audit/findings/`; estes `parts/` servem como prosa explicativa.

## Template para cada parte

```md
# Parte N — Lente(s) X [e Y]

> **Auditoria:** 2026-04-17
> **Lentes:** X (Nome), [Y (Nome)]
> **Total de findings:** N

## Contexto

<resumo narrativo de 3-5 parágrafos>

## Findings

### [X.1] Título
<descrição, evidência, impacto, correção — igual ao que está em findings/LXX-YY-*.md>

### [X.2] ...
```
