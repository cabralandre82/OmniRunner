/**
 * @vitest-environment happy-dom
 */
import React from "react";
import { describe, it, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import "@testing-library/jest-dom/vitest";

let currentPathname = "/dashboard";

vi.mock("next/navigation", () => ({
  usePathname: () => currentPathname,
}));

vi.mock("next/link", () => ({
  default: ({
    href,
    children,
    ...rest
  }: {
    href: string;
    children: React.ReactNode;
    className?: string;
  }) => (
    <a href={href} {...rest}>
      {children}
    </a>
  ),
}));

import { Sidebar, SidebarTrigger } from "./sidebar";

describe("Sidebar", () => {
  it("renders group name", () => {
    render(<Sidebar role="admin_master" groupName="Running Pro" />);
    expect(screen.getAllByText("Running Pro")).toHaveLength(2);
  });

  it("shows default name when groupName is not provided", () => {
    render(<Sidebar role="admin_master" />);
    expect(screen.getAllByText("Omni Runner")).toHaveLength(2);
  });

  it("renders logo when logoUrl is provided", () => {
    render(
      <Sidebar role="admin_master" groupName="Test" logoUrl="https://example.com/logo.png" />,
    );
    expect(screen.getAllByAltText("Logo")).toHaveLength(2);
  });

  it("shows all nav items for admin_master", () => {
    currentPathname = "/financial";
    render(<Sidebar role="admin_master" groupName="Test" />);
    expect(screen.getAllByText("Dashboard")).toHaveLength(2); // desktop + mobile
    expect(screen.getAllByText("Saldo OmniCoins")).toHaveLength(2);
    expect(screen.getAllByText("Transferências OmniCoins")).toHaveLength(2);
  });

  it("hides custody/swap for coach", () => {
    currentPathname = "/clearing";
    render(<Sidebar role="coach" groupName="Test" />);
    expect(screen.queryByText("Saldo OmniCoins")).not.toBeInTheDocument();
    expect(screen.queryByText("Swap de Lastro")).not.toBeInTheDocument();
    expect(screen.getAllByText("Dashboard")).toHaveLength(2);
    expect(screen.getAllByText("Transferências OmniCoins")).toHaveLength(2);
  });

  it("hides custody, swap and distributions for assistant", () => {
    currentPathname = "/dashboard";
    render(<Sidebar role="assistant" groupName="Test" />);
    expect(screen.queryByText("Saldo OmniCoins")).not.toBeInTheDocument();
    expect(screen.queryByText("Swap de Lastro")).not.toBeInTheDocument();
    expect(screen.queryByText("Distribuir OmniCoins")).not.toBeInTheDocument();
    expect(screen.getAllByText("Dashboard")).toHaveLength(2);
  });

  it("shows platform admin link when isPlatformAdmin is true", () => {
    render(
      <Sidebar
        role="admin_master"
        isPlatformAdmin={true}
        groupName="Test"
      />,
    );
    expect(screen.getAllByText("Admin Plataforma")).toHaveLength(2);
  });

  it("does not show platform admin link by default", () => {
    render(<Sidebar role="admin_master" groupName="Test" />);
    expect(screen.queryByText("Admin Plataforma")).not.toBeInTheDocument();
  });

  it("displays role at the bottom", () => {
    render(<Sidebar role="coach" groupName="Test" />);
    expect(screen.getAllByText("Treinador")).toHaveLength(2);
  });
});

describe("SidebarTrigger", () => {
  it("renders the menu button with correct label", () => {
    render(<SidebarTrigger />);
    expect(screen.getByLabelText("Abrir menu")).toBeInTheDocument();
  });
});
