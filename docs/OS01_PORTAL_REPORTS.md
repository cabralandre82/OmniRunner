# OS-01 — Portal Reports: Presença

---

## Pages

| Page             | Path              | Purpose                               |
|------------------|-------------------|---------------------------------------|
| Attendance Report| `/attendance`     | Session list with attendance %         |
| Attendance Detail| `/attendance/[id]`| Per-session athlete list               |

---

## API

| Route                  | Method | Purpose                           |
|------------------------|--------|-----------------------------------|
| `/api/export/attendance`| GET    | CSV export of attendance data     |

---

## Features

- **Date filtering:** Filter sessions by date range
- **Summary cards:** Total sessions, attendance rate, attended count
- **Clickable rows:** Navigate to per-session detail
- **CSV export:** Download attendance data for reporting

---

## Sidebar Entry

Entry added: **"Presença"** for roles `admin_master`, `coach`, `assistant`.

Path: `/attendance`
