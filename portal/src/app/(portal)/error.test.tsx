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

import PortalError from "./error";

describe("PortalError boundary (L06-07)", () => {
  beforeEach(() => {
    reportSpy.mockClear();
  });

  it("forwards the error to reportClientError with boundary=portal", () => {
    const err = new Error("portal subtree crashed");
    render(<PortalError error={err} reset={() => {}} />);
    expect(reportSpy).toHaveBeenCalledWith({ error: err, boundary: "portal" });
  });

  it("renders the digest reference when provided", () => {
    const err = Object.assign(new Error("x"), { digest: "PORTAL-9" });
    render(<PortalError error={err} reset={() => {}} />);
    expect(screen.getByText(/PORTAL-9/)).toBeInTheDocument();
  });

  it("invokes reset when the retry button is clicked", () => {
    const reset = vi.fn();
    render(<PortalError error={new Error("x")} reset={reset} />);
    fireEvent.click(screen.getByRole("button", { name: /tentar novamente/i }));
    expect(reset).toHaveBeenCalledTimes(1);
  });
});
