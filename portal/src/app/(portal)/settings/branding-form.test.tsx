/**
 * @vitest-environment happy-dom
 */
import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import { BrandingForm } from "./branding-form";

vi.mock("next/navigation", () => ({ useRouter: () => ({ refresh: vi.fn() }) }));

describe("BrandingForm", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it("loads branding data on mount", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        logo_url: null,
        primary_color: "#2563eb",
        sidebar_bg: "#ffffff",
        sidebar_text: "#111827",
        accent_color: "#2563eb",
      }),
    }));

    render(<BrandingForm />);

    await waitFor(() => {
      expect(screen.queryByText(/Carregando/i)).toBeNull();
    });
  });

  it("renders preset buttons", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        logo_url: null,
        primary_color: "#2563eb",
        sidebar_bg: "#ffffff",
        sidebar_text: "#111827",
        accent_color: "#2563eb",
      }),
    }));

    render(<BrandingForm />);

    await waitFor(() => {
      expect(screen.getByText("Padrão")).toBeDefined();
      expect(screen.getByText("Escuro")).toBeDefined();
    });
  });
});
