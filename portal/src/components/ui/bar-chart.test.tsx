/**
 * @vitest-environment happy-dom
 */
import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { BarChart } from "./bar-chart";

describe("BarChart", () => {
  const data = [
    { label: "Club A", value: 100 },
    { label: "Club B", value: 60 },
    { label: "Club C", value: 30 },
  ];

  it("renders all bars", () => {
    render(<BarChart data={data} />);
    expect(screen.getByText("Club A")).toBeTruthy();
    expect(screen.getByText("Club B")).toBeTruthy();
    expect(screen.getByText("Club C")).toBeTruthy();
  });

  it("shows formatted values", () => {
    render(<BarChart data={data} formatValue={(v) => `${v} coins`} />);
    expect(screen.getByText("100 coins")).toBeTruthy();
    expect(screen.getByText("60 coins")).toBeTruthy();
  });

  it("handles empty data", () => {
    const { container } = render(<BarChart data={[]} />);
    expect(container.querySelector("[role=img]")).toBeTruthy();
  });

  it("max bar width is 100%", () => {
    const { container } = render(<BarChart data={[{ label: "A", value: 50 }]} />);
    const bar = container.querySelector(".rounded-full.transition-all");
    expect(bar?.getAttribute("style")).toContain("100%");
  });
});
