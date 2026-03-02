/**
 * @vitest-environment happy-dom
 */
import React from "react";
import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { RemoveButton } from "./remove-button";

const messages = {
  common: { remove: "Remover", loading: "Carregando..." },
  settings: { removeMember: "Remover membro" },
  error: { generic: "Algo deu errado. Tente novamente." },
};

function W({ children }: { children: React.ReactNode }) {
  return (
    <NextIntlClientProvider locale="pt-BR" messages={messages}>
      {children}
    </NextIntlClientProvider>
  );
}

const mockRefresh = vi.fn();
vi.mock("next/navigation", () => ({ useRouter: () => ({ refresh: mockRefresh }) }));

describe("RemoveButton", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
    mockRefresh.mockClear();
    vi.stubGlobal("confirm", vi.fn().mockReturnValue(true));
  });

  it("renders remove button", () => {
    render(<RemoveButton memberId="m1" memberName="Bob" />, { wrapper: W });
    expect(screen.getByRole("button")).toBeDefined();
  });

  it("calls confirm before removing", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ success: true }),
    }));

    render(<RemoveButton memberId="m1" memberName="Bob" />, { wrapper: W });
    fireEvent.click(screen.getByRole("button"));

    await waitFor(() => {
      expect(mockRefresh).toHaveBeenCalled();
    });
  });

  it("does nothing when confirm is cancelled", () => {
    vi.stubGlobal("confirm", vi.fn().mockReturnValue(false));
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);

    render(<RemoveButton memberId="m1" memberName="Bob" />, { wrapper: W });
    fireEvent.click(screen.getByRole("button"));

    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("shows error on failure", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: false,
      json: async () => ({ error: "Sem permissão" }),
    }));

    render(<RemoveButton memberId="m1" memberName="Bob" />, { wrapper: W });
    fireEvent.click(screen.getByRole("button"));

    await waitFor(() => {
      expect(screen.getByText("Sem permissão")).toBeDefined();
    });
  });
});
