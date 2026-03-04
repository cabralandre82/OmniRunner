/**
 * @vitest-environment happy-dom
 */
import { describe, it, expect, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import "@testing-library/jest-dom/vitest";
import {
  CopyPayloadButton,
  PublishButton,
  CreateBatchForm,
  GenerateItemsButton,
} from "./delivery-actions";

// Mock next/navigation
vi.mock("next/navigation", () => ({
  useRouter: () => ({ refresh: vi.fn() }),
}));

// Mock supabase client
vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({
    rpc: vi.fn().mockResolvedValue({ data: null, error: null }),
  }),
}));

describe("Delivery Actions", () => {
  describe("CopyPayloadButton", () => {
    it("renders 'Copiar Treino' text", () => {
      render(<CopyPayloadButton payload={{ foo: "bar" }} />);
      expect(screen.getByText("Copiar Treino")).toBeInTheDocument();
    });

    it("changes to 'Copiado!' after click", async () => {
      const writeText = vi.fn().mockResolvedValue(undefined);
      Object.defineProperty(navigator, "clipboard", {
        value: { writeText },
        configurable: true,
      });

      render(<CopyPayloadButton payload={{ foo: "bar" }} />);
      const button = screen.getByText("Copiar Treino");
      fireEvent.click(button);

      expect(writeText).toHaveBeenCalledWith('{\n  "foo": "bar"\n}');
      expect(await screen.findByText("Copiado!")).toBeInTheDocument();
    });
  });

  describe("PublishButton", () => {
    it("renders 'Marcar Publicado'", () => {
      render(<PublishButton itemId="test-item-id" />);
      expect(screen.getByText("Marcar Publicado")).toBeInTheDocument();
    });
  });

  describe("CreateBatchForm", () => {
    it("renders 'Criar Lote' button", () => {
      render(<CreateBatchForm groupId="test-group-id" />);
      expect(screen.getByRole("button", { name: "Criar Lote" })).toBeInTheDocument();
    });

    it("renders date inputs", () => {
      render(<CreateBatchForm groupId="test-group-id" />);
      expect(
        screen.getByLabelText("Início do período")
      ).toBeInTheDocument();
      expect(
        screen.getByLabelText("Fim do período")
      ).toBeInTheDocument();
    });
  });

  describe("GenerateItemsButton", () => {
    it("renders 'Gerar Itens'", () => {
      render(<GenerateItemsButton batchId="test-batch-id" />);
      expect(screen.getByText("Gerar Itens")).toBeInTheDocument();
    });
  });
});
