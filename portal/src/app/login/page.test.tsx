/**
 * @vitest-environment happy-dom
 */
import React from "react";
import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import "@testing-library/jest-dom/vitest";

const mockPush = vi.fn();
const mockRefresh = vi.fn();

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: mockPush, refresh: mockRefresh }),
  useSearchParams: () => ({
    get: (key: string) => (key === "next" ? "/dashboard" : null),
  }),
}));

const mockSignInWithPassword = vi.fn();
const mockSignInWithOAuth = vi.fn();

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({
    auth: {
      signInWithPassword: mockSignInWithPassword,
      signInWithOAuth: mockSignInWithOAuth,
    },
  }),
}));

const { default: LoginPage } = await import("./page");

describe("LoginPage", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("renders login form with email and password fields", () => {
    render(<LoginPage />);
    expect(screen.getByText("Omni Runner")).toBeInTheDocument();
    expect(screen.getByText("Portal da Assessoria")).toBeInTheDocument();
    expect(screen.getByLabelText("E-mail")).toBeInTheDocument();
    expect(screen.getByLabelText("Senha")).toBeInTheDocument();
  });

  it("renders social login buttons", () => {
    render(<LoginPage />);
    expect(screen.getByText("Entrar com Google")).toBeInTheDocument();
    expect(screen.getByText("Entrar com Apple")).toBeInTheDocument();
  });

  it("renders email submit button", () => {
    render(<LoginPage />);
    expect(screen.getByText("Entrar com e-mail")).toBeInTheDocument();
  });

  it("shows error on failed email login", async () => {
    mockSignInWithPassword.mockResolvedValueOnce({
      error: { message: "Invalid credentials" },
    });

    render(<LoginPage />);

    fireEvent.change(screen.getByLabelText("E-mail"), {
      target: { value: "test@test.com" },
    });
    fireEvent.change(screen.getByLabelText("Senha"), {
      target: { value: "wrong" },
    });
    fireEvent.click(screen.getByText("Entrar com e-mail"));

    await waitFor(() => {
      expect(screen.getByText("E-mail ou senha inválidos")).toBeInTheDocument();
    });
  });

  it("redirects on successful email login", async () => {
    mockSignInWithPassword.mockResolvedValueOnce({ error: null });

    render(<LoginPage />);

    fireEvent.change(screen.getByLabelText("E-mail"), {
      target: { value: "test@test.com" },
    });
    fireEvent.change(screen.getByLabelText("Senha"), {
      target: { value: "correct" },
    });
    fireEvent.click(screen.getByText("Entrar com e-mail"));

    await waitFor(() => {
      expect(mockPush).toHaveBeenCalledWith("/dashboard");
      expect(mockRefresh).toHaveBeenCalled();
    });
  });

  it("triggers Google OAuth on button click", async () => {
    mockSignInWithOAuth.mockResolvedValueOnce({ error: null });

    render(<LoginPage />);
    fireEvent.click(screen.getByText("Entrar com Google"));

    await waitFor(() => {
      expect(mockSignInWithOAuth).toHaveBeenCalledWith(
        expect.objectContaining({ provider: "google" }),
      );
    });
  });
});
