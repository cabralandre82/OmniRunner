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

import GlobalError from "./global-error";

describe("GlobalError boundary (L06-07)", () => {
  beforeEach(() => {
    reportSpy.mockClear();
  });

  it("forwards the error to reportClientError with boundary=global", () => {
    const err = new Error("root document blew up");
    render(<GlobalError error={err} reset={() => {}} />);
    expect(reportSpy).toHaveBeenCalledTimes(1);
    expect(reportSpy).toHaveBeenCalledWith({ error: err, boundary: "global" });
  });

  it("renders the digest when present so users can quote it to support", () => {
    const err = Object.assign(new Error("x"), { digest: "REF-123" });
    render(<GlobalError error={err} reset={() => {}} />);
    expect(screen.getByText(/REF-123/)).toBeInTheDocument();
  });

  it("invokes reset when the user clicks the retry button", () => {
    const reset = vi.fn();
    render(<GlobalError error={new Error("x")} reset={reset} />);
    fireEvent.click(screen.getByRole("button", { name: /tentar novamente/i }));
    expect(reset).toHaveBeenCalledTimes(1);
  });
});
