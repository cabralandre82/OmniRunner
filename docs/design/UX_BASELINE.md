# UX Baseline — Portal & Mobile

**Status:** Ratified (2026-04-21), implementation in Wave 3.
**Owner:** product + design + frontend
**Related:** L07-07 (icon fallback), L07-08 (dark mode),
L07-10 (empty states), L07-11 (loading states), L07-12 (copy
financeiro), L07-13 (destructive confirm), L05-11 (already
shipped fat-finger guard).

## Scope

This doc consolidates the cross-cutting UX baseline that
several Wave-2 medium findings asked for as separate items.
Treating them as one ratified spec lets us close 6 findings
together and lets the team build them as one cohesive Wave-3
PR series instead of 6 disjoint PRs.

## L07-07 — Image / icon fallback (mobile offline)

- All `Image.network` callers MUST be replaced with
  `cached_network_image` (already a transitive dep of
  `flutter_secure_storage` ecosystem; we add it explicitly to
  `pubspec.yaml`).
- Avatar shape: 1st pass `placeholder` is the user / group
  initials inside a colored circle (deterministic colour
  derived from `sha1(name)[:6]`).
- Error fallback ≠ placeholder: when the network image
  resolves to a 4xx, we keep the initials placeholder forever
  (no infinite retry) but render a small "!" badge so the user
  can long-press → "Try again" if they care.
- Cache eviction: 30-day TTL, 100 MB on-disk cap (per Drift
  database boundary).

## L07-08 — Dark mode in the portal

The Flutter app already has dark theme tokens
(`omni_runner/lib/core/theme/dark.dart`). The portal does not.

Decision: adopt **`next-themes`** + **Tailwind `dark:`
variants** (already configured in `tailwind.config.ts` —
`darkMode: 'class'` is the toggle). Implementation is mostly
mechanical: swap raw color tokens for the semantic ones
already present in `tailwind.config.ts` (e.g. `bg-white` →
`bg-surface`, `text-gray-900` → `text-content`).

Initial dark token mapping:

```
--color-bg              gray-50    →   gray-950
--color-surface         white      →   gray-900
--color-border          gray-200   →   gray-800
--color-content         gray-900   →   gray-100
--color-content-muted   gray-500   →   gray-400
--color-brand           indigo-600 →   indigo-400
--color-success         emerald-600→   emerald-400
--color-error           red-600    →   red-400
```

The system-preference respect path (`prefers-color-scheme`) is
the default; users can override in Settings. Persisted via
cookie (`portal_theme=dark`) so RSCs render correctly without
a flash.

## L07-10 — Empty states

A single canonical component:

```tsx
<EmptyState
  illustration={<NoChampionships />}
  title="Você ainda não tem desafios ativos"
  description="Crie um novo ou aceite um convite do seu coach."
  primaryAction={{ label: "Criar desafio", onClick: ... }}
  secondaryAction={{ label: "Aceitar convite", onClick: ... }}
/>
```

Every list-style screen MUST use this component for its empty
case. Inventory of screens that need it:
`/athletes`, `/championships`, `/swap`, `/distributions`,
`/credits`, `/coaching/sessions`, `/coaching/templates`,
mobile counterparts. The `illustration` prop lets each screen
customize the visual; the rest is shared.

## L07-11 — Loading states

- Lists → `<SkeletonCard rows={N} />` with `N = expected
  page_size`. NEVER mix spinner + skeleton in the same screen.
- Single-record screens (e.g. `/championships/[id]`) →
  `<SkeletonDetail />` with the same layout grid as the
  loaded version (eliminates layout shift / CLS).
- API call buttons → spinner inside the button text + button
  becomes `disabled`. NEVER overlay a full-screen spinner for
  a single mutation.
- Mobile: identical pattern via `shimmer` package +
  `SkeletonCard` widget that mirrors the portal API.

## L07-12 — Financial copy / glossary

Today the UI mixes "Coins", "Badges", "Créditos",
"Inventário". Decision:

| Term shown to user | Definition                                                | Use anywhere it appears |
|--------------------|-----------------------------------------------------------|-------------------------|
| **OmniCoins** (or **moedas**) | Saldo monetário do atleta. Usado para sacar, swap, gastar em prêmios. | Wallet, distribute UI, withdrawal, swap |
| **Badges** | Conquistas não-monetárias. Decorativas. Não viram dinheiro. | Profile, championships completed |
| **Créditos** | Saldo PJ do clube em moeda fiduciária (BRL/USD), usado para emitir OmniCoins ou pagar fees. | Billing, custody, clearing |
| **Inventário** | (DEPRECATED) Substituir por "OmniCoins disponíveis para emissão" no painel admin. | n/a |

Each first occurrence per screen ships a tooltip
(`<TermDef term="OmniCoins" />`) linking to a glossary page
`/help/glossary`. Glossary content is a single MDX file in
both pt-BR and en.

Migration plan: rename "Inventário" → "OmniCoins disponíveis"
in admin coaching screens; keep the data model name
(`coaching_groups.token_inventory`) untouched. UI labels are
the only thing that changes.

## L07-13 — Destructive action confirmation

Every irreversible action MUST go through `<DestructiveConfirm>`:

```tsx
<DestructiveConfirm
  title="Excluir conta"
  consequence="Esta ação é irreversível. Seus dados serão apagados em até 30 dias e suas OmniCoins serão devolvidas ao grupo."
  typeToConfirm="EXCLUIR"
  confirmLabel="Excluir conta"
  onConfirm={...}
/>
```

The "type-to-confirm" pattern (à la GitHub) is mandatory for:

- Account deletion (already enforced by L04-01 spec).
- Championship cancellation when participants > 0.
- Swap cancellation when status = `accepted`.
- Coach removing a paying athlete from the group.
- Platform admin force-disconnecting a custody account.

For lower-stakes destructive actions (delete a draft, undo a
single message), a simple `<Confirm>` modal suffices.

## Implementation phasing

These six items are scoped to **one Wave-3 PR series**, owned
by the design+frontend pair, in this order:

1. Token migration (`tailwind.config.ts` semantic tokens) — 1 day.
2. Dark mode toggle + cookie + RSC sync — 2 days.
3. `<EmptyState>`, `<SkeletonCard>`, `<SkeletonDetail>`,
   `<DestructiveConfirm>`, `<TermDef>` components + Storybook
   page — 3 days.
4. Replace existing screens (search-replace driven by ESLint
   rule `no-raw-color-tokens` and `no-bare-empty-string`) —
   1 week.
5. Mobile mirror (skeleton + EmptyState + DestructiveConfirm
   widgets) — 1 week.

Total estimate: ~3 weeks of one designer-frontend pair.
Closing the 6 findings now means the **direction is locked**;
the implementation lives in the Wave-3 sprint plan.
