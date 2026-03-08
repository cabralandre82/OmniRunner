# Market & Release Readiness Audit — Omni Runner

**Date:** 2026-03-08
**Scope:** Flutter app (`omni_runner/`), Next.js portal (`portal/`), Supabase backend, docs/
**Perspective:** B2B2C platform readiness for app store submission and soft launch

---

## Executive Summary

Omni Runner is a technically mature B2B2C running platform with genuinely differentiated features (Running DNA, OmniCoin economy, Liga de Assessorias). The codebase has passed 12 QA gates, 1549 Flutter tests, 488 portal unit tests, and 85 E2E tests. Post-audit security fixes have raised the weighted quality score from 58 to 84/100.

**However, the platform is NOT ready for public release.** Critical gaps remain in legal compliance, store listing assets, cold-market onboarding, and accessibility. The product is well-suited for a **closed B2B-led soft launch** (assessoria-first) but would fail in an organic app store discovery context.

**Release Recommendation: CONDITIONAL GO for closed beta / assessoria-led soft launch. NO GO for public store listing.**

---

## 1. Store Listing Readiness

**Rating: 7/10 (Content) · 2/10 (Assets)**

### What exists

| Asset | Status | Quality |
|-------|--------|---------|
| App title | READY | "Omni Runner — Desafios de Corrida" — clear, 30 chars |
| Subtitle | READY | "Treine com assessoria, desafie amigos, descubra seu DNA" |
| Short description (80 chars) | READY | Hits 3 value props in 74 chars |
| Full description | READY | 67 lines, well-structured, keyword-rich |
| Screenshot guide (8 screens) | SPEC ONLY | Detailed mockup specs exist but **no actual screenshots produced** |
| App icon | PARTIAL | Silhouette runner exists but no high-res marketing icon confirmed |
| Preview video | MISSING | No video spec or asset |
| Feature graphic (Play Store) | MISSING | Not mentioned anywhere |

### Strengths

- The full description is genuinely compelling. It leads with differentiation (Running DNA), follows with the core loop (OmniCoin challenges), and includes clear audience segmentation.
- The screenshot guide (`ASO_SCREENSHOTS_GUIDE.md`) is production-quality spec work — 8 screens with exact layouts, captions, and design direction.
- Localization is consistent (pt-BR throughout).

### Blockers

- **No actual screenshot assets exist.** The guide is a spec, not deliverables. Store submission requires 4-8 real screenshots per device class.
- **No preview video.** Top-performing running apps (Strava, Nike Run Club) use video in listings.
- **No A/B test variants prepared**, despite the guide recommending DNA vs Today as hero shot.
- **Welcome screen says "Corra com GPS preciso"** but the app doesn't record GPS natively — it imports from Strava. This is a store listing compliance risk (misleading claims).

### Verdict

Store description copy is strong. Physical assets (screenshots, video, feature graphic) are completely missing. The "GPS preciso" claim needs revision to avoid store review rejection.

---

## 2. Legal Compliance

**Rating: 3/10 — BLOCKER**

### Privacy Policy

| Requirement | Status | Notes |
|-------------|--------|-------|
| Privacy policy document | STUB | `PRIVACY_POLICY_STUB.md` exists with correct structure |
| Contact email for DPO | MISSING | Placeholder `[INSERIR EMAIL DO DPO]` |
| Data retention periods | INCOMPLETE | Logs and financial data marked as `[DEFINIR]` |
| Hosted URL for stores | MISSING | Apple/Google require a live URL |
| In-app link (login screen) | EXISTS | Login screen links to policy, but URL is empty |
| In-app link (settings) | MISSING | No privacy policy link in settings |

### Terms of Service

| Requirement | Status |
|-------------|--------|
| Terms of service document | MISSING |
| User acceptance flow | MISSING |
| Hosted URL | MISSING |

### LGPD/GDPR Compliance

