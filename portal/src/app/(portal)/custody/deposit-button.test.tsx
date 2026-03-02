/**
 * @vitest-environment happy-dom
 */
import { describe, it, expect } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { DepositButton } from "./deposit-button";

describe("DepositButton", () => {
  it("renders trigger button", () => {
    render(<DepositButton />);
    expect(screen.getByText("Depositar Lastro")).toBeTruthy();
  });

  it("opens form on click", () => {
    render(<DepositButton />);
    fireEvent.click(screen.getByText("Depositar Lastro"));
    expect(screen.getByText("Novo Depósito de Lastro")).toBeTruthy();
    expect(screen.getByPlaceholderText("1000")).toBeTruthy();
  });

  it("shows coin equivalence for valid amounts", () => {
    render(<DepositButton />);
    fireEvent.click(screen.getByText("Depositar Lastro"));
    const input = screen.getByPlaceholderText("1000");
    fireEvent.change(input, { target: { value: "500" } });
    expect(screen.getByText("500 coins")).toBeTruthy();
  });

  it("validates minimum amount", () => {
    render(<DepositButton />);
    fireEvent.click(screen.getByText("Depositar Lastro"));
    const input = screen.getByPlaceholderText("1000");
    fireEvent.change(input, { target: { value: "5" } });
    fireEvent.click(screen.getByText("Confirmar"));
    expect(screen.getByText("Valor mínimo: US$ 10.00")).toBeTruthy();
  });

  it("closes form on cancel", () => {
    render(<DepositButton />);
    fireEvent.click(screen.getByText("Depositar Lastro"));
    fireEvent.click(screen.getByText("Cancelar"));
    expect(screen.getByText("Depositar Lastro")).toBeTruthy();
  });

  it("has gateway selector", () => {
    render(<DepositButton />);
    fireEvent.click(screen.getByText("Depositar Lastro"));
    const select = screen.getByDisplayValue("Stripe");
    expect(select).toBeTruthy();
  });
});
