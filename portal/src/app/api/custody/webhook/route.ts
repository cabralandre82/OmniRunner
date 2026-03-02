import { NextRequest, NextResponse } from "next/server";
import { verifyStripeSignature, verifyHmacSignature, WebhookError } from "@/lib/webhook";
import { confirmDepositByReference } from "@/lib/custody";
import { auditLog } from "@/lib/audit";
import { logger } from "@/lib/logger";
import { metrics } from "@/lib/metrics";

const STRIPE_WEBHOOK_SECRET = process.env.STRIPE_CUSTODY_WEBHOOK_SECRET ?? "";
const MP_WEBHOOK_SECRET = process.env.MP_CUSTODY_WEBHOOK_SECRET ?? "";

/**
 * POST /api/custody/webhook
 *
 * Receives payment gateway webhooks to confirm custody deposits.
 * Idempotent: re-processing the same event is safe.
 */
export async function POST(req: NextRequest) {
  const rawBody = await req.text();
  const gateway = req.headers.get("x-gateway") ?? detectGateway(req);

  try {
    if (gateway === "stripe") {
      const sig = req.headers.get("stripe-signature");
      if (!sig || !STRIPE_WEBHOOK_SECRET) {
        return NextResponse.json({ error: "Missing signature" }, { status: 400 });
      }
      verifyStripeSignature({
        payload: rawBody,
        signature: sig,
        secret: STRIPE_WEBHOOK_SECRET,
      });
    } else if (gateway === "mercadopago") {
      const sig = req.headers.get("x-signature");
      if (!sig || !MP_WEBHOOK_SECRET) {
        return NextResponse.json({ error: "Missing signature" }, { status: 400 });
      }
      verifyHmacSignature({
        payload: rawBody,
        signature: sig,
        secret: MP_WEBHOOK_SECRET,
      });
    } else {
      return NextResponse.json({ error: "Unknown gateway" }, { status: 400 });
    }
  } catch (err) {
    if (err instanceof WebhookError) {
      logger.warn("Webhook signature verification failed", { gateway, error: err.message });
      return NextResponse.json({ error: err.message }, { status: 401 });
    }
    throw err;
  }

  const event = JSON.parse(rawBody);
  const paymentReference = extractPaymentReference(event, gateway);

  if (!paymentReference) {
    return NextResponse.json({ error: "No payment reference found" }, { status: 400 });
  }

  try {
    const result = await confirmDepositByReference(paymentReference);
    metrics.increment("custody.webhook.confirmed", { gateway });

    if (!result.alreadyConfirmed) {
      await auditLog({
        actorId: "system",
        action: "custody.deposit.webhook_confirmed",
        targetId: result.depositId,
        metadata: { gateway, payment_reference: paymentReference },
      });
    }

    return NextResponse.json({
      ok: true,
      deposit_id: result.depositId,
      already_confirmed: result.alreadyConfirmed,
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : "Confirmation failed";
    logger.error("Webhook deposit confirmation failed", err, { gateway, paymentReference });
    metrics.increment("custody.webhook.error", { gateway });
    return NextResponse.json({ error: msg }, { status: 422 });
  }
}

function detectGateway(req: NextRequest): string {
  if (req.headers.get("stripe-signature")) return "stripe";
  if (req.headers.get("x-signature")) return "mercadopago";
  return "unknown";
}

function extractPaymentReference(event: Record<string, unknown>, gateway: string): string | null {
  if (gateway === "stripe") {
    const obj = (event as { data?: { object?: { id?: string } } })?.data?.object;
    return obj?.id ?? null;
  }
  if (gateway === "mercadopago") {
    return (event as { data?: { id?: string } })?.data?.id ?? null;
  }
  return null;
}