| Requirement | Status | Notes |
|-------------|--------|-------|
| Consent collection before data processing | MISSING | No opt-in mechanism |
| Data deletion (Art. 18 LGPD) | PARTIAL | Account deletion exists but does NOT delete `coin_ledger`, `sessions`, `runs`, `challenge_participants`, `wallets` |
| Data export / portability | MISSING | No export feature for users |
| Right to correction | PARTIAL | Profile editing exists |
| Consent revocation | MISSING | No mechanism to withdraw consent |
| Legal basis documentation | EXISTS | Table in privacy stub maps purposes to legal bases |
| Data minimization | GOOD | Only collects fitness-relevant data |

### Health Data Handling

| Requirement | Status | Notes |
|-------------|--------|-------|
| Health data disclaimer | MISSING | App collects GPS, heart rate, workout data but has no medical/fitness disclaimer |
| Apple HealthKit compliance | PARTIAL | `Info.plist` has usage descriptions but missing `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` |
| Google Health Connect | EXISTS | Android manifest has proper permission rationale |
| Background location rationale | MISSING | `ACCESS_BACKGROUND_LOCATION` declared without in-app justification dialog (Google Play policy requirement) |

### Blockers

1. **No live privacy policy URL** — Apple and Google both reject apps without one
2. **No terms of service** — required for financial features (OmniCoins)
3. **Incomplete data deletion** — LGPD Art. 18 violation
4. **No health data disclaimer** — collecting heart rate and GPS creates liability
5. **Missing iOS permission descriptions** — app will crash on camera/photo access

---

## 3. Onboarding First Impression

**Rating: 6/10**

### 30-Second Test

| Question | Answer | Evidence |
|----------|--------|----------|
| Does user understand what the app does? | YES (partially) | Welcome screen: "Seu app de corrida completo" + 4 bullets |
| Does user understand why they should use it? | WEAK | Benefits are listed but not demonstrated. No visual preview of Running DNA, challenges, or dashboards |
| Does user know how to get started? | YES | CTA "COMEÇAR" is clear. Social login reduces friction to 0 fields |

### Onboarding Flow (minimum path)

| Step | Screen | Time | Fields | Decisions |
|------|--------|------|--------|-----------|
| 1 | Welcome | 3s | 0 | 1 (tap COMEÇAR) |
| 2 | Login (social) | 5s | 0 | 1 (choose provider) |
| 3 | Role selection | 8s | 0 | 2 (choose + confirm) |
| 4 | Join assessoria | 5s | 0 | 1 (tap "Pular") |
| 5 | Tour (skip) | 3s | 0 | 1 (tap "Pular") |
| **Total** | **5 screens** | **~24s** | **0** | **6** |

### Strengths

- Zero mandatory fields with social login — excellent
- "Pular" (skip) always visible on optional steps
- Deep link / invite code survives the login flow
- TipBanner post-onboarding provides clear first steps
- Animated welcome screen conveys polish

### Critical Issues

1. **Cold start desert**: After onboarding, EVERY dashboard card leads to an empty state. Time-to-value is hours/days, not minutes.
2. **"Corra com GPS preciso"** on welcome screen creates expectation the app records runs. It doesn't — it imports from Strava.
3. **Tour is 9 slides** — excessive. 4-5 would suffice. Most users skip it entirely.
4. **"Assessoria" concept** is asked too early. New users don't know what it means yet.
5. **No demo/sample data** — no preview of what the experience looks like with real data.
6. **iOS permission strings in English** while app is in Portuguese — inconsistency.

### Verdict

The minimum onboarding path (24 seconds, 0 fields) is technically excellent. But the post-onboarding experience is an empty desert that fails to deliver any value without external setup (Strava connection, physical running, assessoria membership).

---

## 4. Competitive Positioning

**Rating: 7/10 (Differentiation) · 4/10 (Communication)**

### Differentiators vs. Major Competitors

