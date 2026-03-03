# OS-01 — QR Check-in Specification

---

## Flow Diagram

```
1. Athlete opens "Meus Treinos", selects session
2. App calls fn_issue_checkin_token(session_id, 120) → gets nonce + expires_at
3. App builds JSON payload: {sid, uid, gid, non, exp} → base64url encode → QrImageView
4. Staff scans QR with MobileScanner
5. App decodes base64url → validates expiry locally
6. App calls fn_mark_attendance(session_id, athlete_user_id, nonce)
7. RPC validates: staff role, session exists, not cancelled, athlete in group
8. INSERT with ON CONFLICT DO NOTHING → returns inserted/already_present
```

---

## Payload Format

```json
{"sid":"uuid","uid":"uuid","gid":"uuid","non":"hex48","exp":1709503200000}
```

| Field | Type   | Description                                   |
|-------|--------|-----------------------------------------------|
| sid   | uuid   | Session ID                                    |
| uid   | uuid   | Athlete user ID                               |
| gid   | uuid   | Group ID                                      |
| non   | hex48  | Nonce (24 random bytes hex-encoded)           |
| exp   | int64  | Expiry timestamp (ms since epoch)             |

Encoded as JSON → UTF-8 → base64url for display in the QR code.

---

## Security Measures

- **TTL 120s default:** `fn_issue_checkin_token(p_session_id, 120)` limits QR validity.
- **Nonce (MVP: TTL-only):** Random value per token for traceability; stored in payload. In MVP, the nonce is NOT validated server-side — anti-replay relies on TTL (120s) + DB idempotency (`ON CONFLICT DO NOTHING`). Full nonce validation (single-use via lookup table or HMAC signature) is deferred to v2.
- **Server-side validation:** `fn_mark_attendance` checks:
  - Authenticated user
  - Staff role (admin_master, coach, assistant) in the group
  - Session exists and is not cancelled
  - Athlete is a member of the group

---

## Error Codes

| Code                 | Meaning                                      |
|----------------------|----------------------------------------------|
| NOT_AUTHENTICATED    | Caller not logged in                         |
| SESSION_NOT_FOUND    | Session ID invalid                            |
| SESSION_CANCELLED    | Session status is cancelled                   |
| NOT_STAFF            | Caller not staff of the group                |
| ATHLETE_NOT_IN_GROUP | Athlete not a member of the group            |
| NOT_IN_GROUP         | Caller (athlete) not in group (token issue)  |

---

## Idempotency

- **UNIQUE(session_id, athlete_user_id)** on `coaching_training_attendance`.
- **ON CONFLICT DO NOTHING** on insert.
- Re-scanning the same QR returns `already_present` without error.
