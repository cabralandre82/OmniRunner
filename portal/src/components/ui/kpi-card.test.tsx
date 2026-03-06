/**
 * @vitest-environment happy-dom
 */
import React from "react";
import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import "@testing-library/jest-dom/vitest";
import { KpiCard } from "./kpi-card";

describe("KpiCard", () => {
  it("renders label and value", () => {
    render(<KpiCard label="Atletas" value={42} />);
    expect(screen.getByText("Atletas")).toBeInTheDocument();
    expect(screen.getByText("42")).toBeInTheDocument();
  });

  it("shows positive trend with + prefix", () => {
    render(<KpiCard label="Revenue" value="R$ 1.200" trend={15} trendLabel="vs last week" />);
    expect(screen.getByText("+15%")).toBeInTheDocument();
    expect(screen.getByText("vs last week")).toBeInTheDocument();
  });

  it("shows negative trend without + prefix", () => {
    render(<KpiCard label="Churn" value="3%" trend={-5} />);
    expect(screen.getByText("-5%")).toBeInTheDocument();
  });

  it("does not render trend section when trend is null", () => {
    const { container } = render(<KpiCard label="Static" value={100} />);
    expect(container.querySelector(".text-green-600")).toBeNull();
    expect(container.querySelector(".text-red-600")).toBeNull();
  });

  it("applies alert styling when alert is true", () => {
    const { container } = render(<KpiCard label="Low Credits" value={5} alert />);
    const card = container.firstElementChild!;
    expect(card.className).toContain("border-error/30");
    expect(card.className).toContain("bg-error-soft");
  });

  it("renders icon when provided", () => {
    render(<KpiCard label="Test" value={0} icon={<span data-testid="icon">I</span>} />);
    expect(screen.getByTestId("icon")).toBeInTheDocument();
  });
});
