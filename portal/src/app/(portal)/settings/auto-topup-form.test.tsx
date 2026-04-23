// @vitest-environment happy-dom
import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { AutoTopupForm } from "./auto-topup-form";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ refresh: vi.fn() }),
}));

const products = [
  { id: "p1", name: "Pacote 100", credits_amount: 100, price_cents: 1990 },
  { id: "p2", name: "Pacote 500", credits_amount: 500, price_cents: 7990 },
];

describe("AutoTopupForm", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it("renders empty message when no products", () => {
    render(
      <AutoTopupForm currentSettings={null} products={[]} />
    );
    expect(
      screen.getByText(/Nenhum pacote de créditos disponível/)
    ).toBeTruthy();
  });

  it("renders toggle and config fields", () => {
    render(
      <AutoTopupForm currentSettings={null} products={products} />
    );
    expect(screen.getByRole("switch")).toBeTruthy();
    expect(screen.getByText("Salvar Configurações")).toBeTruthy();
  });

  it("toggles enabled state", () => {
    render(
      <AutoTopupForm currentSettings={null} products={products} />
    );
    const toggle = screen.getByRole("switch");
    expect(toggle.getAttribute("aria-checked")).toBe("false");
    fireEvent.click(toggle);
    expect(toggle.getAttribute("aria-checked")).toBe("true");
  });

  it("saves settings on save click", async () => {
    const mockFetch = vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ success: true }),
    });
    vi.stubGlobal("fetch", mockFetch);

    render(
      <AutoTopupForm currentSettings={null} products={products} />
    );

    fireEvent.click(screen.getByText("Salvar Configurações"));

    await waitFor(() => {
      expect(mockFetch).toHaveBeenCalledWith(
        "/api/auto-topup",
        expect.objectContaining({ method: "POST" })
      );
    });

    await waitFor(() => {
      expect(screen.getByText("Configurações salvas!")).toBeTruthy();
    });
  });

  it("shows error on save failure", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: false,
      json: () => Promise.resolve({ error: "Erro ao salvar configurações" }),
    }));

    render(
      <AutoTopupForm currentSettings={null} products={products} />
    );

    fireEvent.click(screen.getByText("Salvar Configurações"));

    await waitFor(() => {
      expect(screen.getByText("Erro ao salvar configurações")).toBeTruthy();
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // L12-05 — daily cap antifraude UI
  // ─────────────────────────────────────────────────────────────────────────
  describe("L12-05 daily cap UI", () => {
    const baseSettings = {
      enabled: true,
      threshold_tokens: 50,
      product_id: "p1",
      max_per_month: 3,
      daily_charge_cap_brl: 500,
      daily_max_charges: 3,
      daily_limit_timezone: "America/Sao_Paulo",
    };

    it("hides advanced daily cap section when no Stripe payment method", () => {
      render(
        <AutoTopupForm
          currentSettings={baseSettings}
          products={products}
          hasStripePaymentMethod={false}
        />,
      );
      expect(
        screen.queryByText(/Limites diários de antifraude/),
      ).toBeNull();
    });

    it("shows advanced daily cap section when Stripe is connected", () => {
      render(
        <AutoTopupForm
          currentSettings={baseSettings}
          products={products}
          hasStripePaymentMethod
        />,
      );
      expect(
        screen.getByText(/Limites diários de antifraude/),
      ).toBeTruthy();
    });

    it("does NOT send daily_* fields when nothing changed", async () => {
      const mockFetch = vi.fn().mockResolvedValue({
        ok: true,
        json: () => Promise.resolve({ ok: true, daily_cap: null }),
      });
      vi.stubGlobal("fetch", mockFetch);

      render(
        <AutoTopupForm
          currentSettings={baseSettings}
          products={products}
          hasStripePaymentMethod
        />,
      );

      fireEvent.click(screen.getByText("Salvar Configurações"));

      await waitFor(() => {
        expect(mockFetch).toHaveBeenCalled();
      });
      const body = JSON.parse(
        (mockFetch.mock.calls[0][1] as { body: string }).body,
      );
      expect(body.daily_charge_cap_brl).toBeUndefined();
      expect(body.daily_max_charges).toBeUndefined();
      expect(body.daily_cap_change_reason).toBeUndefined();
    });

    it("blocks save with client-side validation when reason < 10 chars", async () => {
      const mockFetch = vi.fn();
      vi.stubGlobal("fetch", mockFetch);

      const { container } = render(
        <AutoTopupForm
          currentSettings={baseSettings}
          products={products}
          hasStripePaymentMethod
        />,
      );

      // happy-dom doesn't toggle <details> on summary click; force open.
      const details = container.querySelector(
        '[data-testid="daily-cap-section"]',
      ) as HTMLDetailsElement;
      details.open = true;

      const capInput = screen.getByLabelText(
        /Teto diário em R\$/,
      ) as HTMLInputElement;
      fireEvent.change(capInput, { target: { value: "1000" } });

      const reasonField = await screen.findByLabelText(/Motivo da alteração/);
      fireEvent.change(reasonField, { target: { value: "short" } });

      fireEvent.click(screen.getByText("Salvar Configurações"));

      await waitFor(() => {
        expect(
          screen.getByText(/Informe o motivo \(>= 10 caracteres\)/),
        ).toBeTruthy();
      });
      expect(mockFetch).not.toHaveBeenCalled();
    });

    it("sends daily_* fields plus reason when admin changes the cap", async () => {
      const mockFetch = vi.fn().mockResolvedValue({
        ok: true,
        json: () =>
          Promise.resolve({
            ok: true,
            daily_cap: {
              previous_cap_brl: 500,
              new_cap_brl: 1500,
              previous_max_charges: 3,
              new_max_charges: 3,
              was_idempotent: false,
            },
          }),
      });
      vi.stubGlobal("fetch", mockFetch);

      const { container } = render(
        <AutoTopupForm
          currentSettings={baseSettings}
          products={products}
          hasStripePaymentMethod
        />,
      );

      const details = container.querySelector(
        '[data-testid="daily-cap-section"]',
      ) as HTMLDetailsElement;
      details.open = true;

      const capInput = screen.getByLabelText(
        /Teto diário em R\$/,
      ) as HTMLInputElement;
      fireEvent.change(capInput, { target: { value: "1500" } });

      const reasonField = await screen.findByLabelText(/Motivo da alteração/);
      fireEvent.change(reasonField, {
        target: {
          value: "ajuste após reunião com CFO em SUP-1234, temporada de provas",
        },
      });

      fireEvent.click(screen.getByText("Salvar Configurações"));

      await waitFor(() => {
        expect(mockFetch).toHaveBeenCalled();
      });
      const body = JSON.parse(
        (mockFetch.mock.calls[0][1] as { body: string }).body,
      );
      expect(body.daily_charge_cap_brl).toBe(1500);
      expect(body.daily_cap_change_reason).toContain("CFO");
      expect(body.daily_limit_timezone).toBe("America/Sao_Paulo");
    });
  });
});
