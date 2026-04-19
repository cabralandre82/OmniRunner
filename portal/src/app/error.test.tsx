/**
 * @vitest-environment happy-dom
 */
import React from "react";
import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";

const reportSpy = vi.hoisted(() => vi.fn());

vi.mock("@/lib/observability/reportClientError", () => ({
  reportClientError: reportSpy,
}));

import RootError from "./error";

describe("RootError boundary (L06-07)", () => {
  beforeEach(() => {
    reportSpy.mockClear();
  });

  it("forwards the error to reportClientError with boundary=root", () => {
    const err = new Error("root layout subtree crashed");
    render(<RootError error={err} reset={() => {}} />);
    expect(reportSpy).toHaveBeenCalledWith({ error: err, boundary: "root" });
  });

  it("renders the digest reference when provided", () => {
    const err = Object.assign(new Error("x"), { digest: "ROOT-1" });
    render(<RootError error={err} reset={() => {}} />);
    expect(screen.getByText(/ROOT-1/)).toBeInTheDocument();
  });

  it("invokes reset when the retry button is clicked", () => {
    const reset = vi.fn();
    render(<RootError error={new Error("x")} reset={reset} />);
    fireEvent.click(screen.getByRole("button", { name: /tentar novamente/i }));
    expect(reset).toHaveBeenCalledTimes(1);
  });
});
