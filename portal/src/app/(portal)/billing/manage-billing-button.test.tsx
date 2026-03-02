/**
 * @vitest-environment happy-dom
 */
import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { ManageBillingButton } from "./manage-billing-button";

vi.mock("next/navigation", () => ({ useRouter: () => ({ refresh: vi.fn() }) }));

describe("ManageBillingButton", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it("renders manage button", () => {
    render(<ManageBillingButton />);
    expect(screen.getByRole("button")).toBeDefined();
  });

  it("shows error when portal_url missing", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({}),
    }));

    render(<ManageBillingButton />);
    fireEvent.click(screen.getByRole("button"));

    await waitFor(() => {
      expect(screen.getByText("Erro ao abrir portal")).toBeDefined();
    });
  });

  it("redirects to portal on success", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ portal_url: "https://portal.stripe.com/123" }),
    }));

    render(<ManageBillingButton />);
    fireEvent.click(screen.getByRole("button"));

    await waitFor(() => {
      expect(window.location.href).toBe("https://portal.stripe.com/123");
    });
  });

  it("shows connection error on fetch failure", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("Network")));

    render(<ManageBillingButton />);
    fireEvent.click(screen.getByRole("button"));

    await waitFor(() => {
      expect(screen.getByText("Erro de conexão")).toBeDefined();
    });
  });
});
