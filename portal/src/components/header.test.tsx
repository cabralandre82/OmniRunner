/**
 * @vitest-environment happy-dom
 */
import React from "react";
import { describe, it, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import "@testing-library/jest-dom/vitest";

vi.mock("next/navigation", () => ({
  usePathname: () => "/dashboard",
}));

vi.mock("next/link", () => ({
  default: ({
    href,
    children,
    ...rest
  }: {
    href: string;
    children: React.ReactNode;
  }) => (
    <a href={href} {...rest}>
      {children}
    </a>
  ),
}));

vi.mock("@/lib/actions", () => ({
  signOut: vi.fn(),
  clearPortalGroup: vi.fn(),
}));

import { Header } from "./header";

describe("Header", () => {
  it("renders group name", () => {
    render(
      <Header groupName="Assessoria X" userEmail="admin@x.com" multiGroup={false} />,
    );
    expect(screen.getByText("Assessoria X")).toBeInTheDocument();
  });

  it("renders user email", () => {
    render(
      <Header groupName="Test" userEmail="user@test.com" multiGroup={false} />,
    );
    expect(screen.getByText("user@test.com")).toBeInTheDocument();
  });

  it("renders logout button", () => {
    render(
      <Header groupName="Test" userEmail="a@b.com" multiGroup={false} />,
    );
    expect(screen.getByText("Sair")).toBeInTheDocument();
  });

  it("shows trocar button when multiGroup is true", () => {
    render(
      <Header groupName="Test" userEmail="a@b.com" multiGroup={true} />,
    );
    expect(screen.getByText("trocar")).toBeInTheDocument();
  });

  it("does not show trocar button when multiGroup is false", () => {
    render(
      <Header groupName="Test" userEmail="a@b.com" multiGroup={false} />,
    );
    expect(screen.queryByText("trocar")).not.toBeInTheDocument();
  });
});
