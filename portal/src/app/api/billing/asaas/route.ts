import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";

async function forwardToEdgeFunction(
  accessToken: string,
  body: Record<string, unknown>,
): Promise<Response> {
  const url = `${process.env.NEXT_PUBLIC_SUPABASE_URL!}/functions/v1/asaas-sync`;
  return fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

export async function POST(request: NextRequest) {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) {
    return NextResponse.json({ error: "No group selected" }, { status: 400 });
  }

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const action = body.action as string;
  if (!action) {
    return NextResponse.json({ error: "action required" }, { status: 400 });
  }

  const db = createServiceClient();

  const { data: membership } = await db
    .from("coaching_members")
    .select("role")
    .eq("group_id", groupId)
    .eq("user_id", user.id)
    .maybeSingle();

  if (!membership || !["admin_master", "coach"].includes(membership.role)) {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const { data: { session } } = await supabase.auth.getSession();
  const accessToken = session?.access_token;

  switch (action) {
    case "test_connection": {
      if (!accessToken) {
        return NextResponse.json({ error: "Session expired" }, { status: 401 });
      }
      const res = await forwardToEdgeFunction(accessToken, {
        action,
        api_key: body.api_key,
        environment: body.environment,
        group_id: groupId,
      });
      const data = await res.json().catch(() => ({}));
      return NextResponse.json(data, { status: res.status });
    }

    case "save_config": {
      const apiKey = body.api_key as string;
      const environment = (body.environment as string) ?? "sandbox";
      if (!apiKey) {
        return NextResponse.json({ error: "api_key required" }, { status: 400 });
      }
      const { error } = await db
        .from("payment_provider_config")
        .upsert(
          {
            group_id: groupId,
            provider: "asaas",
            api_key: apiKey,
            environment: environment,
            is_active: false,
            updated_at: new Date().toISOString(),
          },
          {
            onConflict: "group_id,provider",
            ignoreDuplicates: false,
          },
        );
      if (error) {
        return NextResponse.json({ error: error.message }, { status: 500 });
      }
      return NextResponse.json({ ok: true });
    }

    case "setup_webhook": {
      if (!accessToken) {
        return NextResponse.json({ error: "Session expired" }, { status: 401 });
      }
      const res = await forwardToEdgeFunction(accessToken, {
        action,
        group_id: groupId,
      });
      const data = await res.json().catch(() => ({}));
      return NextResponse.json(data, { status: res.status });
    }

    case "create_customer": {
      if (!accessToken) {
        return NextResponse.json({ error: "Session expired" }, { status: 401 });
      }
      const res = await forwardToEdgeFunction(accessToken, {
        action,
        group_id: groupId,
        athlete_user_id: body.athlete_user_id,
        name: body.name,
        cpf: body.cpf,
        email: body.email,
      });
      const data = await res.json().catch(() => ({}));
      return NextResponse.json(data, { status: res.status });
    }

    case "create_subscription": {
      if (!accessToken) {
        return NextResponse.json({ error: "Session expired" }, { status: 401 });
      }
      const res = await forwardToEdgeFunction(accessToken, {
        action,
        group_id: groupId,
        subscription_id: body.subscription_id,
        asaas_customer_id: body.asaas_customer_id,
        value: body.value,
        cycle: body.cycle,
        next_due_date: body.next_due_date,
        description: body.description,
        billing_type: body.billing_type,
      });
      const data = await res.json().catch(() => ({}));
      return NextResponse.json(data, { status: res.status });
    }

    case "cancel_subscription": {
      if (!accessToken) {
        return NextResponse.json({ error: "Session expired" }, { status: 401 });
      }
      const res = await forwardToEdgeFunction(accessToken, {
        action,
        group_id: groupId,
        subscription_id: body.subscription_id,
      });
      const data = await res.json().catch(() => ({}));
      return NextResponse.json(data, { status: res.status });
    }

    case "disconnect": {
      const { error } = await db
        .from("payment_provider_config")
        .update({
          is_active: false,
          updated_at: new Date().toISOString(),
        })
        .eq("group_id", groupId)
        .eq("provider", "asaas");
      if (error) {
        return NextResponse.json({ error: error.message }, { status: 500 });
      }
      return NextResponse.json({ ok: true });
    }

    default:
      return NextResponse.json({ error: `Unknown action: ${action}` }, { status: 400 });
  }
}
