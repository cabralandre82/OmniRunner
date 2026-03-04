# Audit: User Experience

**Date:** 2026-03-04  
**Scope:** 80+ Flutter screens analyzed for UX patterns, feedback, dead ends, consistency, confirmations, accessibility

---

## 1. Design System Foundations

The app has a solid design system infrastructure:

| Component | Location | Quality |
|-----------|----------|---------|
| `DesignTokens` | `core/theme/design_tokens.dart` | ✅ Centralized spacing, color, and sizing constants |
| `ErrorState` widget | `presentation/widgets/error_state.dart` | ✅ Reusable with humanized error messages (network, timeout, 401, 403, 404, 500) and retry button |
| `EmptyState` widget | `presentation/widgets/empty_state.dart` | ✅ Reusable with icon, title, subtitle, and optional CTA |
| `ShimmerLoading` | `presentation/widgets/shimmer_loading.dart` | ✅ Consistent skeleton loading |
| `NoConnectionBanner` | `presentation/widgets/no_connection_banner.dart` | ✅ Global offline indicator with auto-hide on reconnect |
| `CachedAvatar` | `presentation/widgets/cached_avatar.dart` | ✅ Consistent avatar rendering |
| Localization | `l10n/` with `AppLocalizations` | ✅ i18n support (pt-BR primary) |

---

## 2. Loading / Error / Empty State Consistency

### 2.1 Loading States

**Usage across 80+ screens:**

| Pattern | Count | Screens |
|---------|-------|---------|
| `ShimmerListLoader` / `ShimmerLoading` | ~20+ | `athlete_device_link_screen`, `assessoria_feed_screen`, `staff_championship_templates_screen`, etc. |
| `CircularProgressIndicator` (center) | ~65+ | Most screens including `today_screen`, `profile_screen`, `settings_screen` |
| `LinearProgressIndicator` | ~5 | Used in some staff screens for progress indication |
| No loading indicator | 0 found | All data-loading screens have loading states ✅ |

**Assessment:** ✅ Nearly universal loading state coverage. Minor inconsistency: some screens use shimmer (richer UX) while others use spinner. Recommend standardizing on shimmer for list views and spinner only for actions.

### 2.2 Error States

| Pattern | Usage |
|---------|-------|
| `ErrorState` widget (reusable) | Used in some screens ✅ |
| Inline `Column` with error icon + text + retry button | Used in `athlete_device_link_screen`, others |
| SnackBar for error display | Widely used (48+ screens, ~200+ occurrences) |
| Raw error text in SnackBar | Some screens show `e.toString()` (e.g., `athlete_log_execution_screen:88`) |

**Assessment:** ⚠️ Mixed patterns. The `ErrorState` widget provides humanized messages, but many screens still construct ad-hoc error UIs or show raw exception text.

**Recommendation:** Mandate `ErrorState.humanizeLocalized()` for all user-facing error messages. Audit all `SnackBar(content: Text('Erro: $e'))` patterns.

### 2.3 Empty States

| Pattern | Usage |
|---------|-------|
| `EmptyState` widget | Some newer screens |
| Custom inline empty state | `athlete_device_link_screen._buildEmpty()`, others |
| No empty state (blank screen) | A few screens may show a blank list |

**Assessment:** ⚠️ Partially consistent. Recommend using the reusable `EmptyState` widget everywhere.

---

## 3. Feedback After Actions

### 3.1 SnackBar Feedback ✅ (Extensive)

SnackBar usage was found in **48+ screens** with a total of ~200+ occurrences. This covers:

- Device link/unlink: "Garmin conectado" / "Garmin desconectado" ✅
- Execution log: "Execução registrada com sucesso!" ✅
- Tag deletion: "Tag excluída" ✅
- Championship actions: "Campeonato cancelado" ✅
- Friend actions: "Convite cancelado" ✅
- Join requests: Success/error feedback ✅

### 3.2 Navigation Feedback

- `athlete_log_execution_screen.dart`: Pops with `true` result after success, allowing the parent screen to refresh ✅
- Announcement creation: Similar pop-on-success pattern ✅

### 3.3 Missing Feedback Patterns

| Screen | Action | Feedback |
|--------|--------|----------|
| `diagnostics_screen.dart` | Navigation-only screen | N/A — no actions |
| `settings_screen.dart` | Theme mode change | ✅ Immediate visual feedback via `ValueListenableBuilder` |
| `profile_screen.dart` | Avatar upload | ✅ Shows uploading state |

**Assessment:** ✅ Strong overall. Virtually all API-calling actions show success/error feedback.

---

## 4. Dead End Screens

### 4.1 Screens Without Clear Navigation Entry

