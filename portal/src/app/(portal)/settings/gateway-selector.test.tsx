// @vitest-environment happy-dom
import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { GatewaySelector } from "./gateway-selector";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ refresh: vi.fn() }),
}));

describe("GatewaySelector", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it("renders both gateway options", () => {
    render(<GatewaySelector currentGateway="mercadopago" />);
    expect(screen.getByText("MercadoPago")).toBeTruthy();
    expect(screen.getByText("Stripe")).toBeTruthy();
  });

  it("does not show save button when selection unchanged", () => {
    render(<GatewaySelector currentGateway="mercadopago" />);
    expect(screen.queryByText("Salvar Preferência")).toBeNull();
  });

  it("shows save button when selection changed", () => {
    render(<GatewaySelector currentGateway="mercadopago" />);
    fireEvent.click(screen.getByText("Stripe"));
    expect(screen.getByText("Salvar Preferência")).toBeTruthy();
  });

  it("saves preference on click", async () => {
    const mockFetch = vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ success: true }),
    });
    vi.stubGlobal("fetch", mockFetch);

    render(<GatewaySelector currentGateway="mercadopago" />);
    fireEvent.click(screen.getByText("Stripe"));
    fireEvent.click(screen.getByText("Salvar Preferência"));

    await waitFor(() => {
      expect(mockFetch).toHaveBeenCalledWith(
        "/api/gateway-preference",
        expect.objectContaining({ method: "POST" })
      );
    });

    await waitFor(() => {
      expect(screen.getByText("Preferência salva com sucesso!")).toBeTruthy();
    });
  });

  it("shows error on save failure", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: false,
      json: () => Promise.resolve({ error: "Falha" }),
    }));

    render(<GatewaySelector currentGateway="mercadopago" />);
    fireEvent.click(screen.getByText("Stripe"));
    fireEvent.click(screen.getByText("Salvar Preferência"));

    await waitFor(() => {
      expect(screen.getByText("Falha")).toBeTruthy();
    });
  });
});
