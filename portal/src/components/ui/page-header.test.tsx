// @vitest-environment happy-dom
import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { PageHeader } from "./page-header";

describe("PageHeader", () => {
  it("renders title", () => {
    render(<PageHeader title="Dashboard" />);
    expect(screen.getByText("Dashboard")).toBeTruthy();
  });

  it("renders description when provided", () => {
    render(
      <PageHeader title="Atletas" description="Gerencie seus atletas" />
    );
    expect(screen.getByText("Gerencie seus atletas")).toBeTruthy();
  });

  it("does not render description when omitted", () => {
    render(<PageHeader title="Settings" />);
    expect(screen.queryByText("Gerencie")).toBeNull();
  });

  it("renders action slot", () => {
    render(
      <PageHeader
        title="Créditos"
        actions={<button>Comprar</button>}
      />
    );
    expect(screen.getByText("Comprar")).toBeTruthy();
  });
});
