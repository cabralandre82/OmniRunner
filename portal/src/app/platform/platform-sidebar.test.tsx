/**
 * @vitest-environment happy-dom
 */
import React from "react";
import { describe, it, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";

vi.mock("next/navigation", () => ({
  usePathname: () => "/platform",
}));
vi.mock("next/link", () => ({
  default: ({ children, href, ...props }: Record<string, unknown>) =>
    React.createElement("a", { href, ...props } as React.HTMLAttributes<HTMLAnchorElement>, children as React.ReactNode),
}));
vi.mock("@/lib/actions", () => ({
  signOut: vi.fn(),
}));

import { PlatformSidebar } from "./platform-sidebar";

describe("PlatformSidebar", () => {
  it("renders email", () => {
    render(<PlatformSidebar email="admin@omni.com" />);
    expect(screen.getAllByText("admin@omni.com").length).toBeGreaterThanOrEqual(1);
  });

  it("renders all nav links", () => {
    render(<PlatformSidebar email="admin@omni.com" />);
    const labels = [
      "Assessorias", "Financeiro", "Reembolsos", "Produtos",
      "Conquistas", "Liga", "Suporte", "Taxas", "Invariantes", "Feature Flags",
    ];
    for (const label of labels) {
      expect(screen.getAllByText(label).length).toBeGreaterThanOrEqual(1);
    }
  });

  it("renders logout button", () => {
    render(<PlatformSidebar email="admin@omni.com" />);
    expect(screen.getAllByText("Sair").length).toBeGreaterThanOrEqual(1);
  });

  it("renders back link to assessoria portal", () => {
    render(<PlatformSidebar email="admin@omni.com" />);
    expect(screen.getAllByText("← Portal Assessoria").length).toBeGreaterThanOrEqual(1);
  });
});
