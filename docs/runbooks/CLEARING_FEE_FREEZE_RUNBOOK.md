# CLEARING_FEE_FREEZE_RUNBOOK

> **Tópico**: taxa de `clearing` (interclub settlement) congelada no
> momento da emissão (L03-02).
> **Severidade-alvo**: P2/P3 (disputas comerciais com assessorias) ou
> P1 (exposure significativa em `fee_rate_source='live_config_fallback'`).
> **Linked findings**: L03-02, L03-09, L03-13, L18-01 (contexto custody).
> **Última revisão**: 2026-04-21

---

## 1. Modelo mental (leia antes de qualquer query)

Post L03-02 a taxa de clearing **não** é mais lida "ao vivo" no burn.
Ela é **congelada na emissão**:

1. `emit_coins_atomic` grava `platform_fee_config.rate_pct` em
   `coin_ledger.clearing_fee_rate_pct_snapshot` na linha de emissão.
2. `execute_burn_atomic` chama `fn_compute_clearing_fee_rate_for_issuer`
   que retorna **média ponderada pelo volume** dos snapshots do par
   `(athlete, issuer)` e usa esse rate no `clearing_settlements.fee_rate_pct`.
3. `clearing_settlements.fee_rate_source` grava **como** a rate foi
   computada:
   - `snapshot_weighted_avg` — caminho normal pós-L03-02.
   - `live_config_fallback` — todas as emissões daquele issuer eram
     pré-migration com snapshot NULL, então caiu em
     `platform_fee_config.rate_pct` (defensivo; deve convergir a 0%).

**Conclusão operacional**: alterar `platform_fee_config.rate_pct` é
**forward-only**. Só afeta emissões **futuras**. Coins já no ecossistema
preservam o rate da hora em que foram emitidas.

---

## 2. Cenário A — Assessoria contesta o fee cobrado

> *"Nosso contrato era 3%, mas o settlement desta semana cobrou 4%."*

### 2.1 Ler o que foi cobrado e como

```sql
SELECT
  s.id                AS settlement_id,
  s.clearing_event_id,
  s.creditor_group_id,
  s.debtor_group_id,
  s.coin_amount,
  s.gross_amount_usd,
  s.fee_rate_pct,
  s.fee_rate_source,
  s.fee_amount_usd,
  s.net_amount_usd,
  s.status,
  s.created_at,
  s.settled_at
FROM public.clearing_settlements s
WHERE s.id = '<SETTLEMENT_ID>';
```

### 2.2 Justificar o rate (caminho normal)

Para `fee_rate_source = 'snapshot_weighted_avg'`, o rate é a média
ponderada dos snapshots das emissões do issuer consumidas no burn:

```sql
SELECT
  cl.id                              AS emission_ledger_id,
  cl.delta_coins,
  cl.clearing_fee_rate_pct_snapshot,
  cl.created_at_ms,
  to_timestamp(cl.created_at_ms / 1000.0) AS emitted_at
FROM public.coin_ledger cl
JOIN public.clearing_events ce       ON ce.id = '<CLEARING_EVENT_ID>'
WHERE cl.user_id         = ce.athlete_user_id
  AND cl.issuer_group_id = '<DEBTOR_GROUP_ID>'
  AND cl.reason          = 'institution_token_issue'
ORDER BY cl.created_at_ms ASC;
```

Verificação independente:

```sql
SELECT *
FROM public.fn_compute_clearing_fee_rate_for_issuer(
  (SELECT athlete_user_id FROM public.clearing_events WHERE id = '<CLEARING_EVENT_ID>'),
  '<DEBTOR_GROUP_ID>'
);
-- rate_pct, source, sample_count, total_coins_emitted
```

Se `rate_pct` bate com `settlement.fee_rate_pct`: o sistema calculou
correto. Monte a justificativa com a lista de emissões acima — a
assessoria assinou taxas diferentes em momentos diferentes; a média
ponderada reflete exatamente o que ela emitiu.

### 2.3 Caso de falha (live_config_fallback)

Se `fee_rate_source = 'live_config_fallback'`:

```sql
-- Quantas emissões daquele issuer ainda estão sem snapshot?
SELECT COUNT(*) AS legacy_rows,
       SUM(delta_coins) AS legacy_coins
FROM public.coin_ledger
WHERE reason = 'institution_token_issue'
  AND issuer_group_id = '<DEBTOR_GROUP_ID>'
  AND clearing_fee_rate_pct_snapshot IS NULL;
```

Se o número é > 0: a migration L03-02 rodou mas o backfill daquele
issuer foi pulado (import cruzado, restore parcial, etc.). **Não fazer
UPDATE direto** — use o procedimento da seção 4.

---

## 3. Cenário B — CFO quer **estimar** fee de um burn futuro

