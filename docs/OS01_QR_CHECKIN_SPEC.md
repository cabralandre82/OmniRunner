# OS-01: Auto-Attendance — Especificação Técnica

> **Atualizado:** 2026-03-04 — DECISAO 134  
> **Substituiu:** QR Check-in Spec (fluxo QR removido em favor de avaliação automática)

## Visão Geral

O sistema de presença nos treinos prescritos é **100% automático**. O staff (coach) prescreve um treino com parâmetros (distância, pace), e o sistema avalia automaticamente as corridas do atleta para determinar se o treino foi cumprido.

**Não existe presença na assessoria** — o sistema rastreia exclusivamente o cumprimento de treinos prescritos.

## Fluxo

```
Staff prescreve treino       Atleta corre (Strava sync)     Sistema avalia
─────────────────────── ──→ ──────────────────────────── ──→ ─────────────────
distance_target_m: 5000      sessions.total_distance_m       ±15% distância
pace_min_sec_km: 270          sessions.moving_ms              pace na faixa
pace_max_sec_km: 360          status = 3 (completed)          → completed/partial
                                                              
Staff cria próximo treino ──→ Fecha treino anterior ──→ Atletas sem corrida → absent
```

## Parâmetros do Treino

| Campo | Tipo | Obrigatório | Descrição |
|-------|------|-------------|-----------|
| `distance_target_m` | `double precision` | Não | Distância alvo em metros |
| `pace_min_sec_km` | `double precision` | Não | Pace mínimo (mais rápido) em segundos/km |
| `pace_max_sec_km` | `double precision` | Não | Pace máximo (mais lento) em segundos/km |

> Se `distance_target_m` for `NULL`, o treino não é avaliado automaticamente.

## Lógica de Avaliação

A função `fn_evaluate_athlete_training(p_training_id, p_athlete_user_id, p_deadline_ms)` avalia as **2 próximas corridas completadas** do atleta após a criação do treino:

### Match de Distância (±15%)
```
total_distance_m >= distance_target_m * 0.85
AND total_distance_m <= distance_target_m * 1.15
```

### Match de Pace (se especificado)
```
pace = (moving_ms / 1000) / (total_distance_m / 1000)  -- seg/km
pace >= pace_min_sec_km AND pace <= pace_max_sec_km
```

### Resultado

| Condição | Status | Descrição |
|----------|--------|-----------|
| Distância ✓ + Pace ✓ (ou sem pace) | `completed` | Treino cumprido |
| Correu, mas sem match | `partial` | Correu mas fora dos parâmetros |
| Sem corrida antes do próximo treino | `absent` | Não correu |

## Triggers

### 1. `trg_session_auto_attendance` (AFTER INSERT OR UPDATE ON sessions)
- Dispara quando `status = 3` (corrida completada)
- Busca treinos pendentes dos grupos do atleta
- Chama `fn_evaluate_athlete_training` para cada treino pendente
- Não sobrescreve avaliações manuais ou já concluídas

### 2. `trg_training_close_prev` (AFTER INSERT ON coaching_training_sessions)
- Dispara quando novo treino com `distance_target_m IS NOT NULL` é criado
- Busca o treino anterior no mesmo grupo
- Para cada atleta sem avaliação: tenta avaliar, se não tiver corridas → `absent`

## Override Manual

Staff pode alterar o status de qualquer atleta via bottom sheet no app:
- Atualiza `status` e seta `method = 'manual'`
- Avaliações automáticas **nunca sobrescrevem** overrides manuais (`WHERE method = 'auto'`)

## Status e Métodos

### `coaching_training_attendance.status`
`present` | `late` | `excused` | `absent` | `completed` | `partial`

### `coaching_training_attendance.method`
`qr` | `manual` | `auto`

## Segurança

- `fn_evaluate_athlete_training` roda como `SECURITY DEFINER`
- RLS policies permitem insert/update para sistema (via trigger)
- Atleta só vê seus próprios registros
- Staff vê todos os registros do grupo

## Migration

`20260313000000_auto_attendance.sql`
