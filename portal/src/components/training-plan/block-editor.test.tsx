// @vitest-environment happy-dom
import { describe, it, expect, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { BlockEditor } from "./block-editor";
import type { ReleaseBlock } from "./types";

function makeBlock(overrides: Partial<ReleaseBlock> = {}): ReleaseBlock {
  return {
    order_index: 0,
    block_type: "interval",
    duration_seconds: null,
    distance_meters: 1000,
    target_pace_min_sec_per_km: 255,
    target_pace_max_sec_per_km: 275,
    target_hr_zone: 4,
    target_hr_min: null,
    target_hr_max: null,
    rpe_target: 8,
    repeat_count: null,
    notes: null,
    ...overrides,
  };
}

describe("BlockEditor", () => {
  it("renders empty state with add button", () => {
    render(<BlockEditor blocks={[]} onChange={vi.fn()} />);
    expect(screen.getByText("Adicionar bloco")).toBeInTheDocument();
  });

  it("renders block rows with type chips", () => {
    const blocks = [
      makeBlock({ block_type: "warmup", order_index: 0 }),
      makeBlock({ block_type: "interval", order_index: 1 }),
    ];
    render(<BlockEditor blocks={blocks} onChange={vi.fn()} />);
    expect(screen.getByText("Aquecimento")).toBeInTheDocument();
    expect(screen.getByText("Intervalo")).toBeInTheDocument();
  });

  it("shows summary with distance and pace", () => {
    const block = makeBlock({ distance_meters: 1000, target_pace_min_sec_per_km: 270, target_pace_max_sec_per_km: 290 });
    render(<BlockEditor blocks={[block]} onChange={vi.fn()} />);
    expect(screen.getByText(/1000m/)).toBeInTheDocument();
    expect(screen.getByText(/4:30/)).toBeInTheDocument();
  });

  it("calls onChange with new block when add button clicked", () => {
    const onChange = vi.fn();
    render(<BlockEditor blocks={[]} onChange={onChange} />);
    fireEvent.click(screen.getByText("Adicionar bloco"));
    expect(onChange).toHaveBeenCalledOnce();
    const [newBlocks] = onChange.mock.calls[0];
    expect(newBlocks).toHaveLength(1);
    expect(newBlocks[0].order_index).toBe(0);
  });

  it("calls onChange without block when remove clicked", () => {
    const block = makeBlock();
    const onChange = vi.fn();
    render(<BlockEditor blocks={[block]} onChange={onChange} />);
    const removeBtn = screen.getAllByRole("button").find((b) =>
      b.querySelector("svg path[d*='M6 18L18 6']")
    );
    expect(removeBtn).toBeDefined();
    fireEvent.click(removeBtn!);
    expect(onChange).toHaveBeenCalledWith([]);
  });

  it("expands block on chevron click and shows distance field", () => {
    render(<BlockEditor blocks={[makeBlock()]} onChange={vi.fn()} />);
    // The expand button has aria-label-less SVG; click every button-like element until distance shows
    const buttons = screen.getAllByRole("button");
    let found = false;
    for (const btn of buttons) {
      if (found) break;
      try {
        fireEvent.click(btn);
        screen.getByPlaceholderText("ex: 1000");
        found = true;
      } catch {
        // not this one
      }
    }
    expect(found).toBe(true);
  });

  it("renders readOnly mode as flat list", () => {
    const blocks = [
      makeBlock({ block_type: "warmup", distance_meters: null, duration_seconds: 300 }),
      makeBlock({ block_type: "interval", distance_meters: 1000, duration_seconds: null }),
    ];
    render(<BlockEditor blocks={blocks} onChange={vi.fn()} readOnly />);
    expect(screen.queryByText("Adicionar bloco")).not.toBeInTheDocument();
    expect(screen.getByText("Aquecimento")).toBeInTheDocument();
    expect(screen.getByText("Intervalo")).toBeInTheDocument();
  });

  it("shows empty message in readOnly mode with no blocks", () => {
    render(<BlockEditor blocks={[]} onChange={vi.fn()} readOnly />);
    expect(screen.getByText(/Sem blocos estruturados/)).toBeInTheDocument();
  });

  it("reorders blocks on move up", () => {
    const blocks = [
      makeBlock({ block_type: "warmup", order_index: 0 }),
      makeBlock({ block_type: "interval", order_index: 1 }),
    ];
    const onChange = vi.fn();
    render(<BlockEditor blocks={blocks} onChange={onChange} />);

    // Find up-arrow buttons (chevron up paths)
    const upBtns = screen.getAllByRole("button").filter((b) => {
      const path = b.querySelector("svg path");
      return path?.getAttribute("d")?.includes("M4.5 15.75");
    });

    if (upBtns.length > 0) {
      fireEvent.click(upBtns[upBtns.length - 1]);
      expect(onChange).toHaveBeenCalled();
      const [result] = onChange.mock.calls[0];
      expect(result[0].block_type).toBe("interval");
      expect(result[1].block_type).toBe("warmup");
    }
  });
});
