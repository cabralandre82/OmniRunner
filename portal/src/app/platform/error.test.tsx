/**
 * @vitest-environment happy-dom
 */
import React from "react";
import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";

const reportSpy = vi.hoisted(() => vi.fn());

vi.mock("@/lib/observability/reportClientError", () => ({
  reportClientError: reportSpy,
}));

import PlatformError from "./error";

const messages = {
  common: { retry: "Tentar novamente" },
  error: { generic: "Algo deu errado. Tente novamente." },
};

function W({ children }: { children: React.ReactNode }) {
  return (
    <NextIntlClientProvider locale="pt-BR" messages={messages}>
      {children}
    </NextIntlClientProvider>
  );
}

describe("PlatformError boundary (L06-07)", () => {
  beforeEach(() => {
    reportSpy.mockClear();
  });

  it("forwards the error to reportClientError with boundary=platform", () => {
    const err = new Error("admin area crashed");
    render(<PlatformError error={err} reset={() => {}} />, { wrapper: W });
    expect(reportSpy).toHaveBeenCalledWith({ error: err, boundary: "platform" });
  });

  it("renders the digest reference when provided", () => {
    const err = Object.assign(new Error("x"), { digest: "PLAT-42" });
    render(<PlatformError error={err} reset={() => {}} />, { wrapper: W });
    expect(screen.getByText(/PLAT-42/)).toBeInTheDocument();
  });

  it("invokes reset when the retry button is clicked", () => {
    const reset = vi.fn();
    render(<PlatformError error={new Error("x")} reset={reset} />, { wrapper: W });
    fireEvent.click(screen.getByRole("button", { name: /tentar novamente/i }));
    expect(reset).toHaveBeenCalledTimes(1);
  });
});
