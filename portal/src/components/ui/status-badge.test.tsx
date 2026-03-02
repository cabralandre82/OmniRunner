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
    expect(container.firstElementChild!.className).toContain("text-green-700");
  });

  it("applies error variant classes", () => {
    const { container } = render(<StatusBadge label="Failed" variant="error" />);
    expect(container.firstElementChild!.className).toContain("text-red-700");
  });

  it("applies warning variant classes", () => {
    const { container } = render(<StatusBadge label="Pending" variant="warning" />);
    expect(container.firstElementChild!.className).toContain("text-yellow-700");
  });

  it("defaults to neutral variant", () => {
    const { container } = render(<StatusBadge label="N/A" />);
    expect(container.firstElementChild!.className).toContain("text-gray-700");
  });

  it("renders dot indicator when dot=true", () => {
    const { container } = render(<StatusBadge label="Online" variant="success" dot />);
    const dot = container.querySelector(".rounded-full.bg-green-500");
    expect(dot).not.toBeNull();
  });

  it("does not render dot when dot=false", () => {
    const { container } = render(<StatusBadge label="Offline" variant="error" />);
    const dot = container.querySelector(".rounded-full.bg-red-500");
    expect(dot).toBeNull();
  });
});
