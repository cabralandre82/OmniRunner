# Email Templates Specification

## Overview

This document specifies the HTML email templates used by the platform for transactional emails.
Templates are rendered server-side before sending via the configured email provider (e.g. Resend, SendGrid).

---

## 1. Coaching Group Invitation

**Trigger:** Staff invites a new athlete to a coaching group via the Portal or App.

**Subject:** `Você foi convidado para {{group_name}}`

**Template variables:**

| Variable | Type | Description |
|---|---|---|
| `recipient_name` | string | Display name of invited user |
| `group_name` | string | Name of the coaching group |
| `coach_name` | string | Name of the staff member who sent the invite |
| `invite_link` | string | Deep link to accept the invitation |
| `expire_date` | string | Human-readable expiry date (e.g. "10 de março de 2026") |

**HTML structure:**

```html
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Convite para {{group_name}}</title>
  <style>
    body { margin: 0; padding: 0; background: #f4f4f5; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; }
    .container { max-width: 600px; margin: 0 auto; background: #ffffff; border-radius: 12px; overflow: hidden; }
    .header { background: #1a1a2e; padding: 32px 24px; text-align: center; }
    .header img { height: 40px; }
    .header h1 { color: #ffffff; font-size: 20px; margin: 16px 0 0; }
    .body { padding: 32px 24px; }
    .body p { color: #3f3f46; font-size: 16px; line-height: 1.6; margin: 0 0 16px; }
    .cta { display: inline-block; background: #6366f1; color: #ffffff; text-decoration: none; padding: 14px 32px; border-radius: 8px; font-weight: 600; font-size: 16px; margin: 8px 0 24px; }
    .footer { padding: 24px; text-align: center; color: #a1a1aa; font-size: 13px; border-top: 1px solid #e4e4e7; }
    .expire-note { background: #fef3c7; border-radius: 8px; padding: 12px 16px; color: #92400e; font-size: 14px; margin: 16px 0; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <!-- Logo placeholder -->
      <h1>Você foi convidado!</h1>
    </div>
    <div class="body">
      <p>Olá <strong>{{recipient_name}}</strong>,</p>
      <p><strong>{{coach_name}}</strong> convidou você para fazer parte da assessoria <strong>{{group_name}}</strong>.</p>
      <p>Clique no botão abaixo para aceitar o convite e começar a treinar com o grupo:</p>
      <p style="text-align: center;">
        <a href="{{invite_link}}" class="cta">Aceitar Convite</a>
      </p>
      <div class="expire-note">
        ⏳ Este convite expira em <strong>{{expire_date}}</strong>.
      </div>
      <p style="font-size: 14px; color: #71717a;">
        Se você não esperava este convite, pode ignorar este email.
      </p>
    </div>
    <div class="footer">
      <p>OmniRunner — Sua plataforma de corrida</p>
      <p>Este email foi enviado automaticamente. Não responda.</p>
    </div>
  </div>
</body>
</html>
```

---

## 2. Championship Invitation

**Trigger:** Host assessoria invites another assessoria to a championship.

**Subject:** `{{group_name}} convidou sua assessoria para o campeonato {{championship_name}}`

**Template variables:**

| Variable | Type | Description |
|---|---|---|
| `staff_name` | string | Name of the staff member receiving the invite |
| `host_group_name` | string | Name of the host assessoria |
| `championship_name` | string | Name of the championship |
| `invite_link` | string | Deep link to accept/decline |
| `start_date` | string | Championship start date |

---

## 3. Weekly Training Summary

**Trigger:** Cron job runs every Monday at 08:00 BRT.

**Subject:** `Resumo semanal — {{group_name}}`

**Template variables:**

| Variable | Type | Description |
|---|---|---|
| `athlete_name` | string | |
| `group_name` | string | |
| `sessions_completed` | number | Sessions completed this week |
| `sessions_total` | number | Sessions assigned |
| `total_km` | string | Total distance formatted |
| `streak_days` | number | Current streak |
| `dashboard_link` | string | Deep link to dashboard |

---

## 4. Payment Confirmation

**Trigger:** After successful subscription payment or coin purchase.

**Subject:** `Pagamento confirmado — R$ {{amount}}`

**Template variables:**

| Variable | Type | Description |
|---|---|---|
| `user_name` | string | |
| `amount` | string | Formatted BRL amount |
| `description` | string | Purchase description |
| `receipt_link` | string | Link to receipt/invoice |

---

## Design Guidelines

- **Max width:** 600px centered
- **Font stack:** system fonts (`-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif`)
- **Primary color:** `#6366f1` (Indigo-500)
- **Dark header:** `#1a1a2e`
- **Border radius:** 8-12px
- **CTA buttons:** minimum 44px height for touch targets
- **Always include:** unsubscribe link in footer (for marketing emails), plain-text fallback
- **Language:** Brazilian Portuguese (pt-BR)
- **Responsive:** single-column layout that works on mobile clients
