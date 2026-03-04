"use client";

import { useState } from "react";
import { createBrowserClient } from "@supabase/ssr";
import { useRouter } from "next/navigation";

const categories = [
  { value: "distance", label: "Distância" },
  { value: "frequency", label: "Frequência" },
  { value: "speed", label: "Velocidade" },
  { value: "endurance", label: "Resistência" },
  { value: "social", label: "Social" },
  { value: "special", label: "Especial" },
];

const tiers = [
  { value: "bronze", label: "Bronze" },
  { value: "silver", label: "Prata" },
  { value: "gold", label: "Ouro" },
  { value: "diamond", label: "Diamante" },
];

const criteriaTypes = [
  { value: "single_session_distance", label: "Distância em 1 sessão", placeholder: '{"threshold_m": 5000}' },
  { value: "lifetime_distance", label: "Distância lifetime", placeholder: '{"threshold_m": 50000}' },
  { value: "session_count", label: "Quantidade de sessões", placeholder: '{"count": 10}' },
  { value: "daily_streak", label: "Sequência diária", placeholder: '{"days": 7}' },
  { value: "weekly_distance", label: "Distância semanal", placeholder: '{"threshold_m": 10000}' },
  { value: "pace_below", label: "Pace abaixo de", placeholder: '{"max_pace_sec_per_km": 300, "min_distance_m": 5000}' },
  { value: "single_session_duration", label: "Duração em 1 sessão", placeholder: '{"threshold_ms": 3600000}' },
  { value: "lifetime_duration", label: "Duração lifetime", placeholder: '{"threshold_ms": 36000000}' },
  { value: "challenges_completed", label: "Desafios completados", placeholder: '{"count": 5}' },
  { value: "challenge_won", label: "Desafios vencidos", placeholder: '{"count": 1}' },
  { value: "championship_completed", label: "Campeonatos completados", placeholder: '{"count": 1}' },
  { value: "session_before_hour", label: "Sessão antes de hora", placeholder: '{"hour_local": 6}' },
  { value: "session_after_hour", label: "Sessão após hora", placeholder: '{"hour_local": 22}' },
  { value: "personal_record_pace", label: "PR de pace", placeholder: '{"min_distance_m": 1000}' },
  { value: "consecutive_wins", label: "Vitórias consecutivas", placeholder: '{"count": 10}' },
  { value: "group_leader", label: "Líder de grupo", placeholder: '{"min_participants": 5}' },
];

