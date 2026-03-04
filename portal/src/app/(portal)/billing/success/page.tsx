import Link from "next/link";
import { trackBillingEvent } from "@/lib/analytics";

export default async function BillingSuccessPage() {
  await trackBillingEvent("billing_checkout_returned", { outcome: "success" });
  return (
    <div className="flex min-h-[60vh] items-center justify-center">
      <div className="max-w-sm space-y-4 rounded-xl bg-surface p-8 text-center shadow-lg">
        <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-success-soft">
          <span className="text-xl text-success">✓</span>
        </div>
        <h1 className="text-xl font-bold text-content-primary">
          Pagamento Confirmado
        </h1>
        <p className="text-sm text-content-secondary">
          Seus créditos serão alocados automaticamente em instantes.
          Você pode acompanhar o status na tela de créditos.
        </p>
        <div className="flex flex-col gap-2 pt-2">
          <Link
            href="/credits"
            className="rounded-lg bg-brand px-4 py-2 text-sm font-medium text-white hover:brightness-110"
          >
            Ver Créditos
          </Link>
          <Link
            href="/dashboard"
            className="rounded-lg bg-surface-elevated px-4 py-2 text-sm font-medium text-content-secondary hover:bg-bg-secondary"
          >
            Ir ao Dashboard
          </Link>
        </div>
      </div>
    </div>
  );
}
