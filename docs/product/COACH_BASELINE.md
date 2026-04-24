# Coach Persona Baseline

**Status:** Ratified (2026-04-24), implementation Wave 4-5
**Owner:** product + backend + portal + mobile
**Related — K12 batch (this doc):** L23-15 (CRM funnel),
L23-16 (PJ earnings dashboard), L23-17 (CREF validation),
L23-18 (AI Copilot), L23-19 (multi-club aggregate),
L23-20 (iCal calendar feed).
**Cross-refs:** L15-01 (attribution), L16-08 (marketplace),
L23-12 (athlete onboarding state), L23-14 (time-trial),
L05-14 (moderation), L04-12 (PII masking).

## Question being answered

> "The coach persona is the second-largest B2B revenue
> source for the platform (after assessorias). They are
> professional users who need the tools of their trade —
> a sales funnel, a transparent payout statement, a way to
> prove credentials, decision support for prescriptions, a
> multi-club pane, and integrations with the calendar they
> already live in. We have 80% of the underlying data
> already; we have shipped ~ 40% of the surfaces."

## Decision

A **single coach-persona module** covering the six product
gaps identified in Lente 23 items 15–20. Each is a
surface on top of data we already capture (coaching_members,
billing_purchases, profiles, plan_workouts); the
shipping cost is UI + a handful of RPCs + one OAuth
integration. Ratified as Wave 4-5 work splitting by
infrastructure cost (§ Implementation phases).

## The 6 features

### 1. Lead-to-athlete CRM funnel (L23-15)

**What.** A funnel-scoped extension of the existing coach
CRM (`staff_crm_list_screen.dart`) that tracks athletes
from **lead** through **trial** to **paid conversion**,
with source attribution linked to the marketing attribution
system (L15-01).

**Today's state.** `staff_crm_list_screen` shows a list of
joined athletes with tags and member status. It's an
**in-group** CRM (people who are already in your coaching
group). It does **not** track:

- Landing-page leads who haven't signed up yet.
- Trial-status athletes who signed up but haven't paid.
- Conversion attribution (which campaign, which coach
  referral, which organic channel).

**New state model.**

```
lead → invited → joined → trial → active (paid) → churned
                    │        │        │             │
                    │        └── hasn't paid ──── lapsed trial
                    └── ─ ─ ─ ─ ─ ─ ─ accepted_invite_never_paid
```

`active` is terminal-for-now; `churned` is a soft state
(cancelled + N days after last activity). `lead` and
`trial` are the two new stages that don't exist today.

**Schema.**

```sql
create table public.coaching_leads (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.coaching_groups(id),
  source text not null,                 -- 'landing','referral_athlete',
                                        -- 'referral_coach','organic','paid_ads'
  utm_source text,
  utm_medium text,
  utm_campaign text,
  referral_user_id uuid references auth.users(id),
  email text,
  phone text,
  name text,
  status text not null default 'new' check (status in
    ('new','contacted','qualified','converted','lost')),
  converted_user_id uuid references auth.users(id),
  converted_at timestamptz,
  lost_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index coaching_leads_group on public.coaching_leads (group_id)
  where status in ('new','contacted','qualified');

alter table public.coaching_leads enable row level security;

create policy coaching_leads_staff on public.coaching_leads
  for all using (
    exists (
      select 1 from public.coaching_members cm
      where cm.group_id = coaching_leads.group_id
        and cm.user_id = auth.uid()
        and cm.role in ('admin_master','coach')
    )
  )
  with check (
    exists (
      select 1 from public.coaching_members cm
      where cm.group_id = coaching_leads.group_id
        and cm.user_id = auth.uid()
        and cm.role in ('admin_master','coach')
    )
  );
```

**Trial state.** `coaching_members.trial_ends_at timestamptz`
(already indirectly captured via `billing_purchases.status =
'trialing'`). The CRM view joins the two.

**Landing page ingestion.** A public form on the coach's
public page (`/c/{slug}`) POSTs to `POST /api/coach/leads`
(rate-limited), which inserts a row into `coaching_leads`
with `source = 'landing'` and the parsed UTM params.

**Attribution.** The cookie `omni_att` written by L15-01's
attribution middleware is read at the `POST /api/coach/leads`
boundary; the UTM fields flow through. Signup attribution
is captured when `converted_user_id` is set (trigger at
`billing_purchases INSERT` with `status != 'trialing'`).

