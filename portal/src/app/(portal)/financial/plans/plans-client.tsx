"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

interface Plan {
  id: string;
  name: string;
  description: string | null;
  monthly_price: number;
  billing_cycle: string;
  max_workouts_per_week: number | null;
  status: string;
  subscriber_count: number;
}

const CYCLE_LABEL: Record<string, string> = {
  monthly: "Mensal",
  quarterly: "Trimestral",
};

export function PlansClient({ plans }: { plans: Plan[] }) {
  const router = useRouter();
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState<Plan | null>(null);
  const [deleting, setDeleting] = useState<string | null>(null);
  const [deleteError, setDeleteError] = useState<string | null>(null);

  const openCreate = () => {
    setEditing(null);
    setShowForm(true);
  };

  const openEdit = (plan: Plan) => {
    setEditing(plan);
    setShowForm(true);
  };

  const handleDelete = async (id: string) => {
    setDeleteError(null);
    const res = await fetch("/api/financial/plans", {
      method: "DELETE",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id }),
    });
    const data = await res.json();
    if (data.ok) {
      setDeleting(null);
      router.refresh();
    } else {
      setDeleteError(data.error);
    }
  };

  return (
    <>
      {!showForm && (
        <button
          onClick={openCreate}
          className="rounded-lg bg-brand px-5 py-2.5 text-sm font-medium text-white hover:bg-brand/90"
        >
          + Novo Plano
        </button>
      )}

      {showForm && (
        <PlanForm
          plan={editing}
          onClose={() => {
            setShowForm(false);
            setEditing(null);
          }}
          onSaved={() => {
            setShowForm(false);
            setEditing(null);
            router.refresh();
          }}
        />
      )}

      {deleteError && (
        <div className="rounded-lg border border-error/30 bg-error-soft px-4 py-3 text-sm text-error">
          {deleteError}
        </div>
      )}

      <div className="overflow-hidden rounded-xl border border-border bg-surface shadow-sm">
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-border text-sm">
            <thead className="bg-bg-secondary">
              <tr>
                <th className="px-4 py-3 text-left font-medium text-content-secondary">
                  Nome
                </th>
                <th className="px-4 py-3 text-right font-medium text-content-secondary">
                  Preço
                </th>
                <th className="px-4 py-3 text-center font-medium text-content-secondary">
                  Ciclo
                </th>
                <th className="px-4 py-3 text-center font-medium text-content-secondary">
                  Limite
                </th>
                <th className="px-4 py-3 text-center font-medium text-content-secondary">
                  Status
                </th>
                <th className="px-4 py-3 text-center font-medium text-content-secondary">
                  Assinantes
                </th>
                <th className="px-4 py-3 text-center font-medium text-content-secondary">
                  Ações
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border-subtle">
              {plans.map((plan) => (
                <tr key={plan.id} className="hover:bg-surface-elevated">
                  <td className="px-4 py-3">
                    <div className="font-medium text-content-primary">
                      {plan.name}
                    </div>
                    {plan.description && (
                      <div className="mt-0.5 text-xs text-content-secondary">
                        {plan.description}
                      </div>
                    )}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-right text-content-primary font-medium">
                    R$ {plan.monthly_price.toFixed(2)}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-center text-content-secondary">
                    {CYCLE_LABEL[plan.billing_cycle] ?? plan.billing_cycle}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-center text-content-secondary">
                    {plan.max_workouts_per_week ?? "Ilim."}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-center">
                    <span
                      className={`inline-flex rounded-full px-2.5 py-0.5 text-xs font-medium ${
                        plan.status === "active"
                          ? "bg-success-soft text-success"
                          : "bg-surface-elevated text-content-secondary"
                      }`}
                    >
                      {plan.status === "active" ? "Ativo" : "Inativo"}
                    </span>
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-center font-medium text-content-primary">
                    {plan.subscriber_count}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-center">
                    <div className="flex items-center justify-center gap-2">
                      <button
                        onClick={() => openEdit(plan)}
                        className="text-xs text-brand hover:underline"
                      >
                        Editar
                      </button>
                      {deleting === plan.id ? (
                        <div className="flex items-center gap-1">
                          <button
                            onClick={() => handleDelete(plan.id)}
                            className="text-xs text-error hover:underline"
                          >
                            Sim
                          </button>
                          <button
                            onClick={() => setDeleting(null)}
                            className="text-xs text-content-muted hover:underline"
                          >
                            Não
                          </button>
                        </div>
                      ) : (
                        <button
                          onClick={() => setDeleting(plan.id)}
                          className="text-xs text-error/60 hover:text-error"
                        >
                          Excluir
                        </button>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {plans.length === 0 && (
        <div className="rounded-xl border border-border bg-surface p-8 text-center shadow-sm">
          <p className="text-sm text-content-secondary">
            Nenhum plano criado. Clique em &quot;Novo Plano&quot; para começar.
          </p>
        </div>
      )}
    </>
  );
}

function PlanForm({
  plan,
  onClose,
  onSaved,
}: {
  plan: Plan | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [name, setName] = useState(plan?.name ?? "");
  const [description, setDescription] = useState(plan?.description ?? "");
  const [price, setPrice] = useState(plan?.monthly_price?.toString() ?? "");
  const [cycle, setCycle] = useState(plan?.billing_cycle ?? "monthly");
  const [limit, setLimit] = useState(
    plan?.max_workouts_per_week?.toString() ?? "",
  );
  const [status, setStatus] = useState(plan?.status ?? "active");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleSave = async () => {
    setError(null);
    if (!name.trim() || name.trim().length < 2) {
      setError("Nome deve ter pelo menos 2 caracteres");
      return;
    }
    const priceNum = parseFloat(price);
    if (isNaN(priceNum) || priceNum < 0) {
      setError("Preço inválido");
      return;
    }

    setSaving(true);
    try {
      const res = await fetch("/api/financial/plans", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          id: plan?.id,
          name,
          description,
          monthly_price: priceNum,
          billing_cycle: cycle,
          max_workouts_per_week: limit ? parseInt(limit) : null,
          status,
        }),
      });
      const data = await res.json();
      if (data.ok) {
        onSaved();
      } else {
        setError(data.error);
      }
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="rounded-xl border-2 border-brand/30 bg-surface p-6 shadow-sm">
      <h3 className="text-base font-semibold text-content-primary">
        {plan ? "Editar Plano" : "Novo Plano"}
      </h3>

      {error && (
        <p className="mt-2 text-sm text-error">{error}</p>
      )}

      <div className="mt-4 grid gap-4 sm:grid-cols-2">
        <div>
          <label className="mb-1 block text-xs font-medium text-content-secondary">
            Nome *
          </label>
          <input
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Ex: Plano Básico"
            className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm focus:border-brand focus:ring-1 focus:ring-brand"
          />
        </div>
        <div>
          <label className="mb-1 block text-xs font-medium text-content-secondary">
            Descrição
          </label>
          <input
            type="text"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="Opcional"
            className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm focus:border-brand focus:ring-1 focus:ring-brand"
          />
        </div>
        <div>
          <label className="mb-1 block text-xs font-medium text-content-secondary">
            Preço mensal (R$) *
          </label>
          <input
            type="number"
            min={0}
            step={0.01}
            value={price}
            onChange={(e) => setPrice(e.target.value)}
            placeholder="150.00"
            className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm focus:border-brand focus:ring-1 focus:ring-brand"
          />
        </div>
        <div>
          <label className="mb-1 block text-xs font-medium text-content-secondary">
            Ciclo de cobrança
          </label>
          <select
            value={cycle}
            onChange={(e) => setCycle(e.target.value)}
            className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm focus:border-brand focus:ring-1 focus:ring-brand"
          >
            <option value="monthly">Mensal</option>
            <option value="quarterly">Trimestral</option>
          </select>
        </div>
        <div>
          <label className="mb-1 block text-xs font-medium text-content-secondary">
            Limite treinos/semana
          </label>
          <input
            type="number"
            min={0}
            value={limit}
            onChange={(e) => setLimit(e.target.value)}
            placeholder="Vazio = ilimitado"
            className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm focus:border-brand focus:ring-1 focus:ring-brand"
          />
        </div>
        <div>
          <label className="mb-1 block text-xs font-medium text-content-secondary">
            Status
          </label>
          <select
            value={status}
            onChange={(e) => setStatus(e.target.value)}
            className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm focus:border-brand focus:ring-1 focus:ring-brand"
          >
            <option value="active">Ativo</option>
            <option value="inactive">Inativo</option>
          </select>
        </div>
      </div>

      <div className="mt-5 flex justify-end gap-3">
        <button
          onClick={onClose}
          className="rounded-lg border border-border px-4 py-2 text-sm text-content-secondary hover:bg-surface-elevated"
        >
          Cancelar
        </button>
        <button
          onClick={handleSave}
          disabled={saving}
          className="rounded-lg bg-brand px-5 py-2 text-sm font-medium text-white hover:bg-brand/90 disabled:opacity-50"
        >
          {saving ? "Salvando..." : "Salvar Plano"}
        </button>
      </div>
    </div>
  );
}