export function BadgeForm() {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");

  const [id, setId] = useState("");
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [category, setCategory] = useState("distance");
  const [tier, setTier] = useState("bronze");
  const [xpReward, setXpReward] = useState(50);
  const [coinsReward, setCoinsReward] = useState(0);
  const [criteriaType, setCriteriaType] = useState("single_session_distance");
  const [criteriaJson, setCriteriaJson] = useState('{"threshold_m": 5000}');
  const [isSecret, setIsSecret] = useState(false);

  const selectedCriteria = criteriaTypes.find((c) => c.value === criteriaType);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    setSuccess("");
    setSaving(true);

    try {
      JSON.parse(criteriaJson);
    } catch {
      setError("JSON de critério inválido");
      setSaving(false);
      return;
    }

    const supabase = createBrowserClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    );

    const { error: insertError } = await supabase.from("badges").insert({
      id: id || `badge_${name.toLowerCase().replace(/\s+/g, "_").replace(/[^a-z0-9_]/g, "")}`,
      name,
      description,
      category,
      tier,
      xp_reward: xpReward,
      coins_reward: coinsReward,
      criteria_type: criteriaType,
      criteria_json: JSON.parse(criteriaJson),
      is_secret: isSecret,
    });

    setSaving(false);

    if (insertError) {
      setError(insertError.message);
      return;
    }

    setSuccess("Conquista criada com sucesso!");
    setOpen(false);
    setId("");
    setName("");
    setDescription("");
    setCriteriaJson(selectedCriteria?.placeholder ?? "{}");
    router.refresh();
  }

  if (!open) {
    return (
      <button
        onClick={() => setOpen(true)}
        className="rounded-lg bg-error px-4 py-2 text-sm font-medium text-white hover:brightness-110 transition"
      >
        + Nova Conquista
      </button>
    );
  }

  return (
    <div className="rounded-xl border border-border bg-surface p-6 shadow-sm">
      <h3 className="mb-4 text-lg font-semibold text-content-primary">
        Nova Conquista
      </h3>

      {error && (
        <div className="mb-4 rounded-lg bg-error-soft border border-error/30 p-3 text-sm text-error">
          {error}
        </div>
      )}
      {success && (
        <div className="mb-4 rounded-lg bg-success-soft border border-green-200 p-3 text-sm text-success">
          {success}
        </div>
      )}

      <form onSubmit={handleSubmit} className="space-y-4">
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div>
            <label className="block text-sm font-medium text-content-secondary">ID (opcional)</label>
            <input
              type="text"
              value={id}
              onChange={(e) => setId(e.target.value)}
              placeholder="badge_custom_name"
              className="mt-1 block w-full rounded-lg border border-border px-3 py-2 text-sm shadow-sm focus:border-red-500 focus:ring-red-500"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-content-secondary">Nome *</label>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              required
              placeholder="Corredor Ultra"
              className="mt-1 block w-full rounded-lg border border-border px-3 py-2 text-sm shadow-sm focus:border-red-500 focus:ring-red-500"
            />
          </div>
        </div>

        <div>
          <label className="block text-sm font-medium text-content-secondary">Descrição *</label>
          <input
            type="text"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            required
            placeholder="Complete 1 sessão ≥ 50 km"
            className="mt-1 block w-full rounded-lg border border-border px-3 py-2 text-sm shadow-sm focus:border-red-500 focus:ring-red-500"
          />
        </div>

        <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
          <div>
            <label className="block text-sm font-medium text-content-secondary">Categoria</label>
            <select
              value={category}
              onChange={(e) => setCategory(e.target.value)}
              className="mt-1 block w-full rounded-lg border border-border px-3 py-2 text-sm shadow-sm"
            >
              {categories.map((c) => (
                <option key={c.value} value={c.value}>{c.label}</option>
              ))}
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-content-secondary">Tier</label>
            <select
              value={tier}
              onChange={(e) => setTier(e.target.value)}
              className="mt-1 block w-full rounded-lg border border-border px-3 py-2 text-sm shadow-sm"
            >
              {tiers.map((t) => (
                <option key={t.value} value={t.value}>{t.label}</option>
              ))}
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-content-secondary">XP</label>
            <input
              type="number"
              value={xpReward}
              onChange={(e) => setXpReward(Number(e.target.value))}
              className="mt-1 block w-full rounded-lg border border-border px-3 py-2 text-sm shadow-sm"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-content-secondary">Coins</label>
            <input
              type="number"
              value={coinsReward}
              onChange={(e) => setCoinsReward(Number(e.target.value))}
              className="mt-1 block w-full rounded-lg border border-border px-3 py-2 text-sm shadow-sm"
            />
          </div>
        </div>

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div>
            <label className="block text-sm font-medium text-content-secondary">Tipo de critério</label>
            <select
              value={criteriaType}
              onChange={(e) => {
                setCriteriaType(e.target.value);
                const ct = criteriaTypes.find((c) => c.value === e.target.value);
                if (ct) setCriteriaJson(ct.placeholder);
              }}
              className="mt-1 block w-full rounded-lg border border-border px-3 py-2 text-sm shadow-sm"
            >
              {criteriaTypes.map((c) => (
                <option key={c.value} value={c.value}>{c.label}</option>
              ))}
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-content-secondary">Critério (JSON)</label>
            <input
              type="text"
              value={criteriaJson}
              onChange={(e) => setCriteriaJson(e.target.value)}
              className="mt-1 block w-full rounded-lg border border-border px-3 py-2 text-sm font-mono shadow-sm focus:border-red-500 focus:ring-red-500"
            />
          </div>
        </div>

        <div className="flex items-center gap-2">
          <input
            type="checkbox"
            id="isSecret"
            checked={isSecret}
            onChange={(e) => setIsSecret(e.target.checked)}
            className="h-4 w-4 rounded border-border text-error focus:ring-red-500"
          />
          <label htmlFor="isSecret" className="text-sm text-content-secondary">
            Conquista secreta (oculta até ser desbloqueada)
          </label>
        </div>

        <div className="flex gap-3 pt-2">
          <button
            type="submit"
            disabled={saving}
            className="rounded-lg bg-error px-4 py-2 text-sm font-medium text-white hover:brightness-110 disabled:opacity-50 transition"
          >
            {saving ? "Salvando..." : "Criar Conquista"}
          </button>
          <button
            type="button"
            onClick={() => setOpen(false)}
            className="rounded-lg border border-border px-4 py-2 text-sm font-medium text-content-secondary hover:bg-surface-elevated transition"
          >
            Cancelar
          </button>
        </div>
      </form>
    </div>
  );
}
