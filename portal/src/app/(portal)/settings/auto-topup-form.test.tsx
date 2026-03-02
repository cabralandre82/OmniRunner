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
});