**UI additions (portal).** `/platform/crm/funnel` — new
page showing a Kanban board with 5 columns (new → contacted
→ qualified → converted/lost). Actions: move card, tag,
archive.

**Source-attribution dashboard.** `/platform/crm/attribution`:
leads by source × conversion rate, stacked over last 30/90
days. Reuses `analytics_events` infra.

**Out of scope v1.**

- Email-automation drip (beyond one manual "first-touch"
  template). Separate project.
- Lead scoring / ML. Irrelevant at current volume.
- Multi-user coach team inside one group (already handled
  by `coaching_members.role`).

### 2. Coach PJ earnings dashboard (L23-16)

**What.** A coach-facing dashboard at
`/platform/billing/earnings` that shows monthly gross,
platform fees (transparent), net earnings, next payout
date, and a printable statement PDF.

**Why.** A coach running as PJ needs to reconcile the
platform's numbers against their own accounting
(`DASN-SIMEI`, `LCP pro-labore`). Today they guess —
support tickets about "qual minha taxa líquida?" are one
of the top 5 categories per the support log. A
transparent dashboard closes the loop.

**Data model — reuse, no new columns.**

The existing `billing_purchases` already has:

- `amount_cents` (gross price paid by athlete)
- `platform_fee_cents` (Omni fee)
- `fx_spread_cents` (FX spread if cross-currency)
- `provider_fee_cents` (Asaas / Stripe fee)
- `net_to_seller_cents` (what goes to the coach's custody)
- `status`, `paid_at`

And `custody_withdrawals`:

- `amount_cents`, `status`, `requested_at`, `scheduled_at`

We derive everything with a **read-only view**:

```sql
create or replace view public.coach_earnings_monthly as
select
  bp.seller_user_id,
  date_trunc('month', bp.paid_at) as month,
  count(*) filter (where bp.status = 'paid')             as sales_count,
  sum(bp.amount_cents)         filter (where bp.status = 'paid') as gross_cents,
  sum(bp.platform_fee_cents)   filter (where bp.status = 'paid') as platform_fee_cents,
  sum(bp.provider_fee_cents)   filter (where bp.status = 'paid') as provider_fee_cents,
  sum(bp.fx_spread_cents)      filter (where bp.status = 'paid') as fx_spread_cents,
  sum(bp.net_to_seller_cents)  filter (where bp.status = 'paid') as net_cents,
  sum(bp.amount_cents)         filter (where bp.status = 'refunded') as refunded_cents
from public.billing_purchases bp
where bp.seller_user_id is not null
  and bp.paid_at is not null
group by bp.seller_user_id, date_trunc('month', bp.paid_at);

alter view public.coach_earnings_monthly
  set (security_invoker = true);

comment on view public.coach_earnings_monthly is
  'L23-16 — per-coach monthly earnings, read-only, RLS via
   security_invoker=true (filter by auth.uid() at the
   seller_user_id column).';
```

**RLS.** View-level; `security_invoker=true` means the
viewer's own `auth.uid()` filters the underlying
`billing_purchases` rows via existing RLS (which already
scopes by seller OR buyer). Coach sees only their rows.

**Next-payout prediction.** Reuses the existing scheduled
withdrawal cron output: `select min(scheduled_at)
from custody_withdrawals where user_id = auth.uid() and
status = 'pending'`. Labeled "Próximo repasse previsto: 15
de outubro".

**PDF statement.** "Extrato mensal" PDF generated on-demand
from the view + header block (CNPJ, razão social from
`coach_profile`). Same rendering path as Wrapped PDF
(L22-15) — `@react-pdf`. Hosted on `user-earnings-pdf`
bucket, 48h signed URL.

**UI (portal).** Single page with:

- Month picker (default: current month + last 11).
- KPI strip: Bruto · Taxas · Líquido · Próximo repasse.
- Table row-per-sale view (expandable).
- "Baixar extrato (PDF)" button.

**Fee explainer.** A static "?" icon expands a sheet:

> Para cada venda, cobramos **6%** de taxa de plataforma.
> Sua adquirente (Asaas ou Stripe) cobra ~ **3,5%** + R$ 0,30.
> Para vendas internacionais, adicionamos spread de câmbio
> explicitado no topo da linha. Você recebe o líquido em
> até 30 dias corridos após a compra, conforme o plano
> [L01-16 custody schedule].

**Out of scope v1.**

- NFS-e emission from within the dashboard (L09-04 / L03-19
  already has its own track — we link to it).
- Export CSV. Add when 1 coach asks for it.
- Tax-optimization suggestions. Out of domain.

### 3. CREF certificate validation (L23-17)

**What.** An upload-and-verify flow that stamps a "CREF
verified" badge on coach profiles after a human review.
Public listings can filter by "only verified".

**Why.** Anyone can create a coaching group today. BR
coaching has a formal certification (Conselho Regional de
Educação Física), and many federative / corporate partners
require proof. We're not the licensing body; we're a proof
surface.

**Flow.**

1. Coach → Settings → "Certificação CREF" → "Enviar
   comprovante".
2. Upload PDF (≤ 5 MB) + text field "Número CREF" (format
   `NNNNNN-[G|P]/UF`, regex-validated).
3. Stored encrypted at rest (storage bucket `coach-cref-docs`,
   RLS: self + platform admin).
4. Platform admin (`admin_master` at platform level, not
   group-admin) reviews in `/platform/admin/cref-queue`,
   clicks Approve / Reject (with reason).
5. On approval, `profiles.cref_verified_at` set; badge
   appears on public profile and coach search.

**Schema.**

```sql
alter table public.profiles
  add column cref_number text,
  add column cref_state text check (char_length(cref_state) = 2),
  add column cref_kind text check (cref_kind in ('G','P')),
  add column cref_doc_path text,        -- storage path
  add column cref_verified_at timestamptz,
  add column cref_verified_by uuid references auth.users(id),
  add column cref_rejected_at timestamptz,
  add column cref_rejection_reason text;

create index profile_cref_verified on public.profiles
  (cref_verified_at) where cref_verified_at is not null;
```

**Storage.** Bucket `coach-cref-docs`, RLS:

```sql
create policy cref_doc_self on storage.objects
  for select using (
    bucket_id = 'coach-cref-docs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy cref_doc_platform_admin on storage.objects
  for select using (
    bucket_id = 'coach-cref-docs'
    and exists (
      select 1 from public.platform_roles pr
      where pr.user_id = auth.uid()
        and pr.role = 'admin_master'
    )
  );
```

**Filter surface.** `/c/search?verified=1` adds a boolean
filter. The public profile page shows a "CREF verificado"
badge (small teal check) when populated.

**Trust boundary.** We **do not** call the public CREF
registry (the public endpoint is flaky and the data is
incomplete). Verification is human: `admin_master`
inspects the uploaded PDF against the claimed number.
This ships with a seeded runbook (`docs/runbooks/CREF_VERIFICATION_RUNBOOK.md`)
covering: what a valid CREF document looks like, state
variations, expiry rules, red flags.

**Compliance notes.**

- Uploaded docs are **personal-sensitive** under LGPD
  Art. 5º II; retention tied to `profiles` row, deleted
  via `fn_delete_user_data_lgpd_complete` (L04-11).
- "CREF" is a registered trademark of the Conselho; we
  always refer to "certificação CREF" (as a third-party
  credential), never as a platform-issued badge.

**Out of scope v1.**

- Auto-renewal reminders. Add when we have enough verified
  coaches to make the alert useful.
- Bulk import from assessoria admin. Separate spec.

### 4. AI Copilot for novice coaches (L23-18)

**What.** A chat surface inside the coach dashboard that
answers prescription-level questions using a RAG layer on
peer-reviewed running-science literature (Daniels'
Running Formula, Pfitzinger's Advanced Marathoning,
Fitzgerald's 80/20, Magness's The Science of Running) +
the coach's own athletes' context (pulled read-only from
their coaching_group).

**Why gated / opinionated.** A novice coach (first year
post-CREF or pre-CREF bootcamp grad) is where the
platform loses the most accounts — they sign up, can't
figure out how to prescribe a 16-week marathon plan for
a specific athlete, and churn to a spreadsheet. Copilot
doesn't replace the coach (we're explicit about this in
copy), it reduces the "blank page" anxiety.

