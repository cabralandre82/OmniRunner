/**
 * @vitest-environment happy-dom
 */
import { describe, it, expect } from "vitest";
import { render } from "@testing-library/react";
import { Skeleton, KpiCardSkeleton, TableRowSkeleton, PageSkeleton } from "./loading-skeleton";

describe("Skeleton", () => {
  it("renders with aria-hidden", () => {
    const { container } = render(<Skeleton />);
    const el = container.firstChild as HTMLElement;
    expect(el.getAttribute("aria-hidden")).toBe("true");
  });

  it("applies custom className", () => {
    const { container } = render(<Skeleton className="h-8 w-32" />);
    const el = container.firstChild as HTMLElement;
    expect(el.className).toContain("h-8");
    expect(el.className).toContain("w-32");
  });

  it("has animate-pulse class", () => {
    const { container } = render(<Skeleton />);
    const el = container.firstChild as HTMLElement;
    expect(el.className).toContain("animate-pulse");
  });
});

describe("KpiCardSkeleton", () => {
  it("renders three skeleton elements", () => {
    const { container } = render(<KpiCardSkeleton />);
    const skeletons = container.querySelectorAll("[aria-hidden]");
    expect(skeletons.length).toBe(3);
  });
});

describe("TableRowSkeleton", () => {
  it("renders correct number of columns", () => {
    const { container } = render(
      <table><tbody><TableRowSkeleton cols={6} /></tbody></table>,
    );
    const cells = container.querySelectorAll("td");
    expect(cells.length).toBe(6);
  });

  it("defaults to 4 columns", () => {
    const { container } = render(
      <table><tbody><TableRowSkeleton /></tbody></table>,
    );
    const cells = container.querySelectorAll("td");
    expect(cells.length).toBe(4);
  });
});

describe("PageSkeleton", () => {
  it("renders with KPI skeletons", () => {
    const { container } = render(<PageSkeleton />);
    const skeletons = container.querySelectorAll("[aria-hidden]");
    expect(skeletons.length).toBeGreaterThan(10);
  });
});
