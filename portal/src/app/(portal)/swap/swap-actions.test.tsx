/**
 * @vitest-environment happy-dom
 */
import { describe, it, expect } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { SwapActions } from "./swap-actions";
import { SWAP_MIN_AMOUNT_USD } from "@/lib/swap";

describe("SwapActions", () => {
  it("renders create button when no acceptOrderId", () => {
    render(<SwapActions groupId="g1" />);
    expect(screen.getByText("Criar Oferta de Venda")).toBeTruthy();
  });

  it("renders accept button when acceptOrderId is set", () => {
    render(<SwapActions groupId="g1" acceptOrderId="order-123" />);
    expect(screen.getByText("Comprar")).toBeTruthy();
  });

  it("opens create form", () => {
    render(<SwapActions groupId="g1" />);
    fireEvent.click(screen.getByText("Criar Oferta de Venda"));
    expect(screen.getByText("Vender Lastro")).toBeTruthy();
    expect(screen.getByPlaceholderText("5000")).toBeTruthy();
  });

  it("renders helper text with canonical min/max range (L05-07 lockstep)", () => {
    render(<SwapActions groupId="g1" />);
    fireEvent.click(screen.getByText("Criar Oferta de Venda"));
    expect(
      screen.getByText(
        new RegExp(`Mínimo US\\$ ${SWAP_MIN_AMOUNT_USD.toFixed(2)}`),
      ),
    ).toBeTruthy();
  });

  it("rejects amount below new floor (L05-07: US$ 10)", () => {
    render(<SwapActions groupId="g1" />);
    fireEvent.click(screen.getByText("Criar Oferta de Venda"));
    const input = screen.getByPlaceholderText("5000");
    fireEvent.change(input, { target: { value: "5" } });
    fireEvent.click(screen.getByText("Publicar"));
    expect(
      screen.getByText(`Valor mínimo: US$ ${SWAP_MIN_AMOUNT_USD.toFixed(2)}`),
    ).toBeTruthy();
  });

  it(
    "accepts amount at the new floor without showing minimum error " +
      "(L05-07: amateur clubs unblocked)",
    () => {
      render(<SwapActions groupId="g1" />);
      fireEvent.click(screen.getByText("Criar Oferta de Venda"));
      const input = screen.getByPlaceholderText("5000");
      fireEvent.change(input, {
        target: { value: String(SWAP_MIN_AMOUNT_USD) },
      });
      fireEvent.click(screen.getByText("Publicar"));
      expect(screen.queryByText(/Valor mínimo/)).toBeNull();
    },
  );

  it(
    "regression — value of 50 (was rejected pre-L05-07 when floor was " +
      "US$ 100) is now accepted",
    () => {
      render(<SwapActions groupId="g1" />);
      fireEvent.click(screen.getByText("Criar Oferta de Venda"));
      const input = screen.getByPlaceholderText("5000");
      fireEvent.change(input, { target: { value: "50" } });
      fireEvent.click(screen.getByText("Publicar"));
      expect(screen.queryByText(/Valor mínimo/)).toBeNull();
    },
  );

  it("closes create form on cancel", () => {
    render(<SwapActions groupId="g1" />);
    fireEvent.click(screen.getByText("Criar Oferta de Venda"));
    fireEvent.click(screen.getByText("Cancelar"));
    expect(screen.getByText("Criar Oferta de Venda")).toBeTruthy();
  });
});