**Architecture.**

```
┌─────────────────────┐
│ Coach asks a Q      │
│ (chat surface)      │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐   ┌─────────────────────┐
│ /api/ai/copilot     │-->│ Athlete context     │
│ (portal edge)       │   │ fetcher (RLS-scoped)│
└──────────┬──────────┘   └─────────────────────┘
           │
           ▼
┌─────────────────────┐   ┌─────────────────────┐
│ OpenAI / similar    │<--│ RAG retriever       │
│ (GPT-4o initially)  │   │ pgvector index on   │
│                     │   │ `coach_lit_docs`    │
└──────────┬──────────┘   └─────────────────────┘
           │
           ▼
┌─────────────────────┐
│ Response with       │
│ citations + disclaimer
└─────────────────────┘
```

**RAG corpus.** `coach_lit_docs` table:

```sql
create extension if not exists vector;

create table public.coach_lit_docs (
  id uuid primary key default gen_random_uuid(),
  source_title text not null,          -- e.g. "Daniels' Running Formula, 4th ed."
  source_author text not null,
  source_page int,
  chunk_text text not null,
  chunk_embedding vector(1536) not null,
  license text not null,               -- 'licensed' | 'public_domain' | 'fair_use_quote'
  created_at timestamptz not null default now()
);

create index coach_lit_docs_hnsw on public.coach_lit_docs
  using hnsw (chunk_embedding vector_cosine_ops);
```