| Feature | Strava | Nike Run Club | Garmin Connect | **Omni Runner** |
|---------|--------|---------------|----------------|-----------------|
| GPS recording | Native | Native | Native | **Via Strava only** |
| Social challenges | Segment-based | Guided runs | Badges | **1v1/group with OmniCoin stakes** |
| Coaching integration | Paid (Summit) | None | None | **Native B2B (assessoria model)** |
| Gamification | Limited | Achievements | Badges | **XP, levels, streaks, badges, DNA radar** |
| Running DNA profile | None | None | None | **Unique — 6-axis radar chart** |
| Virtual economy | None | None | None | **OmniCoins with clearing system** |
| Inter-group competition | None | None | None | **Liga de Assessorias** |
| Anti-cheat verification | None | None | None | **GPS + HR verification system** |
| Park rankings | Segments | None | None | **Dedicated park leaderboards** |
| Wrapped/retrospective | Year in Sport | None | None | **Custom wrapped cards** |

### What makes this unique

The combination of **B2B coaching integration + virtual currency economy + gamified progression** is genuinely novel in the running app space. No competitor offers assessoria-level group management with a financial clearing system.

### B2B2C Model Communication

| Audience | Is the model clear? | Where? |
|----------|-------------------|--------|
| Assessorias (B2B) | PARTIAL | `TERMOS_OPERACIONAIS.md` explains fees, but there's no landing page, pricing page, or sales deck in the codebase |
| Athletes (B2C) | WEAK | Welcome screen mentions "assessoria" but doesn't explain the value prop clearly |
| Investors/partners | MISSING | No pitch deck, no business model documentation |

### OmniCoin Gamification Assessment

| Aspect | Rating | Notes |
|--------|--------|-------|
| Concept | Strong | Virtual currency for challenge stakes is compelling |
| Economy design | Mature | Clearing, swap, custody, audit trail — enterprise-grade |
| User onboarding to coins | WEAK | New user gets 0 coins with no way to earn without assessoria |
| Motivation loop | STRONG (warm) / BROKEN (cold) | Works great when coach distributes coins; fails for solo users |

### Verdict

The platform has world-class differentiation that no competitor matches. However, this differentiation is invisible to cold-market users. The "Strava dependency" positioning (add-on vs standalone) is the Achilles' heel — users expect a running app to record runs.

---

## 5. Monetization Clarity

**Rating: 8/10 (Documentation) · 4/10 (User-Facing)**

### Fee Structure (from `TERMOS_OPERACIONAIS.md`)

| Fee Type | Rate | Base | Transparent? |
|----------|------|------|-------------|
| Billing split | 2.50% | Athlete subscription payment (Asaas) | YES — in docs |
| Athlete maintenance | $0–$10 USD/athlete | Fixed, deducted from payment | YES — configurable |
| Clearing (interclub) | 3.00% | Compensation volume | YES — in docs |
| Swap (liquidity) | 1.00% | Transfer amount | YES — in docs |
| FX spread (in/out) | 0.75–1.00% | Currency conversion | YES — in docs |

### What works

- `TERMOS_OPERACIONAIS.md` is comprehensive and well-structured
- Portal exposes all fees, balances, and audit trails to assessorias
- Platform admin can configure all fee rates via `/api/platform/fees`
- Custody invariant checks prevent financial inconsistencies

### What's missing

- **No public pricing page** — assessorias can't see costs before signing up
- **No in-portal fee explainer** — coaches see numbers but not what each fee means
- **No comparison calculator** — "how much will I pay for 50 athletes?"
- **No invoice/receipt system** visible in the codebase
- **Terms are a doc, not a legal agreement** — no acceptance flow

### Verdict

The financial engine is enterprise-grade. Documentation is thorough. But the user-facing transparency is poor — an assessoria coach would need to read a 135-line technical document to understand their costs.

---

## 6. Error Recovery

**Rating: 7/10**

### Error Handling Infrastructure

