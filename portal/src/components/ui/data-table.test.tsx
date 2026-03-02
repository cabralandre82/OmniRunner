/**
 * @vitest-environment happy-dom
 */
import { describe, it, expect } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { DataTable, type Column } from "./data-table";

interface TestRow {
  id: string;
  name: string;
  score: number;
}

const columns: Column<TestRow>[] = [
  { key: "name", header: "Nome", sortable: true, getValue: (r) => r.name },
  { key: "score", header: "Score", sortable: true, getValue: (r) => r.score },
];

const data: TestRow[] = [
  { id: "1", name: "Alice", score: 90 },
  { id: "2", name: "Bob", score: 80 },
  { id: "3", name: "Carol", score: 95 },
];

describe("DataTable", () => {
  it("renders all rows", () => {
    render(
      <DataTable columns={columns} data={data} keyExtractor={(r) => r.id} />,
    );
    expect(screen.getByText("Alice")).toBeDefined();
    expect(screen.getByText("Bob")).toBeDefined();
    expect(screen.getByText("Carol")).toBeDefined();
  });

  it("shows empty message when no data", () => {
    render(
      <DataTable
        columns={columns}
        data={[]}
        keyExtractor={(r) => r.id}
        emptyMessage="Nada aqui"
      />,
    );
    expect(screen.getByText("Nada aqui")).toBeDefined();
  });

  it("sorts by column on click", () => {
    render(
      <DataTable columns={columns} data={data} keyExtractor={(r) => r.id} />,
    );
    const header = screen.getByText("Score");
    fireEvent.click(header);
    const cells = screen.getAllByRole("cell");
    const scoreValues = cells
      .filter((_, i) => i % 2 === 1)
      .map((c) => c.textContent);
    expect(scoreValues).toEqual(["80", "90", "95"]);
  });

  it("filters with search", () => {
    render(
      <DataTable
        columns={columns}
        data={data}
        keyExtractor={(r) => r.id}
        searchable
        getSearchValue={(r) => r.name}
      />,
    );
    const input = screen.getByRole("textbox");
    fireEvent.change(input, { target: { value: "ali" } });
    expect(screen.getByText("Alice")).toBeDefined();
    expect(screen.queryByText("Bob")).toBeNull();
  });

  it("paginates correctly", () => {
    const bigData = Array.from({ length: 25 }, (_, i) => ({
      id: String(i),
      name: `User ${i}`,
      score: i,
    }));
    render(
      <DataTable
        columns={columns}
        data={bigData}
        keyExtractor={(r) => r.id}
        pageSize={10}
      />,
    );
    expect(screen.getByText("1 / 3")).toBeDefined();
    expect(screen.getByText("25 resultados")).toBeDefined();
    fireEvent.click(screen.getByText("Próximo"));
    expect(screen.getByText("2 / 3")).toBeDefined();
  });
});
