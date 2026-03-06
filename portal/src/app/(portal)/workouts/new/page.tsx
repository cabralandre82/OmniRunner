import { cookies } from "next/headers";
import Link from "next/link";
import { NoGroupSelected } from "@/components/no-group-selected";
import { TemplateBuilder } from "../template-builder";

export const dynamic = "force-dynamic";

export default function NewWorkoutPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return <NoGroupSelected />;

  return (
    <div className="space-y-4">
      <Link
        href="/workouts"
        className="text-sm text-content-secondary hover:text-primary"
      >
        ← Voltar aos templates
      </Link>
      <TemplateBuilder />
    </div>
  );
}