| Component | Status | Quality |
|-----------|--------|---------|
| `ErrorState` widget with `humanize()` | EXISTS | Translates raw exceptions to pt-BR messages |
| `EmptyState` widget with CTA | EXISTS | Icon + title + subtitle + optional action button |
| `NoConnectionBanner` | EXISTS | Auto-shows/hides with live connectivity detection |
| Shimmer loading states | 89% coverage | Mirrors layout during loading |
| Pull-to-refresh | 40+ screens | Standard Material refresh |
| `Semantics(liveRegion: true)` on errors | EXISTS | Screen reader announces errors |
| Portal `error.tsx` boundary | EXISTS | Generic error page, no stack traces |
| Portal toast system (sonner) | EXISTS | Consistent feedback |

### Strengths

- `ErrorState.humanize()` converts socket errors, timeouts, 401/403/404/500 into user-friendly Portuguese messages
- Retry buttons on error states guide users to recovery
- Connectivity banner appears/disappears automatically
- Error messages truncated at 100 chars to prevent raw exception leaks

### Weaknesses

| Issue | Severity |
|-------|----------|
| Error state coverage is only ~38% of app screens | HIGH |
| Empty state coverage is only ~16% of screens | HIGH |
| No "discard changes?" guard on form navigation | MEDIUM |
| Support screen requires assessoria membership — solo users can't get help | HIGH |
| League screen conflates "no season" with "network error" | MEDIUM |
| Some screens still use bare `CircularProgressIndicator` instead of shimmer | LOW |

### Verdict

The error recovery primitives are well-designed (humanized messages, retry buttons, connectivity detection). But coverage is incomplete — 62% of screens have no explicit error recovery path.

---

## 7. Accessibility

**Rating: 5/10**

### What exists

| Feature | Status | Notes |
|---------|--------|-------|
| `Semantics` widgets | 21 files | Used on key widgets (ErrorState, EmptyState, NoConnectionBanner, metrics panel) |
| `semanticLabel` | Present | On interactive elements in ~15 screens |
| `liveRegion: true` | Present | Error and connectivity banners announce to screen readers |
| Design tokens font sizes | Defined | Body: 16pt, Caption: 12pt, Label: 14pt, Title: 20-24pt |
| Dark/light mode | EXISTS | Both themes use design tokens for contrast |
| Material 3 components | YES | Inherits Material accessibility defaults |

### Contrast Analysis (Dark Mode)

| Element | Foreground | Background | Ratio (approx) | WCAG AA |
|---------|-----------|------------|:-----------:|:-------:|
| Primary text | `#F1F5F9` | `#0A0E17` | ~16:1 | PASS |
| Secondary text | `#94A3B8` | `#0A0E17` | ~6.5:1 | PASS |
| Muted text | `#64748B` | `#0A0E17` | ~3.8:1 | FAIL (AA requires 4.5:1) |
| Primary on surface | `#3B82F6` | `#1E293B` | ~3.2:1 | FAIL |
| Error on container | `#EF4444` | `#0A0E17` | ~4.6:1 | PASS (barely) |

### Contrast Analysis (Light Mode)

| Element | Foreground | Background | Ratio (approx) | WCAG AA |
|---------|-----------|------------|:-----------:|:-------:|
| Primary text | `#0F172A` | `#F8FAFC` | ~17:1 | PASS |
| Secondary text | `#475569` | `#F8FAFC` | ~6.7:1 | PASS |
| Muted text | `#94A3B8` | `#F8FAFC` | ~2.5:1 | FAIL |

### Gaps

1. **Muted text fails WCAG AA** in both themes — used for captions, timestamps, secondary info
2. **Primary blue on dark surface fails contrast** — interactive elements may be hard to see
3. **No `textScaleFactor` handling** — no evidence of testing with system font scaling
4. **No `ExcludeSemantics` / `MergeSemantics`** usage found — semantic tree may be noisy
5. **Touch target sizes not explicitly enforced** — relies on Material defaults (48dp)
6. **No accessibility testing documented** — no TalkBack/VoiceOver test results
7. **Portal has no skip-navigation link** or ARIA landmarks beyond defaults

### Verdict

Basic accessibility is in place through Material 3 defaults and targeted `Semantics` use. Two contrast failures need fixing. Comprehensive screen reader testing and font scaling testing have not been done.

