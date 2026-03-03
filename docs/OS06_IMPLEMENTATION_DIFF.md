# OS-06 — Implementation Diff: Inventário Completo (BLOCO 0–6)

## Migrations SQL (7 arquivos)

| Arquivo | Bloco | Conteúdo |
|---------|-------|----------|
| `supabase/migrations/20260303300000_fix_coaching_roles.sql` | PASSO 05 | Role backfill + constraint + RLS + functions |
| `supabase/migrations/20260303300001_alert_dedup_constraints.sql` | PASSO 05 | UNIQUE constraints para idempotência |
| `supabase/migrations/20260303400000_training_sessions_attendance.sql` | OS-01 | Tabelas treino + presença + RLS + RPCs |
| `supabase/migrations/20260303500000_crm_tags_notes_status.sql` | OS-02 | Tags, notes, status + RLS + RPC |
| `supabase/migrations/20260303600000_announcements.sql` | OS-03 | Avisos + reads + RLS + 2 RPCs |
| `supabase/migrations/20260303700000_portal_performance_indexes.sql` | OS-04 | 11 indexes de performance |
| `supabase/migrations/20260303800000_kpi_attendance_integration.sql` | OS-05 | Colunas attendance em KPIs + compute update + novo alerta |

## App Flutter — Domain Layer (19 arquivos)

### Entities (6)
| Arquivo | Bloco |
|---------|-------|
| `lib/domain/entities/training_session_entity.dart` | OS-01 |
| `lib/domain/entities/training_attendance_entity.dart` | OS-01 |
| `lib/domain/entities/coaching_tag_entity.dart` | OS-02 |
| `lib/domain/entities/athlete_note_entity.dart` | OS-02 |
| `lib/domain/entities/member_status_entity.dart` | OS-02 |
| `lib/domain/entities/announcement_entity.dart` | OS-03 |

### Repository Interfaces (4)
| Arquivo | Bloco |
|---------|-------|
| `lib/domain/repositories/i_training_session_repo.dart` | OS-01 |
| `lib/domain/repositories/i_training_attendance_repo.dart` | OS-01 |
| `lib/domain/repositories/i_crm_repo.dart` | OS-02 |
| `lib/domain/repositories/i_announcement_repo.dart` | OS-03 |

### Use Cases (13)
| Arquivo | Bloco |
|---------|-------|
| `lib/domain/usecases/training/create_training_session.dart` | OS-01 |
| `lib/domain/usecases/training/list_training_sessions.dart` | OS-01 |
| `lib/domain/usecases/training/cancel_training_session.dart` | OS-01 |
| `lib/domain/usecases/training/mark_attendance.dart` | OS-01 |
| `lib/domain/usecases/training/issue_checkin_token.dart` | OS-01 |
| `lib/domain/usecases/training/list_attendance.dart` | OS-01 |
| `lib/domain/usecases/crm/manage_tags.dart` | OS-02 |
| `lib/domain/usecases/crm/manage_notes.dart` | OS-02 |
| `lib/domain/usecases/crm/manage_member_status.dart` | OS-02 |
| `lib/domain/usecases/crm/list_crm_athletes.dart` | OS-02 |
| `lib/domain/usecases/announcements/list_announcements.dart` | OS-03 |
| `lib/domain/usecases/announcements/create_announcement.dart` | OS-03 |
| `lib/domain/usecases/announcements/mark_announcement_read.dart` | OS-03 |

## App Flutter — Data Layer (3 arquivos)

| Arquivo | Bloco |
|---------|-------|
| `lib/data/repositories_impl/supabase_training_session_repo.dart` | OS-01 |
| `lib/data/repositories_impl/supabase_training_attendance_repo.dart` | OS-01 |
| `lib/data/repositories_impl/supabase_crm_repo.dart` | OS-02 |
| `lib/data/repositories_impl/supabase_announcement_repo.dart` | OS-03 |

## App Flutter — BLoCs (21 arquivos, 7 BLoCs)

| BLoC | Diretório | Bloco |
|------|-----------|-------|
| TrainingListBloc | `lib/presentation/blocs/training_list/` | OS-01 |
| TrainingDetailBloc | `lib/presentation/blocs/training_detail/` | OS-01 |
| CheckinBloc | `lib/presentation/blocs/checkin/` | OS-01 |
| CrmListBloc | `lib/presentation/blocs/crm_list/` | OS-02 |
| AthleteProfileBloc | `lib/presentation/blocs/athlete_profile/` | OS-02 |
| AnnouncementFeedBloc | `lib/presentation/blocs/announcement_feed/` | OS-03 |
| AnnouncementDetailBloc | `lib/presentation/blocs/announcement_detail/` | OS-03 |

