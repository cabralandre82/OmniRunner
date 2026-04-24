# SEO Landing Pages Strategy

**Status:** Ratified (2026-04-21), implementation in Wave 3.
**Owner:** marketing + frontend
**Related:** L15-05, L15-01..04 (existing marketing wave 1
foundations), L14-01 (OpenAPI registry surface).

## Question being answered

> "Portal is logged-app-first; there is no `/running-with-
> coaches`, no `/marathon-training-plan`, no organic search
> traffic. The only Google entry points are `/login` and
> `/blog`. What's the SEO surface plan?"

## Decision

**MDX-based marketing route group** at `app/(marketing)/...`
with structured data, sitemap, and a small set of high-intent
landing pages launched in two waves.

### Folder layout

```
portal/src/app/(marketing)/
  ├── layout.tsx          # public navbar + footer, no auth gate
  ├── page.tsx            # marketing home (already exists, reuses brand kit)
  ├── [slug]/
  │   └── page.tsx        # MDX-driven landing page
  └── _content/
      ├── corrida-com-coach.mdx
      ├── plano-de-treino-maratona.mdx
      ├── como-criar-um-clube-de-corrida.mdx
      ├── ranking-corrida-amigos.mdx
      └── ...
```

`[slug]/page.tsx` reads the matching `_content/{slug}.mdx`,
renders it inside the shared marketing layout, and emits:

- `<Metadata>` with title, description, canonical URL,
  OpenGraph tags, Twitter card.
- `<JsonLd>` script with `@type: SportsActivity` (where
  applicable) and `@type: Article` for content pages.
- `prefetch` link to `/signup?utm_source=seo&utm_campaign={slug}`.

`generateStaticParams` enumerates `_content/*.mdx`, so every
landing page is statically generated at build time. Lighthouse
target: ≥ 95 for SEO + Performance.

### sitemap.xml

`app/sitemap.ts` (already exists) extended to enumerate
`_content/*.mdx` slugs in addition to the static routes.
`robots.txt` (already exists) explicitly allows
`/(marketing)/*` and disallows `/(portal)/*`.

### Wave-3 launch set (10 pages)

Picked by keyword research against pt-BR running queries
(volumes from Ubersuggest 2026-Q1):

| Slug                               | Target keyword                         | MoM searches |
|------------------------------------|----------------------------------------|--------------|
| `/plano-de-treino-maratona`        | "plano de treino maratona"             | 6.6k         |
| `/corrida-com-coach`               | "coach de corrida"                     | 4.1k         |
| `/como-criar-um-clube-de-corrida`  | "como criar clube de corrida"          | 1.9k         |
| `/ranking-corrida-amigos`          | "ranking corrida amigos"               | 1.2k         |
| `/aplicativo-corrida-coach`        | "aplicativo de corrida com coach"      | 880          |
| `/desafios-de-corrida`             | "desafios de corrida"                  | 720          |
| `/calculadora-pace-corrida`        | "calculadora de pace"                  | 9.9k (interactive widget) |
| `/treino-de-fortalecimento-corredor` | "fortalecimento para corredores"     | 2.4k         |
| `/como-acompanhar-atletas-coach`   | "como acompanhar atletas"              | 590          |
| `/o-que-sao-omnicoins`             | brand education                        | 0 (brand)    |

Each page is ~ 800-1500 words, written by a freelance copy +
reviewed by product, with 1 hero image (WebP, < 100 KB), 2-3
inline illustrations, and a CTA strip every ~ 400 words.

### Internal-link strategy

- Marketing home links to all 10 landing pages in a "Conteúdo"
  section.
- Each landing page links to 2-3 sibling pages in a "Veja
  também" widget.
- Blog posts (already at `/blog/*`) link to the closest
  landing page from inline copy.
- Login / signup pages do NOT link to marketing pages — the
  funnel goes the other way.

### Metrics + retire criteria

Tracked monthly in `docs/marketing/SEO_REPORT.md`:

- Sessions per landing page (from PostHog).
- Top 3 ranked queries per page (Search Console).
- Conversion `/signup` from landing page (UTM `seo`).

Pages with < 50 sessions/month after 90 days are merged or
retired. Pages with > 500 sessions/month get expansion content
+ video.

### Why MDX, not a CMS

Considered Sanity / Storyblok / Contentful. Rejected for v1:

1. Marketing copy churn is low (< 5 edits / month). MDX +
   GitHub PRs are perfectly adequate and benefit from code
   review.
2. CMS adds an external service with its own auth, RBAC, and
   bill (cheapest plans land at USD 100/month).
3. Migration to a headless CMS later is straightforward — MDX
   front-matter maps 1:1 to most CMS schemas.

When marketing needs > 5 edits/week or a non-engineer wants
direct edit access, we re-evaluate (Sanity is the front-runner).

## Implementation phasing

| Phase | Scope                                                   | When        |
|-------|---------------------------------------------------------|-------------|
| 0     | Spec ratified                                           | 2026-04-21  |
| 1     | `(marketing)/[slug]` route + sitemap extension + 3 pages from the list | 2026-Q3     |
| 2     | Remaining 7 pages + interactive pace calculator widget  | 2026-Q4     |
| 3     | Performance audit (Lighthouse ≥ 95) + Search Console verification | 2027-Q1 |

Closing this finding now means the **strategy is locked**;
the build is broken into clean Wave-3 deliverables.
