/**
 * @vitest-environment happy-dom
 */
import React from "react";
import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { InviteForm } from "./invite-form";

const messages = {
  common: { invite: "Convidar", loading: "Carregando..." },
  settings: { inviteMember: "Convidar membro" },
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

describe("InviteForm", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
    mockRefresh.mockClear();
  });

  it("renders email input and role select", () => {
    render(<InviteForm />, { wrapper: W });
    expect(screen.getByPlaceholderText("email@exemplo.com")).toBeDefined();
  });

  it("submits invite successfully", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ success: true }),
    }));

    render(<InviteForm />, { wrapper: W });
    const input = screen.getByPlaceholderText("email@exemplo.com");
    fireEvent.change(input, { target: { value: "test@test.com" } });
    fireEvent.submit(input.closest("form")!);

    await waitFor(() => {
      expect(screen.getByText(/test@test.com adicionado/)).toBeDefined();
    });
  });

  it("shows error on failure", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: false,
      json: async () => ({ error: "E-mail já convidado" }),
    }));

    render(<InviteForm />, { wrapper: W });
    const input = screen.getByPlaceholderText("email@exemplo.com");
    fireEvent.change(input, { target: { value: "dup@test.com" } });
    fireEvent.submit(input.closest("form")!);

    await waitFor(() => {
      expect(screen.getByText("E-mail já convidado")).toBeDefined();
    });
  });
});
