/**
 * @vitest-environment happy-dom
 */
import { describe, it, expect } from "vitest";
import { render } from "@testing-library/react";
import { Sparkline } from "./sparkline";

describe("Sparkline", () => {
  it("renders SVG with correct dimensions", () => {
    const { container } = render(<Sparkline data={[10, 20, 15, 30]} width={200} height={50} />);
    const svg = container.querySelector("svg");
    expect(svg).toBeTruthy();
    expect(svg?.getAttribute("width")).toBe("200");
    expect(svg?.getAttribute("height")).toBe("50");
  });

  it("renders paths for valid data", () => {
    const { container } = render(<Sparkline data={[5, 10, 3, 8]} />);
    const paths = container.querySelectorAll("path");
    expect(paths.length).toBe(2);
  });

  it("renders dash for insufficient data", () => {
    const { container } = render(<Sparkline data={[5]} />);
    const text = container.querySelector("text");
    expect(text?.textContent).toBe("—");
  });

  it("renders endpoint dot", () => {
    const { container } = render(<Sparkline data={[1, 2, 3]} />);
    const circle = container.querySelector("circle");
    expect(circle).toBeTruthy();
  });

  it("applies custom color", () => {
    const { container } = render(<Sparkline data={[1, 2, 3]} color="#ef4444" />);
    const stroke = container.querySelector("path:last-of-type");
    expect(stroke?.getAttribute("stroke")).toBe("#ef4444");
  });

  it("has accessible aria-label", () => {
    const { container } = render(<Sparkline data={[1, 2]} label="Revenue trend" />);
    const svg = container.querySelector("svg");
    expect(svg?.getAttribute("aria-label")).toBe("Revenue trend");
  });
});