Corpus built offline, licensed content only (we negotiate
with publishers for a distinct vector-DB-only right;
classical content is public domain — Daniels' early papers,
Pfitzinger's peer-reviewed studies). No scraping.

**Athlete context.** The chat session is bound to one
`athlete_id` (optional — can be "general question"). When
present, the edge function pulls (read-only, RLS-checked):

- Last 12 weeks of sessions (volume, pace distribution).
- `athlete_zones` (pace + HR) (L21-05).
- Current plan (L09-12).
- Onboarding goal (L22-18).

Context is injected into the prompt.

**Guardrails (must-have).**

- Every answer ends with: "Isto é uma sugestão baseada em
  [citations]. A prescrição final é responsabilidade do
  coach."
- Never claims medical / injury diagnosis. A hard filter
  on prompts matching `/lesão|dor|injury|hurt/i` returns a
  pre-baked response pointing to L22-16 injury triage.
- No direct medication / supplement advice. Same filter.
- PII stripping at the boundary (L04-13 Sentry/log stripping
  reused at `/api/ai/copilot`).

**Rate limit.** Per-coach: 30 messages / day on free tier,
unlimited on "Copilot Pro" tier (price TBD — product).
Already-existing `_shared/rate_limit.ts` covers it.

**Model choice.** GPT-4o first; fallback to Claude 3.5
Sonnet if upstream outage (we already wrap this pattern
in `generate-run-comment`). RAG chunks sent in the prompt
cap at 4k tokens; if more, summarize iteratively.

**Tier gating.** Copilot Pro (paid tier) unlocks:

- Higher rate limit.
- Structured outputs: "gerar plano de 16 semanas em JSON".
- Fine-tuning based on the coach's own coaching style
  (opt-in, from historic plan data).

**Privacy.** Each coach opts in explicitly; opt-out wipes
the coach's chat history and fine-tuning data. Athletes
**never** see the coach's Copilot chats. Zero-knowledge
posture at the ATHLETE side — we only pull athlete data
inside an RLS-scoped query, we never train a model on
athlete data without both the coach's and athlete's opt-in.

**Out of scope v1.**

- Voice UI. Web chat first.
- Multi-language (PT/EN only at launch).
- Auto-prescription (one-click "apply this plan"). Show
  the plan for the coach to accept/edit — never write
  without confirmation.

### 5. Multi-club aggregate dashboard (L23-19)

**What.** A single pane at `/platform/coach/today` that
aggregates "what needs my attention today" across all
groups the coach is a member of.

**Today's state.** A coach who coaches in 3 clubs (an
increasingly common pattern) has to switch groups via
`select-group` and re-load each screen. The existing
`coaching_members` schema is 1:N (a user can be in many
groups), but the UI funnels them through one group at a
time.

**Aggregate view.**

```
Today, 06:00
────────────────────────────────────────
NEEDS REVIEW                   [3 groups]
  · 2 feedbacks pending (Equipe Alpha)
  · 1 injury report (Equipe Beta)
  · 4 workouts to approve (Club Delta)

STARTING SOON (< 2h)
  · 07:00 Track session · 12 atletas · Alpha
  · 07:30 Easy run · 4 atletas · Delta

NO-SHOWS YESTERDAY
  · João Costa (Alpha) — 2nd in a row

NEW LEADS (L23-15)
  · 3 new (2 Alpha, 1 Delta)
```