---

## 8. Documentation

**Rating: 8/10**

### Documentation Inventory

| Category | Document(s) | Status | Quality |
|----------|------------|--------|---------|
| **Architecture** | `ARCHITECTURE.md`, `POST_REFACTOR_ARCHITECTURE.md` | COMPLETE | Comprehensive |
| **API Reference** | `PORTAL_API.md` | COMPLETE | All endpoints documented with Zod schemas, rate limits, auth requirements |
| **Deployment Runbook** | `PRODUCTION_READINESS.md`, `ROLLBACK_RUNBOOK.md`, `STEP05_ROLLOUT.md`, `OS06_RELEASE_RUNBOOK.md` | COMPLETE | Step-by-step deploy, rollback, and verification |
| **Security Audit** | `USERZERO_06_SECURITY_PRIVACY.md`, `CHAOS_RLS.md`, `QA_GATE5_SECURITY.md` | COMPLETE | 21 findings documented and tracked |
| **QA / Testing** | 12 QA gate documents + pre-release sign-off | COMPLETE | Thorough gate-based QA process |
| **UX Audit** | `AUDIT_UX_DETAILED.md`, `COLD_MARKET_REPORT.md`, multiple sub-reports | EXTENSIVE | Cold market, onboarding, value test — deeply analyzed |
| **Financial/Business** | `TERMOS_OPERACIONAIS.md`, `BLOCO_B_FINANCIAL_ENGINE.md` | COMPLETE | Fee structure, clearing, custody |
| **Beta Program** | `BETA_PROGRAM.md` | COMPLETE | 3-phase rollout plan with criteria |
| **Changelog** | `CHANGELOG.md` | COMPLETE | Structured release notes |
| **Troubleshooting** | MISSING | — | No troubleshooting guide |
| **User Guide (Athletes)** | MISSING | — | No end-user documentation |
| **User Guide (Coaches/Portal)** | MISSING | — | No portal user manual |
| **OpenAPI/Swagger** | MISSING | — | API docs are markdown, not machine-readable |
| **Contributing Guide** | MISSING | — | No developer onboarding doc |
| **ENV Variables Reference** | PARTIAL | `.env.example` exists | Not all vars documented with descriptions |

### Strengths

- **216 documentation files** in `docs/` — extensive coverage
- API documentation includes Zod schemas, rate limits, error codes, and auth requirements
- Deployment runbook covers all components (DB, Portal, Flutter, Edge Functions) with rollback procedures
- Security findings are tracked with severity, evidence, and remediation status
- Decision log exists (`DECISIONS_LOG.md`)

### Gaps

1. **No troubleshooting guide** — no FAQ for common deploy/runtime issues
2. **No end-user documentation** — athletes and coaches have no manual
3. **No OpenAPI/Swagger spec** — API consumers must read markdown
4. **No developer onboarding guide** — new team members have no starting point

---

## Consolidated Readiness Scorecard

| Area | Score | Status | Blockers |
|------|:-----:|--------|----------|
| Store Listing (Content) | 7/10 | READY (copy) | "GPS preciso" claim needs revision |
| Store Listing (Assets) | 2/10 | NOT READY | No screenshots, video, or feature graphic |
| Legal Compliance | 3/10 | BLOCKER | No live privacy policy, no ToS, incomplete data deletion |
| Onboarding (Structure) | 8/10 | READY | Min path is fast, skip-friendly |
| Onboarding (Value Delivery) | 3/10 | WEAK | Cold start desert, no demo data |
| Competitive Positioning | 7/10 | STRONG | Genuinely unique features |
| B2B2C Communication | 4/10 | WEAK | No pricing page, no sales materials |
| Monetization (Engine) | 9/10 | STRONG | Enterprise-grade financial system |
| Monetization (Transparency) | 4/10 | WEAK | No user-facing fee explainer |
| Error Recovery | 7/10 | ADEQUATE | Good primitives, incomplete coverage |
| Accessibility | 5/10 | PARTIAL | 2 contrast failures, no screen reader testing |
| Documentation (Technical) | 8/10 | STRONG | 216 docs, thorough QA process |
| Documentation (User-Facing) | 2/10 | MISSING | No user guides |
| Security (Post-Fix) | 8/10 | CONDITIONAL | 3 CRITICAL fixed; verify in staging |

