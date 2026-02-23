# QA PHASE 34 — End-to-End Billing Audit

> Sprint: 34.99.0
> Date: 2026-02-21
> Status: **APROVADO**

---

## 1. create-checkout-session (Edge Function)

| # | Check | Result |
|---|-------|:------:|
| 1.1 | POST only, rejects other methods with 405 | PASS |
| 1.2 | Requires valid JWT (requireUser) | PASS |
| 1.3 | Rate limited (10 req/60s per user) | PASS |
| 1.4 | Requires `product_id` + `group_id` in body | PASS |
| 1.5 | Verifies caller is `admin_master` for group (coaching_members check) | PASS |
| 1.6 | Rejects inactive products (`is_active=false`) | PASS |
| 1.7 | Rejects non-existent products with 404 | PASS |
| 1.8 | Creates `billing_purchases` row with `status=pending` | PASS |
| 1.9 | Logs `billing_events` with `event_type=created` | PASS |
| 1.10 | Creates Stripe Checkout Session with correct `line_items` | PASS |
| 1.11 | Sets `payment_method_types` to `[card, boleto, pix]` for BRL | PASS |
| 1.12 | Sets `metadata.purchase_id` on Stripe session | PASS |
| 1.13 | Session expires in 30 min (`SESSION_TTL_SECONDS = 1800`) | PASS |
| 1.14 | Updates `billing_purchases.payment_reference` with `session.id` | PASS |
| 1.15 | Returns `{purchase_id, checkout_url, session_id}` | PASS |
| 1.16 | Emits `billing_checkout_started` analytics event | PASS |
| 1.17 | `success_url` points to `/billing/success` | PASS |
| 1.18 | `cancel_url` points to `/billing/cancelled` | PASS |
| 1.19 | Observability: logRequest/logError with request_id, fn, user_id, duration_ms | PASS |
| 1.20 | CORS handled via handleCors | PASS |

---

## 2. webhook-payments (Edge Function) — paid -> inventory increments

| # | Check | Result |
|---|-------|:------:|
| 2.1 | Validates Stripe signature (constructEventAsync + SubtleCryptoProvider) | PASS |
| 2.2 | Rejects missing/invalid signature with 400 | PASS |
| 2.3 | Uses service-role DB client (no JWT needed) | PASS |
| 2.4 | L1 dedup: queries `billing_events.stripe_event_id` before processing | PASS |
| 2.5 | L1 dedup: `stripe_event_id` UNIQUE partial index prevents duplicate inserts | PASS |
| 2.6 | L2 dedup: conditional UPDATE `WHERE status='pending'` prevents re-transition | PASS |
| 2.7 | L3 dedup: `fn_fulfill_purchase` uses `FOR UPDATE` lock + status check | PASS |
| 2.8 | `checkout.session.completed` (payment_status=paid) → handlePaymentConfirmed | PASS |
| 2.9 | `checkout.session.async_payment_succeeded` → handlePaymentConfirmed | PASS |
| 2.10 | `checkout.session.async_payment_failed` → handleSessionCancelled | PASS |
| 2.11 | `checkout.session.expired` → handleSessionCancelled | PASS |
| 2.12 | handlePaymentConfirmed: resolves payment_method from PaymentIntent | PASS |
| 2.13 | handlePaymentConfirmed: resolves receipt_url → billing_purchases.invoice_url | PASS |
| 2.14 | handlePaymentConfirmed: transitions purchase pending → paid | PASS |
| 2.15 | handlePaymentConfirmed: inserts `billing_events` (payment_confirmed) | PASS |
| 2.16 | handlePaymentConfirmed: calls `fn_fulfill_purchase` RPC | PASS |
| 2.17 | fn_fulfill_purchase: atomic paid → fulfilled + fn_credit_institution | PASS |
| 2.18 | fn_credit_institution: inserts `institution_credit_purchases` audit row | PASS |
| 2.19 | fn_credit_institution: increments `coaching_token_inventory.available_tokens` | PASS |
| 2.20 | fn_credit_institution: increments `coaching_token_inventory.lifetime_issued` | PASS |
| 2.21 | fn_fulfill_purchase: links `fulfilled_credit_id` back to purchase | PASS |
| 2.22 | handleSessionCancelled: transitions purchase pending → cancelled | PASS |
| 2.23 | handleSessionCancelled: only cancels if still pending (conditional update) | PASS |
| 2.24 | charge.refunded: inserts billing_event(refunded) | PASS |
| 2.25 | charge.dispute.created: inserts billing_event(note_added) | PASS |
| 2.26 | Emits `billing_payment_confirmed` analytics event | PASS |
| 2.27 | Emits `billing_payment_failed` / `billing_checkout_expired` analytics | PASS |
| 2.28 | Returns 200 for all processed events (prevents Stripe retries) | PASS |
| 2.29 | Idempotent: duplicate event returns `{already_processed: true}` | PASS |
| 2.30 | Fulfillment failure logged but doesn't block webhook response | PASS |

