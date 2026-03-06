"use client";

import { useState, useMemo } from "react";
import { useRouter } from "next/navigation";

interface Athlete {
  member_id: string;
  user_id: string;
  display_name: string;
  email: string | null;
  cpf: string | null;
  current_plan: string | null;
  current_status: string | null;
  next_due_date: string | null;
}

interface Plan {
  id: string;
  name: string;
  monthly_price: number;
  billing_cycle: string;
}

const STATUS_BADGE: Record<string, { label: string; cls: string }> = {
  active: { label: "Ativo", cls: "bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-300" },
  late: { label: "Inadimplente", cls: "bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-300" },
  paused: { label: "Pausado", cls: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900/30 dark:text-yellow-300" },
  cancelled: { label: "Cancelado", cls: "bg-gray-100 text-gray-600 dark:bg-gray-700/30 dark:text-gray-400" },
};

export function AssignSubscriptionClient({
  athletes,
  plans,
  asaasActive = false,
}: {
  athletes: Athlete[];
  plans: Plan[];
  asaasActive?: boolean;
}) {
  const router = useRouter();

  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState("all");

  const [planId, setPlanId] = useState("");
  const [startDate, setStartDate] = useState(
    () => new Date().toISOString().split("T")[0],
  );
  const [dueDate, setDueDate] = useState(() => {
    const d = new Date();
    d.setMonth(d.getMonth() + 1);
    return d.toISOString().split("T")[0];
  });

  const [loading, setLoading] = useState(false);
  const [autoBilling, setAutoBilling] = useState(false);
  const [cpfInputs, setCpfInputs] = useState<Record<string, string>>({});
  const [billingProgress, setBillingProgress] = useState("");
  const [result, setResult] = useState<{
    ok: boolean;
    success: number;
    total: number;
  } | null>(null);

  const selectedCount = selectedIds.size;
  const hasStep1 = selectedCount > 0;
  const hasStep2 = !!planId;
  const currentStep = !hasStep1 ? 1 : !hasStep2 ? 2 : 3;

  const filteredAthletes = useMemo(
    () =>
      athletes.filter((a) => {
        if (search && !a.display_name.toLowerCase().includes(search.toLowerCase()))
          return false;
        if (statusFilter === "no_plan" && a.current_plan != null) return false;
        if (statusFilter === "active" && a.current_status !== "active") return false;
        if (statusFilter === "late" && a.current_status !== "late") return false;
        return true;
      }),
    [athletes, search, statusFilter],
  );

  const allVisibleSelected =
    filteredAthletes.length > 0 &&
    filteredAthletes.every((a) => selectedIds.has(a.user_id));

  const toggleSelection = (userId: string) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(userId)) next.delete(userId);
      else next.add(userId);
      return next;
    });
  };

  const selectAll = () => {
    const visible = filteredAthletes.map((a) => a.user_id);
    setSelectedIds((prev) => {
      const next = new Set(prev);
      const all = visible.every((id) => next.has(id));
      if (all) visible.forEach((id) => next.delete(id));
      else visible.forEach((id) => next.add(id));
      return next;
    });
  };

  const handleAssign = async () => {
    if (!planId || selectedCount === 0) return;
    setLoading(true);
    setResult(null);
    setBillingProgress("");

    try {
      const res = await fetch("/api/financial/subscriptions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          plan_id: planId,
          athlete_user_ids: Array.from(selectedIds),
          started_at: startDate,
          next_due_date: dueDate,
        }),
      });
      const data = await res.json();
      setResult({ ok: data.ok, success: data.success, total: data.total });

      if (data.ok && autoBilling && asaasActive && selectedPlan) {
        setBillingProgress("Criando cobranças automáticas...");
        const selectedAthletes = athletes.filter((a) => selectedIds.has(a.user_id));
        let billingOk = 0;

        for (const athlete of selectedAthletes) {
          const cpf = athlete.cpf || cpfInputs[athlete.user_id];
          if (!cpf) continue;

          try {
            // 1. Create Asaas customer
            setBillingProgress(`Criando cliente: ${athlete.display_name}...`);
            const custRes = await fetch("/api/billing/asaas", {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({
                action: "create_customer",
                athlete_user_id: athlete.user_id,
                name: athlete.display_name,
                cpf,
                email: athlete.email ?? "",
              }),
            });
            const custData = await custRes.json();
            if (!custRes.ok) continue;

            const asaasCustomerId = custData.asaas_customer_id;

            // 2. Find the subscription ID just created
            const subsForAthletes = data.subscription_ids as Record<string, string> | undefined;
            const subscriptionId = subsForAthletes?.[athlete.user_id];
            if (!subscriptionId) continue;

            // 3. Create Asaas subscription with split
            setBillingProgress(`Ativando cobrança: ${athlete.display_name}...`);
            const cycle = selectedPlan.billing_cycle === "quarterly" ? "QUARTERLY" : "MONTHLY";
            const subRes = await fetch("/api/billing/asaas", {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({
                action: "create_subscription",
                subscription_id: subscriptionId,
                asaas_customer_id: asaasCustomerId,
                value: selectedPlan.monthly_price,
                cycle,
                next_due_date: dueDate,
                description: `${selectedPlan.name} — ${athlete.display_name}`,
              }),
            });
            if (subRes.ok) billingOk++;
          } catch {
            // continue with next athlete
          }
        }
        setBillingProgress(`Cobrança ativada para ${billingOk}/${selectedAthletes.length} atletas.`);
      }

      if (data.ok) {
        setSelectedIds(new Set());
        setPlanId("");
        setCpfInputs({});
        router.refresh();
      }
    } finally {
      setLoading(false);
    }
  };

  const selectedPlan = plans.find((p) => p.id === planId);

  const selectedNames = useMemo(() => {
    if (selectedCount === 0) return "";
    const names = athletes
      .filter((a) => selectedIds.has(a.user_id))
      .map((a) => a.display_name);
    if (names.length <= 3) return names.join(", ");
    return `${names.slice(0, 3).join(", ")} e mais ${names.length - 3}`;
  }, [athletes, selectedIds, selectedCount]);

  const noPlanCount = athletes.filter((a) => !a.current_plan).length;
  const activeCount = athletes.filter((a) => a.current_status === "active").length;
  const lateCount = athletes.filter((a) => a.current_status === "late").length;

  return (
    <div className="space-y-6">
      {/* Step Indicator */}
      <div className="flex items-center gap-2">
        {[1, 2, 3].map((step) => (
          <div key={step} className="flex items-center gap-2">
            <div
              className={`flex h-8 w-8 items-center justify-center rounded-full text-sm font-bold transition-colors ${
                step < currentStep
                  ? "bg-green-500 text-white"
                  : step === currentStep
                    ? "bg-brand text-white"
                    : "bg-surface-elevated text-content-muted"
              }`}
            >
              {step < currentStep ? "✓" : step}
            </div>
            <span
              className={`text-sm font-medium ${
                step === currentStep ? "text-content-primary" : "text-content-muted"
              }`}
            >
              {step === 1
                ? "Selecione os atletas"
                : step === 2
                  ? "Escolha o plano"
                  : "Confirme e atribua"}
            </span>
            {step < 3 && <div className="mx-2 h-px w-8 bg-border" />}
          </div>
        ))}
      </div>

      {/* KPI Badges */}
      <div className="flex flex-wrap gap-3">
        <div className="rounded-lg border border-border bg-surface px-4 py-2 text-sm">
          <span className="font-semibold text-content-primary">{athletes.length}</span>{" "}
          <span className="text-content-secondary">atletas</span>
        </div>
        <div className="rounded-lg border border-green-200 bg-green-50 px-4 py-2 text-sm dark:border-green-800 dark:bg-green-900/20">
          <span className="font-semibold text-green-800 dark:text-green-300">{activeCount}</span>{" "}
          <span className="text-green-700 dark:text-green-400">ativos</span>
        </div>
        {lateCount > 0 && (
          <div className="rounded-lg border border-red-200 bg-red-50 px-4 py-2 text-sm dark:border-red-800 dark:bg-red-900/20">
            <span className="font-semibold text-red-800 dark:text-red-300">{lateCount}</span>{" "}
            <span className="text-red-700 dark:text-red-400">inadimplentes</span>
          </div>
        )}
        {noPlanCount > 0 && (
          <div className="rounded-lg border border-gray-200 bg-gray-50 px-4 py-2 text-sm dark:border-gray-700 dark:bg-gray-800/30">
            <span className="font-semibold text-gray-700 dark:text-gray-300">{noPlanCount}</span>{" "}
            <span className="text-gray-500 dark:text-gray-400">sem plano</span>
          </div>
        )}
      </div>

      {/* STEP 1: Select Athletes */}
      <div className="rounded-xl border border-border bg-surface shadow-sm">
        <div className="border-b border-border px-6 py-4">
          <div className="flex items-center justify-between">
            <div>
              <h2 className="text-lg font-semibold text-content-primary">
                Passo 1 — Selecione os atletas
              </h2>
              <p className="mt-0.5 text-sm text-content-secondary">
                {selectedCount === 0
                  ? "Clique nos atletas para selecioná-los"
                  : `${selectedCount} atleta${selectedCount !== 1 ? "s" : ""} selecionado${selectedCount !== 1 ? "s" : ""}`}
              </p>
            </div>
            <div className="flex items-center gap-2">
              <input
                type="text"
                placeholder="Buscar..."
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                className="rounded-lg border border-border bg-surface px-3 py-1.5 text-sm focus:border-brand focus:ring-1 focus:ring-brand"
              />
              <select
                value={statusFilter}
                onChange={(e) => setStatusFilter(e.target.value)}
                className="rounded-lg border border-border bg-surface px-3 py-1.5 text-sm focus:border-brand focus:ring-1 focus:ring-brand"
              >
                <option value="all">Todos</option>
                <option value="no_plan">Sem plano</option>
                <option value="active">Ativos</option>
                <option value="late">Inadimplentes</option>
              </select>
            </div>
          </div>
        </div>

        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-border text-sm">
            <thead className="bg-bg-secondary">
              <tr>
                <th className="w-10 px-4 py-3">
                  <input
                    type="checkbox"
                    checked={allVisibleSelected}
                    onChange={selectAll}
                    className="rounded border-border text-brand focus:ring-brand"
                  />
                </th>
                <th className="px-4 py-3 text-left font-medium text-content-secondary">Atleta</th>
                <th className="px-4 py-3 text-center font-medium text-content-secondary">Plano Atual</th>
                <th className="px-4 py-3 text-center font-medium text-content-secondary">Status</th>
                <th className="px-4 py-3 text-center font-medium text-content-secondary">Vencimento</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border-subtle">
              {filteredAthletes.map((athlete) => {
                const selected = selectedIds.has(athlete.user_id);
                const badge = athlete.current_status
                  ? STATUS_BADGE[athlete.current_status]
                  : null;

                return (
                  <tr
                    key={athlete.member_id}
                    className={`cursor-pointer transition-colors ${
                      selected ? "bg-brand/5 dark:bg-brand/10" : "hover:bg-surface-elevated"
                    }`}
                    onClick={() => toggleSelection(athlete.user_id)}
                  >
                    <td className="px-4 py-3" onClick={(e) => e.stopPropagation()}>
                      <input
                        type="checkbox"
                        checked={selected}
                        onChange={() => toggleSelection(athlete.user_id)}
                        className="rounded border-border text-brand focus:ring-brand"
                      />
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 font-medium text-content-primary">
                      {athlete.display_name}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-center text-content-secondary">
                      {athlete.current_plan ?? (
                        <span className="text-content-muted">Sem plano</span>
                      )}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-center">
                      {badge ? (
                        <span className={`inline-flex rounded-full px-2.5 py-0.5 text-xs font-medium ${badge.cls}`}>
                          {badge.label}
                        </span>
                      ) : (
                        <span className="text-content-muted text-xs">—</span>
                      )}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-center text-content-secondary">
                      {athlete.next_due_date
                        ? new Date(athlete.next_due_date + "T12:00:00").toLocaleDateString("pt-BR")
                        : "—"}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>

        {filteredAthletes.length === 0 && (
          <div className="p-6 text-center text-sm text-content-secondary">
            Nenhum atleta encontrado.
          </div>
        )}
      </div>

      {/* STEP 2: Choose plan */}
      {hasStep1 && (
        <div className="rounded-xl border-2 border-brand/30 bg-surface shadow-sm">
          <div className="border-b border-border px-6 py-4">
            <h2 className="text-lg font-semibold text-content-primary">
              Passo 2 — Escolha o plano
            </h2>
            <p className="mt-0.5 text-sm text-content-secondary">
              Selecione um plano existente ou crie um novo em Planos
            </p>
          </div>

          <div className="px-6 py-5">
            {plans.length === 0 ? (
              <div className="text-center">
                <p className="text-sm text-content-secondary">
                  Nenhum plano ativo.{" "}
                  <a href="/financial/plans" className="text-brand hover:underline">
                    Crie um plano primeiro
                  </a>
                </p>
              </div>
            ) : (
              <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                {plans.map((plan) => (
                  <button
                    key={plan.id}
                    onClick={() => setPlanId(plan.id === planId ? "" : plan.id)}
                    className={`rounded-xl border-2 p-4 text-left transition ${
                      planId === plan.id
                        ? "border-brand bg-brand/5"
                        : "border-border hover:border-brand/40"
                    }`}
                  >
                    <p className="text-sm font-semibold text-content-primary">
                      {plan.name}
                    </p>
                    <p className="mt-1 text-lg font-bold text-brand">
                      R$ {plan.monthly_price.toFixed(2)}
                      <span className="text-xs font-normal text-content-muted">
                        /{plan.billing_cycle === "quarterly" ? "trim" : "mês"}
                      </span>
                    </p>
                  </button>
                ))}
              </div>
            )}
          </div>
        </div>
      )}

      {/* STEP 3: Confirm */}
      {hasStep1 && hasStep2 && (
        <div className="rounded-xl border-2 border-green-300 bg-green-50/50 p-6 shadow-sm dark:border-green-800 dark:bg-green-900/10">
          <h2 className="text-lg font-semibold text-content-primary">
            Passo 3 — Confirme e atribua
          </h2>

          <div className="mt-3 rounded-lg border border-border bg-surface p-4 text-sm">
            <div className="flex items-center gap-2">
              <span className="font-medium text-content-secondary">Atletas:</span>
              <span className="text-content-primary">{selectedNames}</span>
            </div>
            <div className="mt-2 flex items-center gap-2">
              <span className="font-medium text-content-secondary">Plano:</span>
              <span className="text-content-primary">
                {selectedPlan?.name} — R$ {selectedPlan?.monthly_price.toFixed(2)}
              </span>
            </div>
          </div>

          {/* Auto-billing toggle */}
          {asaasActive && (
            <div className="mt-4 rounded-lg border border-brand/30 bg-brand/5 p-4">
              <label className="flex items-center gap-3 cursor-pointer">
                <input
                  type="checkbox"
                  checked={autoBilling}
                  onChange={(e) => setAutoBilling(e.target.checked)}
                  className="rounded border-border text-brand focus:ring-brand h-5 w-5"
                />
                <div>
                  <span className="text-sm font-semibold text-content-primary">
                    Ativar cobrança automática via Asaas
                  </span>
                  <p className="text-xs text-content-secondary">
                    O atleta receberá um email com link de pagamento (PIX, boleto ou cartão)
                  </p>
                </div>
              </label>

              {autoBilling && (() => {
                const selected = athletes.filter((a) => selectedIds.has(a.user_id));
                const noCpf = selected.filter((a) => !a.cpf && !cpfInputs[a.user_id]);
                return noCpf.length > 0 ? (
                  <div className="mt-3 space-y-2">
                    <p className="text-xs font-medium text-content-secondary">
                      CPF necessário para {noCpf.length} atleta{noCpf.length !== 1 ? "s" : ""}:
                    </p>
                    {noCpf.map((a) => (
                      <div key={a.user_id} className="flex items-center gap-2">
                        <span className="text-sm text-content-primary w-40 truncate">{a.display_name}</span>
                        <input
                          type="text"
                          placeholder="000.000.000-00"
                          value={cpfInputs[a.user_id] ?? ""}
                          onChange={(e) => setCpfInputs((prev) => ({ ...prev, [a.user_id]: e.target.value }))}
                          className="rounded-lg border border-border bg-surface px-3 py-1.5 text-sm w-44"
                          maxLength={14}
                        />
                      </div>
                    ))}
                  </div>
                ) : (
                  <p className="mt-2 text-xs text-success">
                    Todos os atletas selecionados possuem CPF cadastrado.
                  </p>
                );
              })()}
            </div>
          )}

          <div className="mt-4 flex flex-wrap items-end gap-4">
            <div>
              <label className="mb-1 block text-xs font-medium text-content-secondary">
                Data de início
              </label>
              <input
                type="date"
                value={startDate}
                onChange={(e) => setStartDate(e.target.value)}
                className="rounded-lg border border-border bg-surface px-3 py-2.5 text-sm focus:border-brand focus:ring-1 focus:ring-brand"
              />
            </div>
            <div>
              <label className="mb-1 block text-xs font-medium text-content-secondary">
                Próximo vencimento
              </label>
              <input
                type="date"
                value={dueDate}
                onChange={(e) => setDueDate(e.target.value)}
                className="rounded-lg border border-border bg-surface px-3 py-2.5 text-sm focus:border-brand focus:ring-1 focus:ring-brand"
              />
            </div>
            <button
              onClick={handleAssign}
              disabled={loading}
              className="rounded-lg bg-green-600 px-6 py-2.5 text-sm font-semibold text-white hover:bg-green-700 disabled:opacity-50"
            >
              {loading
                ? "Atribuindo..."
                : `Atribuir plano a ${selectedCount} atleta${selectedCount !== 1 ? "s" : ""}`}
            </button>
          </div>

          {billingProgress && (
            <div className="mt-3 rounded-lg border border-brand/20 bg-brand/5 px-4 py-2 text-sm text-brand">
              {billingProgress}
            </div>
          )}

          {result && (
            <div
              className={`mt-3 rounded-lg px-4 py-2 text-sm ${
                result.ok
                  ? "border border-green-200 bg-green-100 text-green-800 dark:border-green-800 dark:bg-green-900/30 dark:text-green-300"
                  : "border border-red-200 bg-red-100 text-red-800 dark:border-red-800 dark:bg-red-900/30 dark:text-red-300"
              }`}
            >
              {result.success}/{result.total} atribuições realizadas com sucesso.
            </div>
          )}
        </div>
      )}
    </div>
  );
}