**Weighted Overall: 5.4/10**

---

## Release Recommendation

### PUBLIC APP STORE RELEASE: NO GO

**Reason:** 5 hard blockers prevent store submission:

1. **No live privacy policy URL** (Apple/Google requirement)
2. **No terms of service** (required for financial features)
3. **No screenshot assets** (store listing incomplete)
4. **Misleading "GPS preciso" claim** (store compliance risk)
5. **Incomplete LGPD data deletion** (legal liability)

### CLOSED BETA / ASSESSORIA-LED SOFT LAUNCH: CONDITIONAL GO

The platform is suitable for a controlled launch where:

- Assessorias are onboarded manually (B2B sales, not store discovery)
- Athletes arrive via coach invitation (warm market, not cold)
- Distribution is via Firebase App Distribution or TestFlight (not public store)

**Conditions before even soft launch:**

| # | Condition | Effort | Priority |
|---|-----------|--------|----------|
| 1 | Finalize privacy policy (fill all `[INSERIR]` placeholders) and host at a public URL | 1 day | P0 |
| 2 | Create basic terms of service and host at public URL | 1-2 days | P0 |
| 3 | Complete data deletion to include all user-linked tables (coin_ledger, sessions, runs, wallets) | 1 day | P0 |
| 4 | Verify `verify_jwt = true` doesn't break webhooks/crons in staging | 1 day | P0 |
| 5 | Configure `CORS_ALLOWED_ORIGINS` with production domains (remove localhost defaults) | 30 min | P0 |
| 6 | Add health data disclaimer to app (non-medical advice notice) | 30 min | P1 |
| 7 | Fix iOS `Info.plist` missing camera/photo permission descriptions | 30 min | P1 |
| 8 | Add background location rationale dialog (Google Play requirement) | 2 hours | P1 |
| 9 | Fix muted text contrast ratio (bump `#64748B` → `#7C8BA5` or similar) | 1 hour | P1 |
| 10 | Change "Corra com GPS preciso" to "Acompanhe corridas com dados GPS" or similar | 30 min | P1 |

**Estimated time to soft-launch readiness: 3-5 days of focused work.**

### PUBLIC STORE READINESS: 3-4 WEEKS ADDITIONAL

Beyond the soft-launch conditions:

| # | Item | Effort |
|---|------|--------|
| 1 | Produce 8 actual screenshots per device class (iPhone + Android) | 3-5 days |
| 2 | Create 30-second preview video | 1 week |
| 3 | Build public-facing pricing/landing page for assessorias | 1 week |
| 4 | Implement cold-start improvements (Strava history import, demo data, welcome OmniCoins) | 2 weeks |
| 5 | Reduce onboarding tour from 9 to 4-5 slides | 1-2 days |
| 6 | Create user guides for athletes and coaches | 1 week |
| 7 | Full accessibility audit with TalkBack/VoiceOver | 3-5 days |
| 8 | Create OpenAPI spec from portal API routes | 2-3 days |

---

## Strategic Recommendation

This platform's natural go-to-market is **B2B-first**:

1. **Phase 1 (Now):** Closed beta with 5-10 assessorias via direct onboarding. Fix the 10 conditions above.
2. **Phase 2 (Month 2):** Open beta with 50+ assessorias. Build landing page, produce store assets.
3. **Phase 3 (Month 3-4):** Public store launch. Solve cold-start problem (Strava history import, welcome coins, demo data).

The product has world-class features trapped behind a world-class cold-start problem. Lead with B2B (where the coach solves the cold start), then expand to B2C once the ecosystem has critical mass.

> **Bottom line:** Ship to coaches first. They'll bring the athletes. The app store can wait.