Each line deep-links to the existing group-scoped screen;
clicking "STARTING SOON · Alpha" opens the same session
detail in the Alpha group context.

**Data source — no new tables.** The aggregate is a
client-side union of existing per-group queries in
parallel. Backend exposes **one** RPC that returns the
union, pre-filtered:

```sql
create or replace function public.coach_today_aggregate()
  returns table (
    kind text,          -- 'feedback','injury','approval','session_soon','no_show','lead'
    group_id uuid,
    group_name text,
    payload jsonb,
    priority int,
    ts timestamptz
  )
  language plpgsql
  security definer
  set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_groups uuid[];
begin
  if v_user is null then
    raise exception 'UNAUTHORIZED';
  end if;

  select array_agg(group_id)
    into v_groups
    from public.coaching_members
    where user_id = v_user
      and role in ('admin_master','coach');

  if v_groups is null or cardinality(v_groups) = 0 then
    return;
  end if;

  -- 1. feedbacks pending
  return query
    select 'feedback', cm.group_id, cg.name,
           jsonb_build_object('athlete_id', f.user_id,
                              'workout_id', f.workout_id),
           10,
           f.submitted_at
      from public.athlete_workout_feedback f
      join public.coaching_members cm
        on cm.user_id = f.user_id
      join public.coaching_groups cg on cg.id = cm.group_id
     where cm.group_id = any(v_groups)
       and f.acknowledged = false
       and f.submitted_at > now() - interval '72 hours';

  -- 2. sessions starting soon
  return query
    select 'session_soon', pw.group_id, cg.name,
           jsonb_build_object('session_name', pw.name,
                              'attendees', pw.expected_attendees),
           20,
           pw.scheduled_at
      from public.plan_workouts pw
      join public.coaching_groups cg on cg.id = pw.group_id
     where pw.group_id = any(v_groups)
       and pw.scheduled_at between now() and now() + interval '2 hours';

  -- ...additional kinds (approval, no_show, lead)...
end;
$$;
revoke all on function public.coach_today_aggregate() from public;
grant execute on function public.coach_today_aggregate() to authenticated;
```

**RLS note.** `SECURITY DEFINER` with a hard `auth.uid()`
gate + the `v_groups` filter is the canonical pattern
already used in 26+ functions (L18-03). Groups list is
computed once per call.

**UI.**

- Portal: `/platform/coach/today` — the pane described
  above.
- Mobile (`staff_dashboard_screen.dart`): a top card
  "Hoje em todos os clubes" that links to the same RPC
  result.

**Performance guardrails.** The RPC cap: 100 rows per
`kind`, ordered by priority. Cached client-side for
60s. A coach with 10 clubs isn't our scale target; 3–5
clubs is.

**Out of scope v1.**

- Drag-and-drop across groups (moving an athlete is
  already a different surface).
- Group-level KPI dashboards in one pane. Each group
  keeps its own; the aggregate is the work-queue,
  not the analytics.

### 6. iCal calendar feed (L23-20)

**What.** An endpoint `GET /api/athletes/{user_id}/calendar.ics`
that returns an iCalendar (RFC 5545) feed of the athlete's
scheduled workouts + registered race events. Athletes or
coaches subscribe to the URL from Google Calendar / Apple
Calendar / Outlook; the calendar auto-updates on their
phone and desktop.

**Why a feed, not a sync.** Two-way sync (OAuth to Google
Calendar, push when new workouts added) is a much bigger
project — OAuth flow, refresh tokens, quota, push
semantics. A **read-only iCal feed** covers 80% of the
need with 10% of the surface: athletes see workouts in
their calendar, coaches don't need to think about it.

**Auth model.** The URL is signed:

```
GET /api/athletes/{user_id}/calendar.ics?token={hmac}
```

`token` is a long-lived HMAC over `(user_id, created_at,
revoked_at?)` signed with a server secret. Stored in a
new table so we can revoke:

```sql
create table public.calendar_feed_tokens (
  token_hash text primary key,         -- hash of the HMAC for lookup
  user_id uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  last_accessed_at timestamptz
);

alter table public.calendar_feed_tokens enable row level security;
create policy self_feed_tokens on public.calendar_feed_tokens
  for all using (user_id = auth.uid())
  with check (user_id = auth.uid());
```