## App Flutter — Screens (14 arquivos)

| Tela | Bloco | Quem usa |
|------|-------|----------|
| `staff_training_list_screen.dart` | OS-01 | Staff |
| `staff_training_create_screen.dart` | OS-01 | Staff |
| `staff_training_detail_screen.dart` | OS-01 | Staff |
| `staff_training_scan_screen.dart` | OS-01 | Staff |
| `athlete_training_list_screen.dart` | OS-01 | Athlete |
| `athlete_checkin_qr_screen.dart` | OS-01 | Athlete |
| `athlete_attendance_screen.dart` | OS-01 | Athlete |
| `staff_crm_list_screen.dart` | OS-02 | Staff |
| `staff_athlete_profile_screen.dart` | OS-02 | Staff |
| `athlete_my_status_screen.dart` | OS-02 | Athlete |
| `athlete_my_evolution_screen.dart` | OS-02 | Athlete |
| `announcement_feed_screen.dart` | OS-03 | All |
| `announcement_detail_screen.dart` | OS-03 | All |
| `announcement_create_screen.dart` | OS-03 | Staff |

## App Flutter — Modified Files (1)

| Arquivo | Mudança |
|---------|---------|
| `lib/core/service_locator.dart` | +60 linhas: registros de repos, usecases, blocs para OS-01/02/03 |

## Portal Next.js — Pages (16+ arquivos)

| Página | Path | Bloco |
|--------|------|-------|
| Attendance Report | `/attendance` | OS-01 |
| Attendance Detail | `/attendance/[id]` | OS-01 |
| Attendance Analytics | `/attendance-analytics` | OS-04 |
| CRM Table | `/crm` | OS-02 |
| CRM At-Risk | `/crm/at-risk` | OS-02 |
| CRM Athlete Detail | `/crm/[userId]` | OS-02 |
| Announcements Panel | `/announcements` | OS-03 |
| Announcement Detail | `/announcements/[id]` | OS-03 |
| Announcement Edit | `/announcements/[id]/edit` | OS-03 |
| Engagement (upgraded) | `/engagement` | OS-04 |
| Communications | `/communications` | OS-04 |
| Risk/Alerts | `/risk` | OS-04 |
| Exports Hub | `/exports` | OS-04 |

## Portal Next.js — API Routes (8 arquivos)

| Route | Method | Bloco |
|-------|--------|-------|
| `/api/export/attendance` | GET | OS-01 |
| `/api/export/crm` | GET | OS-02 |
| `/api/crm/tags` | GET | OS-02 |
| `/api/crm/notes` | POST | OS-02 |
| `/api/announcements` | POST | OS-03 |
| `/api/announcements/[id]` | PATCH/DELETE | OS-03 |
| `/api/export/announcements` | GET | OS-03 |
| `/api/export/engagement` | GET | OS-04 |
| `/api/export/alerts` | GET | OS-04 |

## Portal — Modified Files

| Arquivo | Mudança |
|---------|---------|
| `src/components/sidebar.tsx` | +6 nav entries |

## Docs (17 arquivos)

| Doc | Bloco |
|-----|-------|
| `docs/ATLAS_OS_MASTER.md` | BLOCO 0 |
| `docs/OS01_SCHEMA_RLS.md` | OS-01 |
| `docs/OS01_QR_CHECKIN_SPEC.md` | OS-01 |
| `docs/OS01_APP_FLOWS.md` | OS-01 |
| `docs/OS01_PORTAL_REPORTS.md` | OS-01 |
| `docs/OS02_CRM_SPEC.md` | OS-02 |
| `docs/OS02_APP_FLOWS.md` | OS-02 |
| `docs/OS02_PORTAL.md` | OS-02 |
| `docs/OS03_ANNOUNCEMENTS_SPEC.md` | OS-03 |
| `docs/OS03_APP_FLOWS.md` | OS-03 |
| `docs/OS03_PORTAL.md` | OS-03 |
| `docs/OS04_PORTAL_REPORTS.md` | OS-04 |
| `docs/OS04_EXPORTS.md` | OS-04 |
| `docs/OS05_KPIS_ALERTS_INTEGRATION.md` | OS-05 |
| `docs/OS06_IMPLEMENTATION_DIFF.md` | OS-06 |
| `docs/OS06_TEST_MATRIX.md` | OS-06 |
| `docs/OS06_RELEASE_RUNBOOK.md` | OS-06 |

