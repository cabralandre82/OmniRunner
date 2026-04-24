---
id: L22-17
audit_ref: "22.17"
lens: 22
title: "Clima local não informa decisão"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-24
closed_at: 2026-04-24
tags: ["personas", "athlete-amateur", "mobile", "integrations"]
files:
  - docs/product/ATHLETE_AMATEUR_BASELINE.md

correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs:
  - "fce133b"

owner: product+mobile+backend
runbook: docs/product/ATHLETE_AMATEUR_BASELINE.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Coberto em `docs/product/ATHLETE_AMATEUR_BASELINE.md`
  § 8 (Home weather widget). OpenWeatherMap One Call v3
  primário + Open-Meteo fallback (cap em 1000 calls/dia
  free tier). Geocoding do `home_city` 1x no save, não
  em cada leitura. `weather-cache-cron` (30 min) popula
  `weather_cache` por bin de 3 casas decimais (~100m),
  reduzindo dramaticamente custo de API para o cluster
  BR. Cliente nunca chama API diretamente — lê só cache.
  "Running window" heurística simples (temp/precip/vento/
  raio). Ship Wave 5 fase W5-A.
---
# [L22-17] Clima local não informa decisão
> **Lente:** 22 — Atleta Amador · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— Amador olha fora da janela pra decidir correr.
## Correção proposta

— Widget home "Hoje às 6h: 22°C, umidade 80%, chuva em 2h — boa hora para sair". OpenWeatherMap API.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[22.17]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 22 — Atleta Amador, item 22.17).
- `2026-04-24` — Consolidado em `docs/product/ATHLETE_AMATEUR_BASELINE.md` § 8 (batch K12); implementação Wave 5 fase W5-A.
