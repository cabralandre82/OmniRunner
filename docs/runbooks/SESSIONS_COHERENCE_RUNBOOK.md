## Sessions Coherence Runbook (L08-04)

**Status**: active · **Owner**: Platform / Data · **Updated**: 2026-04-21

---

### 1. Invariante

Para toda row em `public.sessions` com `status >= 3` (finalizada):

- `total_distance_m = 0 AND moving_ms = 0` (sessão cancelada/drop), **OU**
- `total_distance_m >= 100 AND moving_ms >= 60000` (sessão real: ≥ 100 m, ≥ 60 s)

Sessões com `status < 3` (incompletas/em progresso) são **livres** — a
invariante só é checada no gate de finalização.

Enforce: `CHECK constraint chk_sessions_coherence` em `public.sessions`,
VALIDATED em 2026-04-21 (sem offenders).

---

### 2. Por que este guard existe

`fn_compute_skill_bracket` e outros consumers de `sessions` fazem:

```sql
CASE WHEN total_distance_m > 0 AND moving_ms > 0
     THEN (moving_ms / 1000.0) / (total_distance_m / 1000.0)  -- pace sec/km
     ELSE NULL
END
```

Sem o `moving_ms > 0` guard, um GPS bug que deixa `moving_ms=0` com
`total_distance_m=5000` produz pace = 0.0 sec/km (infinito rápido) e
bagunça rankings/skill-bracket.

A constraint schema-level é **defense in depth**: mesmo que um contribuidor
esqueça o guard inline, a row nunca entra no catálogo.

---

### 3. Playbook de backfill (quando CI falha)

Se `npm run audit:sessions-coherence` retornar `P0010`:

1. Inspecione a lista de offenders:

    ```sql
    SELECT * FROM public.fn_find_sessions_incoherent(500);
    -- Retorna (id, user_id, status, total_distance_m, moving_ms, reason)
    -- reason ∈ {gps_zero_moving_ms, zero_distance_with_moving, distance_below_100m, moving_below_60s, other_incoherent}
    ```

2. Classifique por `reason`:

    | reason | Origem típica | Ação |
    |---|---|---|
    | `gps_zero_moving_ms` | GPS pause bug, strava_import com moving_time zerado | Se a sessão tem points_path consistente, recompute `moving_ms` via edge function; senão: marque `integrity_flags += 'gps_no_moving'` e demova para `status=2` (review) |
    | `zero_distance_with_moving` | Manual entry inválido | `status=2` + investigar fonte |
    | `distance_below_100m` | Sessão espúria que passou pelo verify-session (pré-L21) | Hard delete se confirmado lixo, ou `status=2` |
    | `moving_below_60s` | Auto-finalização precoce em iOS suspend | Demova para `status=2` |
    | `other_incoherent` | desconhecido | Planet-scale review; trate case-a-case |

3. Para cada classe, use um UPDATE segmentado (wrap in transaction):

    ```sql
    BEGIN;
    -- Exemplo: demover gps_zero_moving_ms para review
    UPDATE public.sessions s
       SET status = 2,
           integrity_flags = array_append(integrity_flags, 'gps_no_moving_ms_l08_04')
      FROM public.fn_find_sessions_incoherent(10000) f
     WHERE s.id = f.id AND f.reason = 'gps_zero_moving_ms';
    COMMIT;
    ```

4. Revalide o constraint (se foi adicionado NOT VALID):

    ```sql
    ALTER TABLE public.sessions VALIDATE CONSTRAINT chk_sessions_coherence;
    ```

5. Re-rode CI até 0 offenders.

---

### 4. Detection / CI

- `public.fn_find_sessions_incoherent(p_limit int default 100)` — lista
  offenders com `reason` classificado. SECURITY DEFINER, service_role only.
- `public.fn_assert_sessions_coherence()` — raise `P0010` se qualquer
  offender existir. SECURITY DEFINER, service_role only.
- CI: `npm run audit:sessions-coherence`.

---

### 5. Call-sites protegidos / que dependem da invariante

- `fn_compute_skill_bracket` (20260312000000) — já tem guard inline.
- `fn_compute_kpis_batch` (20260312000000) — usa `COALESCE(SUM(...), 0)`.
- `v_weekly_progress` — filtra `s.total_distance_m >= 200`, protegido.
- Portal admin / staff_weekly_report — consumidor futuro pode confiar na
  invariante sem guards inline repetidos.

---

### 6. Edge cases e decisões

**Por que `(0,0)` é aceito para status >= 3?**
Sessões canceladas/drop: usuário iniciou, desistiu, mas a row foi
persistida para auditoria. Permitir `(0,0)` evita precisar de um segundo
status para "cancelada" com distância zero.

**Por que não aceitar `(50, 30000)` para "sessão de treino curto"?**
Abaixo de 100 m ou 60 s geralmente é ruído de GPS (rastreamento ativou
acidentalmente, ou kid mexeu no celular). Verify-session já bloqueia essas
via integrity check; o CHECK é backstop.

**Existe risco de quebrar INSERTS em tests?**
Sim — tests que insiram fixture `status=3` com `dist=1, moving=100`
passarão a falhar. Ajuste fixtures para `dist=100, moving=60000` ou
`(0,0)`.

---

### 7. Referências

- Finding: `docs/audit/findings/L08-04-analise-de-sessions-pelo-moving-ms-mas-coluna.md`
- Migração: `supabase/migrations/20260421320000_l08_04_sessions_coherence_check.sql`
- CI: `tools/audit/check-sessions-coherence.ts`
- Tests: `tools/test_l08_04_sessions_coherence_check.ts`
- Relacionados: L08-05 (views), L21-01/02 (anti-cheat thresholds)
