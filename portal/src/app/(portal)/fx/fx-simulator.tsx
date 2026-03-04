"use client";

import { useState } from "react";
import { formatUsd } from "@/lib/format";

export function FxSimulator({ spreadRate }: { spreadRate: number }) {
  const [direction, setDirection] = useState<"in" | "out">("in");
  const [amount, setAmount] = useState("");
  const [rate, setRate] = useState("5.25");

  const amountNum = parseFloat(amount) || 0;
  const rateNum = parseFloat(rate) || 1;

  let result = { rawUsd: 0, spread: 0, netUsd: 0, localAmount: 0 };

  if (direction === "in") {
    const rawUsd = amountNum / rateNum;
    const spread = rawUsd * (spreadRate / 100);
    const netUsd = rawUsd - spread;
    result = { rawUsd, spread, netUsd, localAmount: amountNum };
  } else {
    const spread = amountNum * (spreadRate / 100);
    const netUsd = amountNum - spread;
    const localAmount = netUsd * rateNum;
    result = { rawUsd: amountNum, spread, netUsd, localAmount };
  }

  return (
    <div className="rounded-xl border border-border bg-surface p-6 shadow-sm">
      <h2 className="text-lg font-semibold text-content-primary">Simulador FX</h2>
      <p className="mt-1 text-sm text-content-secondary">Simule conversoes antes de executar</p>

      <div className="mt-4 flex flex-wrap gap-4">
        <div>
          <label className="block text-xs font-medium text-content-secondary">Direcao</label>
          <select
            value={direction}
            onChange={(e) => setDirection(e.target.value as "in" | "out")}
            className="mt-1 rounded-lg border border-border px-3 py-2 text-sm"
          >
            <option value="in">BRL &rarr; USD (Deposito)</option>
            <option value="out">USD &rarr; BRL (Retirada)</option>
          </select>
        </div>
        <div>
          <label className="block text-xs font-medium text-content-secondary">
            {direction === "in" ? "Valor em BRL" : "Valor em USD"}
          </label>
          <input
            type="number"
            step="0.01"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            className="mt-1 w-36 rounded-lg border border-border px-3 py-2 text-sm"
            placeholder={direction === "in" ? "1000.00" : "200.00"}
          />
        </div>
        <div>
          <label className="block text-xs font-medium text-content-secondary">Cotacao BRL/USD</label>
          <input
            type="number"
            step="0.0001"
            value={rate}
            onChange={(e) => setRate(e.target.value)}
            className="mt-1 w-28 rounded-lg border border-border px-3 py-2 text-sm"
          />
        </div>
      </div>

      {amountNum > 0 && (
        <div className="mt-4 rounded-lg bg-bg-secondary p-4">
          <div className="grid grid-cols-2 gap-3 text-sm sm:grid-cols-4">
            <div>
              <p className="text-xs text-content-secondary">
                {direction === "in" ? "USD Bruto" : "USD Solicitado"}
              </p>
              <p className="font-bold text-content-primary">{formatUsd(result.rawUsd)}</p>
            </div>
            <div>
              <p className="text-xs text-content-secondary">Spread ({spreadRate}%)</p>
              <p className="font-bold text-orange-600">-{formatUsd(result.spread)}</p>
            </div>
            <div>
              <p className="text-xs text-content-secondary">
                {direction === "in" ? "USD Creditado" : "USD Debitado"}
              </p>
              <p className="font-bold text-success">{formatUsd(result.netUsd)}</p>
            </div>
            <div>
              <p className="text-xs text-content-secondary">
                {direction === "in" ? "BRL Depositado" : "BRL Recebido"}
              </p>
              <p className="font-bold text-content-primary">
                R$ {result.localAmount.toLocaleString("pt-BR", { minimumFractionDigits: 2 })}
              </p>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
