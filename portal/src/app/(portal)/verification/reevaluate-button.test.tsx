/**
 * @vitest-environment happy-dom
 */
import React from "react";
import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import "@testing-library/jest-dom/vitest";
import { ReevaluateButton } from "./reevaluate-button";

const mockFetch = vi.fn();
vi.stubGlobal("fetch", mockFetch);

describe("ReevaluateButton", () => {
  beforeEach(() => vi.clearAllMocks());

  it("renders Reavaliar button", () => {
    render(<ReevaluateButton userId="u1" />);
    expect(screen.getByText("Reavaliar")).toBeInTheDocument();
  });

  it("calls verification API on click", async () => {
    mockFetch.mockResolvedValueOnce({ ok: true });

    render(<ReevaluateButton userId="u1" />);
    fireEvent.click(screen.getByText("Reavaliar"));

    await waitFor(() => {
      expect(mockFetch).toHaveBeenCalledWith(
        "/api/verification/evaluate",
        expect.objectContaining({ method: "POST" }),
      );
    });

    const body = JSON.parse(
      (mockFetch.mock.calls[0][1] as { body: string }).body,
    );
    expect(body.user_id).toBe("u1");
  });

  it("shows Feito on success", async () => {
    mockFetch.mockResolvedValueOnce({ ok: true });

    render(<ReevaluateButton userId="u1" />);
    fireEvent.click(screen.getByText("Reavaliar"));

    await waitFor(() => {
      expect(screen.getByText("Feito")).toBeInTheDocument();
    });
  });

  it("shows Erro on failure", async () => {
    mockFetch.mockResolvedValueOnce({ ok: false });

    render(<ReevaluateButton userId="u1" />);
    fireEvent.click(screen.getByText("Reavaliar"));

    await waitFor(() => {
      expect(screen.getByText("Erro")).toBeInTheDocument();
    });
  });

  it("shows Erro on network failure", async () => {
    mockFetch.mockRejectedValueOnce(new Error("offline"));

    render(<ReevaluateButton userId="u1" />);
    fireEvent.click(screen.getByText("Reavaliar"));

    await waitFor(() => {
      expect(screen.getByText("Erro")).toBeInTheDocument();
    });
  });
});
