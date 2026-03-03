# OS-02 — Portal CRM: Relatórios e Gestão

---

## Pages

| Page | Path | Purpose |
|------|------|---------|
| CRM Table | `/crm` | Filterable athlete table with export |
| At-Risk Panel | `/crm/at-risk` | Athletes with active coaching_alerts |
| Athlete Detail | `/crm/[userId]` | Notes, tags, status, attendance, alerts |

**File paths (planned):**
- `portal/src/app/(portal)/crm/page.tsx` — CRM table
- `portal/src/app/(portal)/crm/at-risk/page.tsx` — At-risk panel
- `portal/src/app/(portal)/crm/[userId]/page.tsx` — Athlete detail

---

## API

| Route | Method | Purpose |
|-------|--------|---------|
| `/api/export/crm` | GET | CSV export of CRM data |

**File path (planned):** `portal/src/app/api/export/crm/route.ts`

---

## Sidebar

Entry **"CRM Atletas"** for roles: `admin_master`, `coach`, `assistant`.

Implementation: add to `NAV_ITEMS` in `portal/src/components/sidebar.tsx` with `href: "/crm"`.

---

## Integrations

### PASSO 05
Consumes `coaching_alerts` for at-risk indicators (e.g. low attendance, rule violations).

### OS-01
Shows attendance data from `coaching_training_attendance` and `coaching_training_sessions`.
