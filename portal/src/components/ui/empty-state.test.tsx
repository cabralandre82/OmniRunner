/**
 * @vitest-environment happy-dom
 */
import React from "react";
import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import "@testing-library/jest-dom/vitest";
import { EmptyState } from "./empty-state";

describe("EmptyState", () => {
  it("renders title", () => {
    render(<EmptyState title="Nenhum atleta" />);
    expect(screen.getByText("Nenhum atleta")).toBeInTheDocument();
  });

  it("renders description when provided", () => {
    render(
      <EmptyState
        title="Sem dados"
        description="Adicione atletas para ver dados aqui"
      />,
    );
    expect(screen.getByText("Adicione atletas para ver dados aqui")).toBeInTheDocument();
  });

  it("does not render description when not provided", () => {
    const { container } = render(<EmptyState title="Empty" />);
    const paragraphs = container.querySelectorAll("p");
    expect(paragraphs.length).toBe(0);
  });

  it("renders icon when provided", () => {
    render(
      <EmptyState
        title="No items"
        icon={<span data-testid="custom-icon">X</span>}
      />,
    );
    expect(screen.getByTestId("custom-icon")).toBeInTheDocument();
  });

  it("renders action when provided", () => {
    render(
      <EmptyState
        title="No items"
        action={<button>Add Item</button>}
      />,
    );
    expect(screen.getByRole("button", { name: "Add Item" })).toBeInTheDocument();
  });
});
