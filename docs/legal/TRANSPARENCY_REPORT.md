# Relatório de Transparência — Omni Runner

> **Versão:** 1.0
> **Vigência:** 2026-04-23
> **Cadência:** semestral (publicado em 31/jan e 31/jul)
> **Base legal:** Marco Civil da Internet (Lei 12.965/2014) Art. 11; LGPD Art. 4 §3.

Este documento é o **template canônico** do relatório semestral de
transparência da Omni Runner. Cada publicação preserva o mesmo
formato e a mesma seção; as métricas são preenchidas pelo time
legal com base em `audit_logs` (categoria `legal_request`) e em
registros do DPO (`dpo@omnirunner.com.br`).

---

## 1. Período coberto

| Item | Valor |
|---|---|
| Início | YYYY-MM-DD |
| Fim    | YYYY-MM-DD |
| Publicado em | YYYY-MM-DD |
| Próxima publicação | YYYY-MM-DD |

---

## 2. Solicitações governamentais

Conta apenas requisições **formais** (ofício judicial, requisição
do Ministério Público, etc). Pedidos informais ou via canais não
oficiais são rejeitados e contabilizados em §6.

| Categoria | Recebidas | Atendidas integralmente | Atendidas parcialmente | Rejeitadas | Pendentes |
|---|---|---|---|---|---|
| Ordem judicial cível          | 0 | 0 | 0 | 0 | 0 |
| Ordem judicial criminal       | 0 | 0 | 0 | 0 | 0 |
| Requisição do MP              | 0 | 0 | 0 | 0 | 0 |
| Requisição administrativa BCB | 0 | 0 | 0 | 0 | 0 |
| Requisição ANPD               | 0 | 0 | 0 | 0 | 0 |
| Outros órgãos públicos        | 0 | 0 | 0 | 0 | 0 |

**Tipos de dado mais solicitados:** `[a preencher]` (ex.: dados
cadastrais, registros de conexão, conteúdo de comunicações,
movimentação financeira).

**Critério de rejeição:** falta de competência, ausência de base
legal, escopo excessivo, ou solicitação não formal. Cada rejeição
é registrada em `audit_logs.category='legal_request'` com
`outcome='rejected'` e `reason`.

---

## 3. Solicitações de titulares (LGPD Art. 18)

| Direito | Solicitações | Atendidas no SLA (15d) | Atendidas fora do SLA | Rejeitadas | Mediana de tempo |
|---|---|---|---|---|---|
| Confirmação de tratamento | 0 | 0 | 0 | 0 | — |
| Acesso aos dados          | 0 | 0 | 0 | 0 | — |
| Correção                  | 0 | 0 | 0 | 0 | — |
| Anonimização/eliminação   | 0 | 0 | 0 | 0 | — |
| Portabilidade             | 0 | 0 | 0 | 0 | — |
| Informação compartilhamento | 0 | 0 | 0 | 0 | — |
| Revogação de consentimento | 0 | 0 | 0 | 0 | — |

**Total:** 0 solicitações no período.

**Self-service vs DPO:** dos atendimentos, X% foram resolvidos
diretamente pelos endpoints self-service (`/privacy/data/export`,
`/privacy/data/delete`) sem intervenção humana.

---

## 4. Incidentes de segurança / vazamentos

| Item | Valor |
|---|---|
| Incidentes confirmados                       | 0 |
| Incidentes notificados à ANPD                | 0 |
| Titulares notificados                        | 0 |
| Tempo médio de detecção (MTTD)               | — |
| Tempo médio de notificação à ANPD            | — |

Conforme LGPD Art. 48 §1, incidentes de risco relevante são
notificados à ANPD em prazo razoável (interpretação ANPD = 2 dias
úteis para notificação preliminar).

---

## 5. Remoções de conteúdo

A plataforma Omni Runner não hospeda conteúdo gerado por usuário
de natureza pública (UGC) atualmente. Esta seção fica reservada
para futuras features sociais (feed, comentários etc.).

| Categoria | Solicitações | Removidas | Mantidas |
|---|---|---|---|
| Direito autoral (DMCA / Lei 9.610/98) | 0 | 0 | 0 |
| Discurso de ódio                      | 0 | 0 | 0 |
| Falsificação de identidade            | 0 | 0 | 0 |
| Outros                                 | 0 | 0 | 0 |

---

## 6. Tentativas de acesso ilegítimo

Tentativas de obter dados sem base legal (engenharia social,
phishing contra suporte, etc).

| Item | Valor |
|---|---|
| Tentativas detectadas | 0 |
| Origem mais comum     | — |

---

## 7. Compromissos de transparência

A Omni Runner compromete-se a:

1. Publicar este relatório **semestralmente** (31/jan e 31/jul).
2. Manter histórico das versões anteriores em
   `docs/legal/transparency-archive/` (a criar quando houver
   primeira edição preenchida).
3. Notificar usuários afetados por solicitação governamental
   sempre que **não** houver vedação legal.
4. Detalhar metodologia de contagem em apêndice quando solicitado.

---

## 8. Contato

Dúvidas sobre este relatório:
- DPO: `dpo@omnirunner.com.br`
- Jurídico: `legal@omnirunner.com.br`

Cross-references:
- `docs/legal/DPO_AND_DATA_SUBJECT_CHANNEL.md` — canal do titular
  (L04-11)
- `docs/legal/DATA_TRANSFER.md` — política de transferência
  internacional (L04-10)
- `docs/legal/TERMO_ATLETA.md` — direitos contratuais do atleta

---

## 9. Histórico de revisão

| Versão | Data | Autor | Mudança |
|---|---|---|---|
| 1.0 | 2026-04-23 | Audit Wave 2 (Batch K) | Template inicial — fecha L09-10. Próxima edição: 2026-07-31. |
