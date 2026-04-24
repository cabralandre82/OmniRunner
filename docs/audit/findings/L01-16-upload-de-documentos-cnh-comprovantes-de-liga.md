---
id: L01-16
audit_ref: "1.16"
lens: 1
title: "Upload de documentos — CNH, comprovantes de liga"
severity: na
status: not-reproducible
wave: 3
discovered_at: 2026-04-17
reaudited_at: 2026-04-24
tags: ["lgpd", "rls", "mobile", "portal", "storage"]
files:
  - "omni_runner/lib/data/datasources/sync_service.dart"
  - "omni_runner/lib/data/services/profile_data_service.dart"
  - "omni_runner/lib/presentation/screens/run_details_screen.dart"
  - "supabase/migrations/20260218000000_full_schema.sql"
correction_type: process
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 0
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "Re-auditoria 2026-04-24: feature não existe no codebase. Sem upload de CNH/liga documentation. Apenas avatars e session-points, ambos com RLS auth.uid()-scoped."
---
# [L01-16] Upload de documentos — CNH, comprovantes de liga
> **Lente:** 1 — CISO · **Severidade:** ⚪ N/A · **Onda:** 3 · **Status:** 🔍 not-reproducible
**Camada:** APP (Flutter) + BACKEND (Storage)
**Personas impactadas:** Atleta profissional (envio de documentos para liga/filiação)

## Achado original
Grepping rápido não encontrou endpoint portal `/api/documents/upload` nem `/api/lgpd/*`. Uploads pareciam ir direto para Supabase Storage via SDK do app. Marcado para re-auditoria.

## Re-auditoria 2026-04-24

### Inventário de uploads via Storage SDK
Busca exaustiva por `.storage.from(...)`, `uploadBinary`, `Supabase.instance.client.storage` no app (`omni_runner/lib`) e no portal retornou **apenas 3 buckets** em uso:

| Bucket | Finalidade | RLS | Arquivo |
|---|---|---|---|
| `avatars` | Foto de perfil do usuário | RLS padrão Supabase (owner-scoped via path `avatars/{userId}.ext`) | `omni_runner/lib/data/services/profile_data_service.dart:46-50` |
| `session-points` | GPS raw points da corrida (JSON) | `session_points_own_upload`/`own_read` — `(storage.foldername(name))[1] = auth.uid()::text` (`supabase/migrations/20260218000000_full_schema.sql:1041-1053`) | `omni_runner/lib/presentation/screens/run_details_screen.dart:158`, `omni_runner/lib/data/datasources/sync_service.dart:65` |
| `avatars` (sync) | Mesmo bucket acima, via sync path | Idem | `omni_runner/lib/data/datasources/sync_service.dart:65` |

### Busca por features de "CNH / liga / documento"
`rg -i 'CNH|\bliga\b|documento|upload.*document' omni_runner portal/src/app/api` — nenhum match relacionado a upload de documentos. `league_screen.dart` e `my_assessoria_screen.dart` contém a palavra "liga" apenas no sentido de "categoria de ranking social", não "filiação à liga desportiva".

### Conclusão
**A feature de "upload de documentos — CNH, comprovantes de liga" não existe no codebase atual.** O achado original foi especulativo (auditor antecipou a necessidade para atletas profissionais de alto nível que precisam comprovar filiação à CBAt/FIS). Nada a corrigir.

**Watchdog**: quando essa feature for implementada no futuro, criar novo finding dedicado cobrindo:
- Bucket privado `athlete-documents` com RLS `(storage.foldername(name))[1] = auth.uid()::text`.
- Políticas adicionais para staff-read-only (coach/admin_master do grupo de assessoria do atleta).
- Retenção LGPD: `purge_expired_athlete_documents` cron após X dias desde revogação.
- Classificação LGPD: "dado pessoal sensível" → consent explicit logging.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.16]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.16).
- `2026-04-24` — Re-auditoria confirmou que a feature não existe. Flipped para `not-reproducible`. Seguir com watchdog quando implementada.
