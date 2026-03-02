/**
 * @vitest-environment happy-dom
 */
import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { DashboardCharts } from "./dashboard-charts";

const mockBreakdown = [
  { label: "Dom", date: "22/02", sessions: 5 },
  { label: "Seg", date: "23/02", sessions: 12 },
  { label: "Ter", date: "24/02", sessions: 8 },
  { label: "Qua", date: "25/02", sessions: 15 },
  { label: "Qui", date: "26/02", sessions: 10 },
  { label: "Sex", date: "27/02", sessions: 6 },
  { label: "Sáb", date: "28/02", sessions: 3 },
];

describe("DashboardCharts", () => {
  it("renders trend section", () => {
    render(<DashboardCharts dailyBreakdown={mockBreakdown} />);
    expect(screen.getByText("Tendência — Corridas (7d)")).toBeTruthy();
  });

  it("renders bar chart section", () => {
    render(<DashboardCharts dailyBreakdown={mockBreakdown} />);
    expect(screen.getByText("Corridas por Dia")).toBeTruthy();
  });

  it("shows date range", () => {
    render(<DashboardCharts dailyBreakdown={mockBreakdown} />);
    expect(screen.getByText("22/02")).toBeTruthy();
    expect(screen.getByText("28/02")).toBeTruthy();
  });

  it("renders SVG sparkline", () => {
    const { container } = render(<DashboardCharts dailyBreakdown={mockBreakdown} />);
    const svgs = container.querySelectorAll("svg");
    expect(svgs.length).toBeGreaterThanOrEqual(1);
  });
});
