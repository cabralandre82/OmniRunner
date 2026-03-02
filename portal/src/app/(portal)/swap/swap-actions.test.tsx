/**
 * @vitest-environment happy-dom
 */
import { describe, it, expect } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { SwapActions } from "./swap-actions";

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

  it("validates minimum amount", () => {
    render(<SwapActions groupId="g1" />);
    fireEvent.click(screen.getByText("Criar Oferta de Venda"));
    const input = screen.getByPlaceholderText("5000");
    fireEvent.change(input, { target: { value: "50" } });
    fireEvent.click(screen.getByText("Publicar"));
    expect(screen.getByText("Valor mínimo: US$ 100.00")).toBeTruthy();
  });

  it("closes create form on cancel", () => {
    render(<SwapActions groupId="g1" />);
    fireEvent.click(screen.getByText("Criar Oferta de Venda"));
    fireEvent.click(screen.getByText("Cancelar"));
    expect(screen.getByText("Criar Oferta de Venda")).toBeTruthy();
  });
});
