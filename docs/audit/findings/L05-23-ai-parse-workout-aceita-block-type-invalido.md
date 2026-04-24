---
id: L05-23
audit_ref: "5.23"
lens: 5
title: "AI parse-workout: block_type inválido trocado silenciosamente por steady"
severity: high
status: fix-pending
wave: 0
discovered_at: 2026-04-24
tags: ["workout", "ai", "validation", "coach"]
files:
  - portal/src/app/api/training-plan/ai/parse-workout/route.ts
correction_type: code
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: platform-workout
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L05-23] AI parse-workout: block_type inválido trocado silenciosamente por steady

> **Lente:** 5 — CPO · **Severidade:** 🟠 High · **Onda:** 0 · **Status:** fix-pending

**Camada:** Portal Next.js (rota `POST /api/training-plan/ai/parse-workout`)
**Personas impactadas:** coach (digita descrição, recebe workout silenciosamente destorcido)

## Achado

Quando GPT-4o aluciona um `block_type` fora do enum válido (acontece empiricamente em ~8% dos parses complexos), o parser **substitui silenciosamente** por `"steady"`:

```149:149:portal/src/app/api/training-plan/ai/parse-workout/route.ts
      block_type:                 validBlockTypes.includes(b.block_type as string) ? b.block_type : "steady",
```

Adicionalmente, **não valida invariantes semânticos** entre blocos:
- Não verifica que `repeat` é seguido de pelo menos um `interval`/`run`.
- Não verifica que `repeat_count >= 2`.
- Não valida que `pace_min_sec_per_km <= pace_max_sec_per_km` (o DB tem CHECK, mas o parser retorna 200 OK e o INSERT depois falha com erro genérico 23514).
- Aceita bloco com `distance_meters` **e** `duration_seconds` simultâneos (FIT encoder prioriza time → distância perdida silenciosamente).
- Não recalcula `estimated_distance_km`/`estimated_duration_minutes` consistentes com a soma dos blocos.

## Impacto

**Cenário real:** coach digita "aqueço 2km e faço 3x strides de 100m rápidos". GPT-4o retorna `block_type: "strides"` (não existe no enum). Parser troca por `"steady"` sem avisar. Coach olha o preview no portal, vê "2km warmup + 3 steady blocks" (sem targets de pace), salva, distribui para 30 atletas. Ninguém viu que a prescrição "strides" foi silenciosamente achatada em "corrida contínua".

**Segunda classe de bug:** coach digita "4x 1km em 4:30 a 4:00 pace". Se o GPT inverter low/high, o parser devolve 200 OK, o INSERT no DB falha por `chk_pace_range`, o erro chega ao coach como "erro genérico 500" sem explicação de qual bloco está com pace invertido.

## Correção proposta

1. **Strict mode**: trocar `|| "steady"` por erro 422 estruturado com `errors: [{ block_index, field, message }]`.

2. **Validator pós-parser** em `portal/src/lib/workout/validate.ts`:
   ```ts
   export type ValidationError = { path: string; code: string; message: string };
   export function validateWorkoutBlocks(blocks: ParsedBlock[]): {
     ok: boolean;
     errors: ValidationError[];
     warnings: ValidationError[];
   };
   ```

   Invariantes cobertos:
   - `block_type ∈ enum` (redundante com Zod, mas explícito aqui).
   - `repeat` tem `repeat_count >= 2` e é seguido por ≥ 1 bloco ativo antes de `repeat_end`.
   - `repeat_end` só aparece após um `repeat` aberto.
   - Cada bloco tem **exatamente um** gatilho: (duração || distância), **nunca ambos, nunca nenhum** (exceto `repeat`/`repeat_end`).
   - `target_pace_min_sec_per_km <= target_pace_max_sec_per_km` (ambos preenchidos ou ambos null).
   - `target_hr_min <= target_hr_max` idem.
   - `estimated_distance_km` está dentro de 10% da soma calculada — senão, warning.
   - `estimated_duration_minutes` idem.

3. **Integrar** validator na rota `parse-workout/route.ts`: se `errors.length > 0`, retornar 422; se só `warnings`, retornar 200 com campo `warnings[]`.

4. **Testes** em `portal/src/lib/workout/validate.test.ts` cobrindo cada invariante (12 casos).

## Teste de regressão

- Input GPT-mock com `block_type: "strides"` → 422 + mensagem clara.
- Input com `pace_min=300, pace_max=250` (invertido) → 422.
- Input com `duration_seconds=600, distance_meters=1000` no mesmo bloco → 422.
- Input com `repeat` sem `repeat_end` e sem bloco ativo interno → 422.
- Input válido feliz → 200 + blocks preservados idênticos.

## Cross-refs

- L05-21, L05-22: correção do modelo de dados; este finding foca em quality gate na entrada (AI).

## Histórico

- `2026-04-24` — Descoberto durante vistoria de passagem de treino.
