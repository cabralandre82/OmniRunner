/**
 * @vitest-environment happy-dom
 */
import React from "react";
import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import "@testing-library/jest-dom/vitest";
import { BuyButton } from "./buy-button";

const mockFetch = vi.fn();
vi.stubGlobal("fetch", mockFetch);

describe("BuyButton", () => {
  beforeEach(() => vi.clearAllMocks());

  it("renders mercadopago as primary when preferred", () => {
    render(
      <BuyButton
        productId="p1"
        productName="Pack 50"
        preferredGateway="mercadopago"
      />,
    );
    expect(
      screen.getByText("Pagar com Pix, Cartão ou Boleto"),
    ).toBeInTheDocument();
    expect(
      screen.getByText(/pagar com cartão \(stripe\)/i),
    ).toBeInTheDocument();
  });

  it("renders stripe as primary when preferred", () => {
    render(
      <BuyButton
        productId="p1"
        productName="Pack 50"
        preferredGateway="stripe"
      />,
    );
    expect(screen.getByText("Pagar com Cartão (Stripe)")).toBeInTheDocument();
  });

  it("calls checkout API with preferred gateway on primary click", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({ checkout_url: "https://pay.example.com", ok: true }),
    });

    render(
      <BuyButton
        productId="p1"
        productName="Pack 50"
        preferredGateway="mercadopago"
      />,
    );

    fireEvent.click(screen.getByText("Pagar com Pix, Cartão ou Boleto"));

    await waitFor(() => {
      expect(mockFetch).toHaveBeenCalledWith("/api/checkout", expect.any(Object));
    });

    const body = JSON.parse(
      (mockFetch.mock.calls[0][1] as { body: string }).body,
    );
    expect(body.gateway).toBe("mercadopago");
    expect(body.product_id).toBe("p1");
  });

  it("shows error when checkout fails", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: false,
      json: async () => ({ error: "Product not found" }),
    });

    render(
      <BuyButton
        productId="p1"
        productName="Pack 50"
        preferredGateway="mercadopago"
      />,
    );

    fireEvent.click(screen.getByText("Pagar com Pix, Cartão ou Boleto"));

    await waitFor(() => {
      expect(screen.getByText("Product not found")).toBeInTheDocument();
    });
  });

  it("shows connection error on fetch failure", async () => {
    mockFetch.mockRejectedValueOnce(new Error("network error"));

    render(
      <BuyButton
        productId="p1"
        productName="Pack 50"
        preferredGateway="stripe"
      />,
    );

    fireEvent.click(screen.getByText("Pagar com Cartão (Stripe)"));

    await waitFor(() => {
      expect(screen.getByText("Erro de conexão")).toBeInTheDocument();
    });
  });
});
