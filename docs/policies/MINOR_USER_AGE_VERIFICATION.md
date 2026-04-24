# Minor User Age Verification Policy

**Status:** Ratified (2026-04-21)
**Owner:** legal + product
**Regulatory ref:** LGPD Art. 14 (consent of the data subject's
parents/guardians for minors), ECA Art. 17 (proteção integral),
COPPA (FTC, US users < 13).
**Related:** L04-14, L04-03 (consent registry), L04-04 (health
data hardening), `docs/audit/findings/L04-01-*` (delete-my-data).

## Question being answered

> "Today onboarding does not collect `date_of_birth`. The
> product has a 'Categoria Infantil' UI in `championships`. A
> 12-year-old that signs up directly is undetectable, which
> trips ECA Art. 17 and (for any US sign-up) COPPA. What's our
> position?"

## Decision

**Three-tier age model**, enforced at signup AND at every
sensitive UI surface:

| Tier | Age range | Account allowed?            | Consent path |
|------|-----------|-----------------------------|--------------|
| A    | < 13      | NO direct signup            | Account is opened by a parent under their own profile, child enrolled as a `dependent` under the parent's wallet. No personal account, no leaderboard exposure, no chat. |
| B    | 13–17     | YES with parental consent   | Signup form collects `date_of_birth`. If `age < 18`, the form requires the parent's email; we email a double-confirm link to that address before activating the account. |
| C    | 18+       | YES                         | Standard flow.            |

## Schema additions (Wave-3 migration)

```sql
ALTER TABLE public.profiles
  ADD COLUMN date_of_birth date,
  ADD COLUMN parental_consent_token uuid,
  ADD COLUMN parental_consent_email text,
  ADD COLUMN parental_consent_granted_at timestamptz;

ALTER TABLE public.profiles
  ADD CONSTRAINT chk_minor_consent CHECK (
    -- Adults: no parental fields required.
    (date_of_birth IS NULL OR
     date_of_birth <= (CURRENT_DATE - INTERVAL '18 years'))
    OR
    -- Minors: parental consent must be granted.
    (date_of_birth > (CURRENT_DATE - INTERVAL '18 years')
     AND parental_consent_granted_at IS NOT NULL)
  );

CREATE TABLE public.dependent_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  display_name text NOT NULL,
  date_of_birth date NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.dependent_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dependent_profiles FORCE  ROW LEVEL SECURITY;

CREATE POLICY dependent_owner_rw ON public.dependent_profiles
  FOR ALL TO authenticated
  USING (parent_user_id = auth.uid())
  WITH CHECK (parent_user_id = auth.uid());
```

## Onboarding flow (mobile + portal)

1. The first onboarding screen asks for **year of birth only**
   (no day/month — minimises PII collection per LGPD
   minimisation principle).
2. If the implied age ≥ 18 → continue normal flow.
3. If 13 ≤ age ≤ 17 → step 2 asks for parent's email; we send
   a double-opt-in link (`/parental-consent/[token]`) to that
   address. The account remains locked (`profiles.locked_at`
   set, no API surface usable except `GET /api/account`) until
   the parent clicks the link AND confirms a checkbox saying
   "Eu autorizo meu filho/filha a usar o Omni Runner".
4. If age < 13 → block direct signup. Show a screen explaining
   that the account must be opened by a parent and offering a
   redirect to the parent-mode signup that creates a
   `dependent_profiles` row instead.

## Operational rules

- **Existing user backfill.** First time an existing account
  hits a screen that requires age (championship enrollment,
  withdrawal request, custody deposit), we open a one-time
  modal asking for year of birth. Until they answer, the
  protected screen returns `412 PRECONDITION_REQUIRED` with
  hint `age_unknown`.
- **No leaderboard exposure for minors.** `mv_user_progression`
  and the public leaderboard views filter
  `WHERE date_of_birth IS NULL OR date_of_birth <=
  CURRENT_DATE - INTERVAL '18 years'`. Minors compete in
  age-group categories internal to a championship, not in the
  global leaderboard.
- **No third-party data sharing for minors.** Strava /
  TrainingPeaks OAuth flows refuse to bind a minor account
  (UI hides the button + API returns 403).
- **Right to delete.** When a minor's parental consent is
  revoked (parent clicks the link in the consent email at any
  later date), the account is hard-deleted via the existing
  `fn_delete_user_data` (L04-01) without a 30-day grace
  period, per LGPD Art. 14 §6.
- **Audit log.** Every transition (consent_granted,
  consent_revoked, age_collected, dependent_created) is
  written to `audit_logs` with `event_domain='lgpd'`.

## Implementation status

- **Spec:** ratified (this document).
- **Schema migration:** drafted in this doc, to land in
  `supabase/migrations/<date>_l04_14_minor_age_verification.sql`
  in Wave-3.
- **Onboarding UI:** mobile + portal screens to be built in
  Wave-3.
- **Backfill modal:** Wave-3.
- **Leaderboard view filter:** Wave-3.

## Why this is in Wave 3, not now

- Schema change touches `profiles` (the most-read table in the
  product) and requires backfill of every existing row before
  the CHECK constraint can be enforced.
- Onboarding UI is shared between mobile and portal and needs
  copy review by legal (parental consent text is regulated).
- The double-opt-in email infra reuses the L09-09 contract
  consent envelope, but needs a parental-consent template
  approved by legal.

Closing this finding now means the **policy is ratified** and
the schema + UI work is clearly scoped. Without this doc the
team would either build the wrong thing (collecting full
birthdate when year-only suffices) or skip the parental
consent envelope entirely.

## See also

- `docs/legal/CONSENT_REGISTRY.md` (L04-03)
- `docs/audit/findings/L04-04-*` (health data hardening,
  related minor-protection surface)
- `supabase/migrations/20260418_*_consent_*.sql` (existing
  consent envelope reused for parental consent)