---

## 3. Portal reflects balance

| # | Check | Result |
|---|-------|:------:|
| 3.1 | Dashboard: shows `coaching_token_inventory.available_tokens` | PASS |
| 3.2 | Credits page: shows current balance from `coaching_token_inventory` | PASS |
| 3.3 | Credits page: lists active `billing_products` (sort_order ASC) | PASS |
| 3.4 | Credits page: shows price in BRL + cost per OmniCoin | PASS |
| 3.5 | Credits page: BuyButton → POST /api/checkout → redirect to Stripe | PASS |
| 3.6 | Billing page: lists `billing_purchases` with status badges | PASS |
| 3.7 | Billing page: shows receipt link (invoice_url) when available | PASS |
| 3.8 | Billing page: summary cards (total purchases, total paid, credits) | PASS |
| 3.9 | /billing/success page renders after successful checkout | PASS |
| 3.10 | /billing/cancelled page renders after cancelled checkout | PASS |
| 3.11 | API route /api/checkout: validates session + group_id cookie | PASS |
| 3.12 | API route /api/checkout: forwards JWT to Edge Function | PASS |
| 3.13 | Credits purchase restricted to admin_master | PASS |
| 3.14 | Non-admin staff see informational message on credits page | PASS |
| 3.15 | Settings/Equipe: list staff, invite by email, remove with guards | PASS |
| 3.16 | Middleware: blocks athletes, enforces staff roles | PASS |
| 3.17 | Analytics: billing_credits_viewed, billing_purchases_viewed tracked | PASS |
| 3.18 | Analytics: billing_checkout_returned tracked (success/cancelled) | PASS |
| 3.19 | Portal build: tsc clean, 20/20 routes | PASS |

---

## 4. App reflects balance

| # | Check | Result |
|---|-------|:------:|
| 4.1 | staff_credits_screen: reads `coaching_token_inventory.available_tokens` | PASS |
| 4.2 | staff_credits_screen: shows OmniCoins balance (available/issued/burned) | PASS |
| 4.3 | staff_credits_screen: reads `institution_credit_purchases` history | PASS |
| 4.4 | staff_credits_screen: no monetary values in history (credits only) | PASS |
| 4.5 | staff_dashboard: reads coaching_token_inventory for wallet badge | PASS |
| 4.6 | RLS: coaching_token_inventory readable by staff of the group | PASS |
| 4.7 | RLS: institution_credit_purchases readable by admin_master only | PASS |
| 4.8 | Portal button on staff dashboard opens external browser | PASS |
| 4.9 | Portal CTA on credits screen opens external browser | PASS |
| 4.10 | LaunchMode.externalApplication — never in-app WebView | PASS |

---

## 5. No price appears in app (loja-safe audit)

| # | Check | Result |
|---|-------|:------:|
| 5.1 | grep `price_cents` in app lib/ → 0 matches | PASS |
| 5.2 | grep `billing_products` in app lib/ → 0 matches | PASS |
| 5.3 | grep `billing_purchases` in app lib/ → 0 matches | PASS |
| 5.4 | grep `R$` in app lib/ → 0 matches | PASS |
| 5.5 | staff_credits_screen: comment confirms "No monetary values, no purchase flow" | PASS |
| 5.6 | institution_credit_purchases: schema comment "No monetary values stored" | PASS |
| 5.7 | institution_credit_purchases: no price_cents column | PASS |
| 5.8 | wallet_screen: "cosmeticPurchase" = OmniCoin virtual currency, not real money | PASS |
| 5.9 | RLS: billing_products restricted to staff roles only (athletes can't read) | PASS |
| 5.10 | RLS: billing_purchases restricted to admin_master only | PASS |
| 5.11 | AppConfig.portalUrl: comment says "Never load checkout inside the app" | PASS |
| 5.12 | GAMIFICATION_POLICY §5: OmniCoins are cosmetic, never sold in app | PASS |
| 5.13 | Apple 3.1.1 compliance: no IAP for Coins, no payment UI in app | PASS |
| 5.14 | Google Play Billing compliance: no real-money transactions in app | PASS |
| 5.15 | flutter analyze: 0 errors in modified files | PASS |

---

## Summary

| Area | Checks | Passed | Failed |
|------|:------:|:------:|:------:|
| create-checkout-session | 20 | 20 | 0 |
| webhook → inventory | 30 | 30 | 0 |
| Portal reflects balance | 19 | 19 | 0 |
| App reflects balance | 10 | 10 | 0 |
| No price in app | 15 | 15 | 0 |
| **TOTAL** | **94** | **94** | **0** |

**Verdict: APROVADO — pronto para produção**