Athlete generates the URL once (Settings → "Calendário" →
"Gerar URL"), copies it into Google Calendar. A "revoke"
button regenerates; the old URL returns 410 Gone.

**Feed content.**

- `VEVENT` per `plan_workouts` row scheduled for the next
  180 days (cap — iCal clients don't handle infinite
  feeds well).
- `VEVENT` per `race_participations` (L21-16) for the
  athlete.
- `VEVENT` per group-level shared session (`group_sessions`)
  for the groups the athlete is in.

Each event has:

- `SUMMARY`: workout type + distance/duration
  ("🏃 Tempo 8k @ 4:20/km").
- `DTSTART`, `DTEND` (duration from plan).
- `LOCATION`: if set (track / venue).
- `DESCRIPTION`: the full plan detail (warm-up, intervals,
  cool-down) in plain text.
- `URL`: deep link back to the app
  (`omnirunner://workout/{id}`).
- `UID`: stable (`plan_workout:{id}@omnirunner.com`)
  so updates overwrite.

**Edge function / route.**

```
portal/src/app/api/athletes/[userId]/calendar.ics/route.ts
```

Validates token → loads workouts → emits iCal text/plain
with `Content-Type: text/calendar; charset=utf-8`.
`Cache-Control: private, max-age=900` (15-min refresh is
fine for a calendar feed; quicker = quota abuse).

**Library.** `ical-generator` npm (small, MIT, last
updated 2026). Avoids RFC 5545 hand-rolling.

**Out of scope v1.**

- Two-way sync (OAuth to Google Calendar). Separate
  finding if demand materializes.
- Coach-facing aggregate calendar (one feed for all of
  coach's athletes). Nice-to-have; deferrable.
- `VTIMEZONE` blocks — we emit UTC, clients convert.
- Push notifications when a subscribed calendar item
  changes. Calendar clients re-poll; that's the design.

## What we DO NOT do

- **White-label app for big assessorias**. That's a
  separate SKU that would warrant its own spec (likely
  L16-10 sandbox tier lineage).
- **Coach-to-coach video mentoring marketplace.** Out
  of scope; our Copilot addresses the same problem in
  self-serve mode at a fraction of the cost.
- **Prescription-rule editor**. Coaches use our
  plan-builder + Copilot; a visual rule editor would
  invite low-quality prescriptions.
- **Auto-renewing CREF validation** — we do not
  integrate with the CREF public registry (flaky,
  out-of-date). Manual review stays.

## Implementation phases

### Wave 4 — K12 additions (backend-heavy, data-available)

1. **W4-O** Multi-club aggregate dashboard (L23-19):
   new RPC + portal page + mobile card. Zero new tables;
   fastest to ship.
2. **W4-P** iCal calendar feed (L23-20): one route, one
   table, one mobile setting. Independent of all else
   in K12.
3. **W4-Q** PJ earnings dashboard (L23-16): read-only
   view + portal page + PDF renderer reused from L22-15.
   Ships after W4-P so it inherits the PDF infra.

### Wave 5 — K12 (heavier surfaces)

4. **W5-D** CRM funnel (L23-15): new table + public lead
   form + portal Kanban + attribution wiring (L15-01
   dependency). Ships when marketing-site is ready for
   the public lead form.
5. **W5-E** CREF validation (L23-17): schema + storage
   bucket + admin-queue portal + runbook. Ships when
   platform-admin team has staff to handle queue.
6. **W5-F** AI Copilot (L23-18): RAG corpus procurement
   (licensed content) + pgvector setup + Copilot UI +
   guardrails. Ships last due to content-license lead
   time and guardrail QA cost.

## See also

- `docs/product/ATHLETE_AMATEUR_BASELINE.md` (sibling
  persona, K11+K12)
- `docs/product/ATHLETE_PRO_BASELINE.md` (sibling
  persona, K11)
- `docs/audit/findings/L23-12-onboarding-do-atleta-pos-aceite.md`
  (coach-adjacent onboarding state)
- `docs/integrations/PARTNER_SAAS_TIERING.md` (L16-07..10)
- `docs/marketing/SEO_LANDING_STRATEGY.md` (L15-05, lead
  ingestion surface)
