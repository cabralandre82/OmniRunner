/**
 * @vitest-environment happy-dom
 */
import React from "react";
import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import "@testing-library/jest-dom/vitest";
import { NextIntlClientProvider } from "next-intl";
import { DistributeButton } from "./distribute-button";

const messages = {
  common: { confirm: "Confirmar", cancel: "Cancelar", loading: "Carregando..." },
  athletes: { distribute: "Distribuir moedas" },
  error: { generic: "Algo deu errado. Tente novamente." },
};

function W({ children }: { children: React.ReactNode }) {
  return (
    <NextIntlClientProvider locale="pt-BR" messages={messages}>
      {children}
    </NextIntlClientProvider>
  );
}

const mockFetch = vi.fn();
vi.stubGlobal("fetch", mockFetch);

describe("DistributeButton", () => {
  beforeEach(() => vi.clearAllMocks());

  it("renders Distribuir button initially", () => {
    render(<DistributeButton athleteId="u1" athleteName="João" />, { wrapper: W });
    expect(screen.getByText("Distribuir moedas")).toBeInTheDocument();
  });

  it("opens input form on click", () => {
    render(<DistributeButton athleteId="u1" athleteName="João" />, { wrapper: W });
    fireEvent.click(screen.getByText("Distribuir moedas"));
    expect(screen.getByPlaceholderText("Qtd")).toBeInTheDocument();
    expect(screen.getByText("Confirmar")).toBeInTheDocument();
    expect(screen.getByText("Cancelar")).toBeInTheDocument();
  });

  it("validates amount range client-side", async () => {
    render(<DistributeButton athleteId="u1" athleteName="João" />, { wrapper: W });
    fireEvent.click(screen.getByText("Distribuir moedas"));

    fireEvent.change(screen.getByPlaceholderText("Qtd"), {
      target: { value: "0" },
    });
    fireEvent.click(screen.getByText("Confirmar"));

    await waitFor(() => {
      expect(screen.getByText("Algo deu errado. Tente novamente.")).toBeInTheDocument();
    });
    expect(mockFetch).not.toHaveBeenCalled();
  });

  it("submits valid amount and shows success", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({ ok: true, amount: 10 }),
    });

    render(<DistributeButton athleteId="u1" athleteName="João" />, { wrapper: W });
    fireEvent.click(screen.getByText("Distribuir moedas"));

    fireEvent.change(screen.getByPlaceholderText("Qtd"), {
      target: { value: "10" },
    });
    fireEvent.click(screen.getByText("Confirmar"));

    await waitFor(() => {
      expect(mockFetch).toHaveBeenCalledWith(
        "/api/distribute-coins",
        expect.objectContaining({ method: "POST" }),
      );
    });
  });

  it("shows error on failed submission", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: false,
      json: async () => ({ error: "Créditos insuficientes" }),
    });

    render(<DistributeButton athleteId="u1" athleteName="João" />, { wrapper: W });
    fireEvent.click(screen.getByText("Distribuir moedas"));

    fireEvent.change(screen.getByPlaceholderText("Qtd"), {
      target: { value: "50" },
    });
    fireEvent.click(screen.getByText("Confirmar"));

    await waitFor(() => {
      expect(screen.getByText("Créditos insuficientes")).toBeInTheDocument();
    });
  });

  it("closes form on cancel", () => {
    render(<DistributeButton athleteId="u1" athleteName="João" />, { wrapper: W });
    fireEvent.click(screen.getByText("Distribuir moedas"));
    expect(screen.getByText("Confirmar")).toBeInTheDocument();

    fireEvent.click(screen.getByText("Cancelar"));
    expect(screen.getByText("Distribuir moedas")).toBeInTheDocument();
  });
});