| Screen | Status | Notes |
|--------|--------|-------|
| `debug_hrm_screen.dart` | ⚠️ QA-only | Marked as development/QA screen. No navigation found from production screens. Not a dead end — intentionally hidden |
| `diagnostics_screen.dart` | ✅ | Reachable from `settings_screen.dart` |
| `how_it_works_screen.dart` | ✅ | Reachable from settings |
| `onboarding_tour_screen.dart` | ✅ | Shown during first launch |
| `welcome_screen.dart` | ✅ | First-time entry point |

### 4.2 Potentially Orphaned Screens

Without full router analysis, some screens that could be orphaned:

| Screen | Risk |
|--------|------|
| `athlete_my_status_screen.dart` | Low — likely reachable from athlete dashboard |
| `athlete_my_evolution_screen.dart` | Low — likely linked from progress hub |
| `group_rankings_screen.dart` | Low — likely linked from group details |

**Recommendation:** Run a dead-code analysis on the router/navigator configuration to confirm all screens are reachable.

---

## 5. Inconsistent Patterns

### 5.1 Loading State Display

| Inconsistency | Example Screens |
|---------------|-----------------|
| Shimmer vs Spinner | `athlete_device_link_screen` uses `ShimmerListLoader`; `settings_screen` uses `CircularProgressIndicator` |
| Loading indicator position | Most center it; some show it inline |

### 5.2 Error Display

| Inconsistency | Example |
|---------------|---------|
| Humanized vs raw errors | `athlete_log_execution_screen:88` shows `e.toString()`; `ErrorState` widget humanizes errors |
| Error color | Most use `colorScheme.error`; some use hardcoded `Colors.red` |

### 5.3 Button Styles

| Pattern | Usage |
|---------|-------|
| `FilledButton` | Primary actions across most screens ✅ |
| `FilledButton.tonal` | Secondary actions (device connect/disconnect) ✅ |
| `OutlinedButton` | Tertiary actions ✅ |
| `TextButton` | Cancel/dismiss actions ✅ |

**Assessment:** ✅ Button hierarchy is well-applied and consistent.

### 5.4 Language Mixing

| Pattern | Example |
|---------|---------|
| Portuguese UI strings | "Registrar Execução", "Dispositivos", "Cancelar" ✅ |
| English error messages | Some catch blocks use English: "Connection error: $e" |
| i18n coverage | `context.l10n.cancel`, `context.l10n.settings` used in many places ✅ |
| Hardcoded Portuguese | Some screens use hardcoded strings instead of l10n keys |

**Recommendation:** Replace all hardcoded strings with `l10n` keys for full internationalization readiness.

---

## 6. Missing Confirmation Dialogs

### 6.1 Destructive Actions WITH Confirmation ✅

| Action | Screen | Confirmation |
|--------|--------|-------------|
| Cancel training session | `staff_training_detail_screen.dart:50-76` | ✅ AlertDialog with explanation |
| Cancel championship | `staff_championship_manage_screen.dart:208-260` | ✅ AlertDialog |
| Delete account | `settings_screen.dart` | ✅ Dialog (inferred from context) |
| Remove member | `coaching_group_details_screen.dart` | ✅ AlertDialog |
| Cancel challenge | `challenge_details_screen.dart` | ✅ Via bloc event pattern |
| Leave assessoria | `my_assessoria_screen.dart` | ✅ AlertDialog |

### 6.2 Destructive Actions WITHOUT Confirmation ❌

| Action | Screen | Risk |
|--------|--------|------|
| **Device unlink** | `athlete_device_link_screen.dart:90-98` | ⚠️ `_toggleLink` immediately unlinks without dialog. OAuth re-auth may be required to re-link |
| **Tag deletion** | `staff_crm_list_screen.dart:652-668` | ❌ `_deleteTag` calls `ManageTags().delete()` directly with no confirmation dialog. Tags may be assigned to athletes |
| **Friend invite cancel** | `friends_screen.dart:380` | ⚠️ Tooltip says "Cancelar convite" but no confirmation shown |
| **Clear saved BLE device** | `debug_hrm_screen.dart:232-238` | ✅ Acceptable — QA-only screen |

**Recommendation:** Add confirmation dialogs for device unlink and tag deletion.

---

## 7. Accessibility

### 7.1 Flutter (`Semantics`)

**Search results:**

| Widget | `Semantics` / `semanticsLabel` usage |
|--------|--------------------------------------|
| `ErrorState` | ✅ `Semantics(label: 'Erro: $friendly', liveRegion: true)` |
| `EmptyState` | ✅ `Semantics(label: '$title. $subtitle')` |
| `NoConnectionBanner` | ✅ `Semantics(liveRegion: true, label: ...)` |
| `ShimmerLoading` | 1 occurrence of `semanticsLabel` |
| `SummaryMetricsPanel` | 6 occurrences |
| All 80+ screens | ❌ No screen-level `Semantics` wrappers found outside the shared widgets |

