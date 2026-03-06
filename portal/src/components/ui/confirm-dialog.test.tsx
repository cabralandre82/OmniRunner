// @vitest-environment happy-dom
import { describe, it, expect, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { ConfirmDialog } from "./confirm-dialog";

const messages = {
  common: {
    confirm: "Confirmar",
    cancel: "Cancelar",
  },
};

function Wrapper({ children }: { children: React.ReactNode }) {
  return (
    <NextIntlClientProvider locale="pt-BR" messages={messages}>
      {children}
    </NextIntlClientProvider>
  );
}

describe("ConfirmDialog", () => {
  it("renders title and default labels", () => {
    render(
      <ConfirmDialog
        open={true}
        title="Tem certeza?"
        onConfirm={() => {}}
        onCancel={() => {}}
      />,
      { wrapper: Wrapper },
    );

    expect(screen.getByText("Tem certeza?")).toBeTruthy();
    expect(screen.getByText("Confirmar")).toBeTruthy();
    expect(screen.getByText("Cancelar")).toBeTruthy();
  });

  it("renders description when provided", () => {
    render(
      <ConfirmDialog
        open={true}
        title="Apagar?"
        description="Esta ação não pode ser desfeita."
        onConfirm={() => {}}
        onCancel={() => {}}
      />,
      { wrapper: Wrapper },
    );

    expect(screen.getByText("Esta ação não pode ser desfeita.")).toBeTruthy();
  });

  it("renders custom labels", () => {
    render(
      <ConfirmDialog
        open={true}
        title="Ação"
        confirmLabel="Sim, fazer"
        cancelLabel="Não, voltar"
        onConfirm={() => {}}
        onCancel={() => {}}
      />,
      { wrapper: Wrapper },
    );

    expect(screen.getByText("Sim, fazer")).toBeTruthy();
    expect(screen.getByText("Não, voltar")).toBeTruthy();
  });

  it("calls onConfirm when confirm button clicked", () => {
    const onConfirm = vi.fn();
    render(
      <ConfirmDialog
        open={true}
        title="Ação"
        onConfirm={onConfirm}
        onCancel={() => {}}
      />,
      { wrapper: Wrapper },
    );

    fireEvent.click(screen.getByText("Confirmar"));
    expect(onConfirm).toHaveBeenCalledOnce();
  });

  it("calls onCancel when cancel button clicked", () => {
    const onCancel = vi.fn();
    render(
      <ConfirmDialog
        open={true}
        title="Ação"
        onConfirm={() => {}}
        onCancel={onCancel}
      />,
      { wrapper: Wrapper },
    );

    fireEvent.click(screen.getByText("Cancelar"));
    expect(onCancel).toHaveBeenCalledOnce();
  });

  it("shows loading state", () => {
    render(
      <ConfirmDialog
        open={true}
        title="Ação"
        loading={true}
        onConfirm={() => {}}
        onCancel={() => {}}
      />,
      { wrapper: Wrapper },
    );

    expect(screen.getByText("...")).toBeTruthy();
  });

  it("applies danger styling for danger variant", () => {
    render(
      <ConfirmDialog
        open={true}
        title="Deletar"
        variant="danger"
        onConfirm={() => {}}
        onCancel={() => {}}
      />,
      { wrapper: Wrapper },
    );

    const confirmBtn = screen.getByText("Confirmar");
    expect(confirmBtn.className).toContain("bg-error");
  });
});
