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
    render(<Sidebar role="admin_master" groupName="Test" />);
    expect(screen.getAllByText("Dashboard")).toHaveLength(2); // desktop + mobile
    expect(screen.getAllByText("Custódia")).toHaveLength(2);
    expect(screen.getAllByText("Compensações")).toHaveLength(2);
    expect(screen.getAllByText("Swap de Lastro")).toHaveLength(2);
  });

  it("hides custody/swap for professor", () => {
    render(<Sidebar role="professor" groupName="Test" />);
    expect(screen.queryByText("Custódia")).not.toBeInTheDocument();
    expect(screen.queryByText("Swap de Lastro")).not.toBeInTheDocument();
    expect(screen.getAllByText("Dashboard")).toHaveLength(2);
    expect(screen.getAllByText("Compensações")).toHaveLength(2);
  });

  it("hides custody, swap and distributions for assistente", () => {
    render(<Sidebar role="assistente" groupName="Test" />);
    expect(screen.queryByText("Custódia")).not.toBeInTheDocument();
    expect(screen.queryByText("Swap de Lastro")).not.toBeInTheDocument();
    expect(screen.queryByText("Distribuições")).not.toBeInTheDocument();
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
    render(<Sidebar role="professor" groupName="Test" />);
    expect(screen.getAllByText("professor")).toHaveLength(2);
  });
});

describe("SidebarTrigger", () => {
  it("renders the menu button with correct label", () => {
    render(<SidebarTrigger />);
    expect(screen.getByLabelText("Abrir menu")).toBeInTheDocument();
  });
});
