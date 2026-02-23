import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { cookies } from "next/headers";

export async function POST() {
  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();

  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) {
    return NextResponse.json({ error: "No group selected" }, { status: 400 });
  }

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;
  const res = await fetch(
    `${supabaseUrl}/functions/v1/create-portal-session`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${session.access_token}`,
      },
      body: JSON.stringify({ group_id: groupId }),
    },
  );

  const data = await res.json();

  if (!res.ok || !data.ok) {
    return NextResponse.json(
      { error: data.error?.message ?? "Failed to open billing portal" },
      { status: res.status },
    );
  }

  return NextResponse.json({ portal_url: data.portal_url });
}