> *"Athlete A tem 800 coins do issuer X. Se ele queimar tudo no issuer
> Y amanhã, quanto a plataforma vai cobrar?"*

```sql
SELECT rate_pct, source, sample_count, total_coins_emitted
FROM public.fn_compute_clearing_fee_rate_for_issuer(
  '<ATHLETE_USER_ID>',
  '<ISSUER_GROUP_ID>'
);
```

- `rate_pct` é a taxa que será aplicada.
- `sample_count` é o número de linhas de emissão que a sustentam.
- `source = 'snapshot_weighted_avg'` confirma o caminho normal.

Fee estimado = `coin_amount * rate_pct / 100`.

---

## 4. Cenário C — Monitorar exposição `live_config_fallback`

Deve convergir a 0% após ciclo natural de archive/rotation do ledger.

### 4.1 Query de monitoramento (adicionar ao cron CFO)

```sql
SELECT
  COUNT(*) FILTER (WHERE fee_rate_source = 'snapshot_weighted_avg') AS snapshot_count,
  COUNT(*) FILTER (WHERE fee_rate_source = 'live_config_fallback')  AS fallback_count,
  SUM(fee_amount_usd) FILTER (WHERE fee_rate_source = 'live_config_fallback')
    AS fallback_fee_exposure_usd
FROM public.clearing_settlements
WHERE created_at > now() - interval '30 days';
```

### 4.2 Alert threshold sugerido

- `fallback_count / (snapshot_count + fallback_count) > 5%` por mais
  de 7 dias consecutivos → abrir ticket CFO+SRE para investigar import
  de dados pendente.

### 4.3 Corrigir exposição legacy (caso raro)

Para backfillar manualmente emissões de um issuer específico com a
rate que **realmente** vigorava na época (se houver fonte externa):

```sql
-- NÃO executar sem duplo OK de CFO + DBA.
-- Parâmetros: issuer, janela temporal, rate histórica documentada.
UPDATE public.coin_ledger
   SET clearing_fee_rate_pct_snapshot = <HISTORIC_RATE>
 WHERE reason = 'institution_token_issue'
   AND issuer_group_id = '<DEBTOR_GROUP_ID>'
   AND clearing_fee_rate_pct_snapshot IS NULL
   AND created_at_ms BETWEEN <WINDOW_START_MS> AND <WINDOW_END_MS>;
```

Registrar a mudança em `portal_audit_log` manualmente com justificativa
(link para ticket CFO + rate histórica + fonte).

---

## 5. Cenário D — Mudar `platform_fee_config.rate_pct`

Procedimento **forward-only** pós-L03-02. Coins já no ecossistema
preservam a rate da emissão.

1. **Comunicar** todas as assessorias emissoras **antes** da mudança
   (contratual).
2. **Aplicar** (via portal `/platform/fees` ou SQL):
   ```sql
   UPDATE public.platform_fee_config
      SET rate_pct  = <NEW_RATE>,
          updated_at = now(),
          updated_by = '<ADMIN_USER_ID>'
    WHERE fee_type = 'clearing';
   ```
3. **Validar**: emitir 1 coin de teste e conferir
   `coin_ledger.clearing_fee_rate_pct_snapshot` = `<NEW_RATE>`.
4. **Documentar** a mudança em `portal_audit_log` ou equivalente com
   link para ATA de decisão.

**NÃO** existe hoje histórico estruturado de mudanças de rate —
rastreamento é via git/`portal_audit_log`. Avaliar se uma tabela
`platform_fee_config_history` é desejável em wave futura
(finding separado).

---

## 6. Cross-refs

- [`docs/audit/findings/L03-02-congelamento-de-precos-taxas.md`](../audit/findings/L03-02-congelamento-de-precos-taxas.md) — fix completo.
- [`docs/audit/findings/L03-13-reverse-coins-*.md`](../audit/findings/) — reversão de coins (incluindo corrigir emissões com snapshot errado).
- [`CLEARING_STUCK_RUNBOOK.md`](./CLEARING_STUCK_RUNBOOK.md) — settlements presas em `pending`.
- [`CUSTODY_INCIDENT_RUNBOOK.md`](./CUSTODY_INCIDENT_RUNBOOK.md) — invariantes de custódia.
- [`REVERSE_COINS_RUNBOOK.md`](./REVERSE_COINS_RUNBOOK.md) — procedimento para reemitir coins com snapshot corrigido.
- Migration: [`supabase/migrations/20260421170000_l03_02_freeze_clearing_fee_at_emission.sql`](../../supabase/migrations/20260421170000_l03_02_freeze_clearing_fee_at_emission.sql).
- Testes: [`tools/test_l03_02_freeze_clearing_fee.ts`](../../tools/test_l03_02_freeze_clearing_fee.ts).
