/**
 * @vitest-environment happy-dom
 */
import React from "react";
import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import "@testing-library/jest-dom/vitest";
import { StatusBadge } from "./status-badge";

describe("StatusBadge", () => {
  it("renders label text", () => {
    render(<StatusBadge label="Active" />);
    expect(screen.getByText("Active")).toBeInTheDocument();
  });

  it("applies success variant classes", () => {
    const { container } = render(<StatusBadge label="OK" variant="success" />);
    expect(container.firstElementChild!.className).toContain("text-success");
  });

  it("applies error variant classes", () => {
    const { container } = render(<StatusBadge label="Failed" variant="error" />);
    expect(container.firstElementChild!.className).toContain("text-error");
  });

  it("applies warning variant classes", () => {
    const { container } = render(<StatusBadge label="Pending" variant="warning" />);
    expect(container.firstElementChild!.className).toContain("text-warning");
  });

  it("defaults to neutral variant", () => {
    const { container } = render(<StatusBadge label="N/A" />);
    expect(container.firstElementChild!.className).toContain("text-content-secondary");
  });

  it("renders dot indicator when dot=true", () => {
    const { container } = render(<StatusBadge label="Online" variant="success" dot />);
    const dot = container.querySelector(".rounded-full.bg-success");
    expect(dot).not.toBeNull();
  });

  it("does not render dot when dot=false", () => {
    const { container } = render(<StatusBadge label="Offline" variant="error" />);
    const dot = container.querySelector(".rounded-full.bg-error");
    expect(dot).toBeNull();
  });
});