**Assessment:** ⚠️ The reusable widgets have good accessibility support, but individual screens do not add semantic labels to their interactive elements, lists, or key sections.

**Specific gaps:**
- No `Semantics` on list items in screen-specific ListViews
- No `semanticsLabel` on IconButtons (e.g., disconnect button in debug screen)
- No `ExcludeSemantics` to hide decorative elements
- No `MergeSemantics` to group related elements

### 7.2 Portal (Next.js) — `aria-*` Labels

**Search results:** `aria-` found in:
- `sidebar.tsx` (2 occurrences) ✅
- `fee-row.tsx` (1), `feature-flag-row.tsx` (2), `platform-sidebar.tsx` (1) ✅
- `data-table.tsx` (1), `confirm-dialog.tsx` (2) ✅
- `sparkline.tsx` (2), `bar-chart.tsx` (1), `kpi-card.tsx` (2), `filter-bar.tsx` (1) ✅

**Assessment:** ✅ Portal has reasonable aria coverage in shared UI components.

### 7.3 Color Contrast

The app uses Material 3 `colorScheme` tokens consistently, which generally provide WCAG AA contrast ratios. The `DesignTokens` class defines semantic colors (`.success`, `.error`, `.primary`, `.textMuted`).

**Potential issues:**
- `withValues(alpha: 0.4)` and `withValues(alpha: 0.3)` used on icons and containers may not meet contrast requirements
- Zone/intensity colors (green → red gradient for BPM) may be hard to distinguish for color-blind users

---

## 8. Call-to-Action Clarity

### 8.1 Strong CTAs ✅

| Screen | CTA | Assessment |
|--------|-----|------------|
| `athlete_device_link_screen` (empty state) | "Conectar Dispositivo" button | ✅ Clear |
| `debug_hrm_screen` (idle) | "Start Scan" button | ✅ Clear |
| `athlete_log_execution_screen` | "Registrar" button | ✅ Clear with disabled state during submit |
| Login screen | Social login buttons | ✅ |
| `welcome_screen` | Onboarding flow | ✅ |

### 8.2 Weak CTAs

| Screen | Issue |
|--------|-------|
| `athlete_device_link_screen` (empty + no providers) | Shows "Conectar Dispositivo" button that calls `_load()` (refresh), not an actual connect flow. Misleading label |
| Scan done with no devices found | Shows "No HR devices found yet..." with only Rescan option. No guidance on troubleshooting |

---

## 9. Summary of Findings

| # | Finding | Severity | Category |
|---|---------|----------|----------|
| 1 | Tag deletion has no confirmation dialog | **Major** | Missing confirmation |
| 2 | Device unlink has no confirmation dialog | **Major** | Missing confirmation |
| 3 | Raw `e.toString()` shown to users in some error SnackBars | **Major** | Error quality |
| 4 | Mixed shimmer vs spinner loading patterns | **Minor** | Consistency |
| 5 | Hardcoded Portuguese strings instead of l10n keys | **Minor** | i18n |
| 6 | No screen-level `Semantics` wrappers on individual screens | **Major** | Accessibility |
| 7 | No `semanticsLabel` on most IconButtons | **Minor** | Accessibility |
| 8 | Low-alpha colors may fail WCAG contrast | **Minor** | Accessibility |
| 9 | No color-blind mode or alternative indicators for BPM zones | **Minor** | Accessibility |
| 10 | Empty state "Conectar Dispositivo" button is misleading (calls refresh) | **Minor** | CTA clarity |

---

## 10. Positive Highlights

1. **Consistent design system** — `DesignTokens`, shared widgets (`ErrorState`, `EmptyState`, `ShimmerLoading`), Material 3 theming
2. **Universal loading states** — Every screen has a loading indicator
3. **Extensive action feedback** — 48+ screens use SnackBars for success/error, covering virtually all user actions
4. **Confirmation dialogs on most destructive actions** — Cancel training, cancel championship, delete account, remove member, leave assessoria
5. **Offline awareness** — `NoConnectionBanner` provides global offline detection with live-region semantics
6. **Error humanization** — `ErrorState.humanize()` and `humanizeLocalized()` convert raw errors to friendly Portuguese messages
7. **i18n infrastructure** — `AppLocalizations` with `context.l10n` pattern used in many screens
8. **Auto-reconnect UX for BLE** — Clear reconnecting state with last BPM display and manual stop option