## Tools

| Arquivo | Bloco |
|---------|-------|
| `tools/verify_metrics_snapshots.ts` | OS-05 (updated) |

## TrainingPeaks Integration

| Arquivo | Bloco |
|---------|-------|
| `supabase/migrations/20260304800000_trainingpeaks_integration.sql` | TrainingPeaks |
| `supabase/functions/trainingpeaks-oauth/index.ts` | TrainingPeaks |
| `supabase/functions/trainingpeaks-sync/index.ts` | TrainingPeaks |
| `omni_runner/lib/domain/usecases/wearable/push_to_trainingpeaks.dart` | TrainingPeaks |
| `portal/src/app/(portal)/trainingpeaks/page.tsx` | TrainingPeaks |
| `portal/src/app/(portal)/trainingpeaks/loading.tsx` | TrainingPeaks |
| `docs/TRAININGPEAKS_INTEGRATION.md` | TrainingPeaks |

## Performance / Observability / UX

| Arquivo | Tipo |
|---------|------|
| `tools/perf_seed.ts` | Performance |
| `tools/perf_benchmark.sql` | Performance |
| `tools/perf_run.sh` | Performance |
| `portal/src/app/error.tsx` | Error boundary |
| `portal/src/app/global-error.tsx` | Error boundary |
| `portal/src/components/empty-state.tsx` | UX |
| `portal/src/components/web-vitals.tsx` | Performance |
| `portal/src/lib/api-handler.ts` | Observability |
| `supabase/functions/_shared/obs.ts` | Observability |
| `supabase/functions/_shared/cors.ts` | Security |

## QA Documentation

| Arquivo | Tipo |
|---------|------|
| `docs/QA_GATE0_PRODUCT_INVENTORY.md` | QA Gate 0 |
| `docs/QA_GATE1_E2E_DUMMY.md` | QA Gate 1 |
| `docs/QA_GATE2_INTEGRATION_CONTRACTS.md` | QA Gate 2 |
| `docs/QA_GATE3_NO_LOCAL_MOCK.md` | QA Gate 3 |
| `docs/QA_GATE4_EDGE_CASES.md` | QA Gate 4 |
| `docs/QA_GATE5_SECURITY.md` | QA Gate 5 |
| `docs/QA_GATE6_CONCURRENCY.md` | QA Gate 6 |
| `docs/QA_GATE7_WEARABLES.md` | QA Gate 7 |
| `docs/QA_GATE8_UX.md` | QA Gate 8 |
| `docs/QA_GATE9_OBSERVABILITY.md` | QA Gate 9 |
| `docs/QA_GATE10_SCALE_PERF.md` | QA Gate 10 |
| `docs/QA_GATE11_FEATURE_QA_INTERROGATION.md` | QA Gate 11 |
| `docs/QA_GATE12_RELEASE_SIGNOFF.md` | QA Gate 12 |
| `docs/QA_PRE_RELEASE_MASTER_REPORT.md` | QA Consolidado |
| `docs/QA_PRE_RELEASE_BUGS.md` | QA Bugs |
| `docs/QA_PRE_RELEASE_RISK_REGISTER.md` | QA Riscos |
| `docs/QA_PRE_RELEASE_SIGNOFF.md` | QA Sign-off |

## Totais

| Camada | Arquivos novos | Arquivos modificados |
|--------|---------------|---------------------|
| Migrations SQL | 16 | 0 |
| Edge Functions | 4 (new) | 20+ (CORS/health) |
| App Domain | 25 | 2 |
| App Data | 4 | 0 |
| App BLoCs | 21 | 3 |
| App Screens | 14 | 10 |
| App DI | 0 | 1 |
| Portal Pages | 24+ | 5 |
| Portal API | 12 | 8 |
| Portal Components | 3 | 2 |
| Docs | 45+ | 3 |
| Tools | 6 | 1 |
| CI/CD | 2 | 0 |
| **TOTAL** | **~190+** | **~55** |
