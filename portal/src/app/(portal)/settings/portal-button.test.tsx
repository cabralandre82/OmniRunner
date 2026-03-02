/**
 * @vitest-environment happy-dom
 */
import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { PortalButton } from "./portal-button";

vi.mock("next/navigation", () => ({ useRouter: () => ({ refresh: vi.fn() }) }));

describe("PortalButton", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it("renders button text", () => {
    render(<PortalButton />);
    expect(screen.getByRole("button")).toBeDefined();
  });

  it("shows error on failed response", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: false,
      json: async () => ({ error: "No subscription" }),
    }));

    render(<PortalButton />);
    fireEvent.click(screen.getByRole("button"));

    await waitFor(() => {
      expect(screen.getByText("No subscription")).toBeDefined();
    });
  });

  it("redirects to portal_url on success", async () => {
    const originalHref = window.location.href;
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ portal_url: "https://billing.example.com" }),
    }));

    render(<PortalButton />);
    fireEvent.click(screen.getByRole("button"));

    await waitFor(() => {
      expect(window.location.href).toContain("https://billing.example.com");
    });
  });
});
