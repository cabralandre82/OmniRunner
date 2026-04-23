---
id: L23-08
audit_ref: "23.8"
lens: 23
title: "Presença em treinos coletivos via QR code (staff_training_scan_screen.dart existe)"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["mobile", "migration", "personas", "coach"]
files:
  - supabase/migrations/20260421660000_l23_08_geofenced_checkin.sql
  - tools/audit/check-geofenced-checkin.ts
correction_type: code
test_required: true
tests:
  - tools/audit/check-geofenced-checkin.ts
linked_issues: []
linked_prs:
  - "local:32819d4"
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Fixed at 2026-04-21 (commit 32819d4) by extending the existing QR
  attendance rail with a geofenced auto-check-in path that lets
  athletes check themselves in when they enter the session's radius:
    - coaching_training_sessions gains location_radius_meters
      (CHECK [25, 5000]), checkin_early_seconds / checkin_late_seconds
      (both [0, 86400]), geofence_enabled (default FALSE). CHECK
      geofence_requires_location forces lat/lng/radius when enabled.
    - coaching_training_attendance gains checkin_lat / checkin_lng /
      checkin_accuracy_m. CHECK method_check drops and re-adds to add
      'auto_geo'. CHECK auto_geo_has_coords forces coords on auto_geo
      rows.
    - public.coaching_attendance_audit append-only log of accepted +
      rejected attempts with reason_code (shape ^[A-Z][A-Z0-9_]{2,48}$).
      RLS: athlete-self, staff per-session, platform_admin.
    - fn_session_checkin_window(session_id) STABLE SECURITY INVOKER —
      returns (window_open_at, window_close_at, is_open).
    - fn_auto_checkin(session_id, lat, lng, accuracy_m) SECURITY
      DEFINER — validates auth, lat/lng range, accuracy_m ≤ 100,
      session not cancelled, geofence_enabled, membership, window,
      and uses fn_haversine_m for distance. Idempotent via
      ON CONFLICT (session_id, athlete_user_id) DO NOTHING. Every
      rejection emits an audit row with an explicit reason code.
    - fn_record_attendance_audit SECURITY DEFINER fail-open (RAISE
      WARNING) so audit outages never block a legitimate check-in.
    - Self-tests assert column / CHECK / fn_auto_checkin presence.
    - 51-invariant CI guard `npm run audit:geofenced-checkin`.
---
# [L23-08] Presença em treinos coletivos via QR code (staff_training_scan_screen.dart existe)
> **Lente:** 23 — Treinador · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Tela de scan existe. Integração com `attendance` OK? Mas e **check-in geofenced** no local do encontro?
## Correção proposta

— Cada `coaching_event` (treino coletivo) tem `geofence`. App atleta auto-check-in quando entra no raio. Coach confirma via QR se necessário.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[23.8]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 23 — Treinador, item 23.8).