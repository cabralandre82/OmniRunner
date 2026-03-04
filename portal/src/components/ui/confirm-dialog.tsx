"use client";

import { useRef, useEffect } from "react";
import { useTranslations } from "next-intl";

interface ConfirmDialogProps {
  open: boolean;
  title: string;
  description?: string;
  confirmLabel?: string;
  cancelLabel?: string;
  variant?: "danger" | "default";
  onConfirm: () => void;
  onCancel: () => void;
  loading?: boolean;
}

export function ConfirmDialog({
  open,
  title,
  description,
  confirmLabel,
  cancelLabel,
  variant = "default",
  onConfirm,
  onCancel,
  loading = false,
}: ConfirmDialogProps) {
  const t = useTranslations("common");
  const resolvedConfirmLabel = confirmLabel ?? t("confirm");
  const resolvedCancelLabel = cancelLabel ?? t("cancel");
  const dialogRef = useRef<HTMLDialogElement>(null);

  useEffect(() => {
    const el = dialogRef.current;
    if (!el) return;
    if (open && !el.open) el.showModal();
    if (!open && el.open) el.close();
  }, [open]);

  const confirmClass =
    variant === "danger"
      ? "bg-error text-white hover:brightness-110"
      : "bg-brand text-white hover:brightness-110";

  return (
    <dialog
      ref={dialogRef}
      onClose={onCancel}
      role="alertdialog"
      aria-labelledby="confirm-dialog-title"
      aria-describedby={description ? "confirm-dialog-desc" : undefined}
      className="w-full max-w-md rounded-xl border border-border bg-surface p-0 shadow-lg backdrop:bg-overlay"
    >
      <div className="p-6">
        <h2 id="confirm-dialog-title" className="text-lg font-semibold text-content-primary">{title}</h2>
        {description && (
          <p id="confirm-dialog-desc" className="mt-2 text-sm text-content-secondary">{description}</p>
        )}
        <div className="mt-6 flex justify-end gap-3">
          <button
            type="button"
            onClick={onCancel}
            disabled={loading}
            className="rounded-lg border border-border bg-surface px-4 py-2 text-sm font-medium text-content-secondary hover:bg-surface-elevated disabled:opacity-50 transition-colors"
          >
            {resolvedCancelLabel}
          </button>
          <button
            type="button"
            onClick={onConfirm}
            disabled={loading}
            className={`rounded-lg px-4 py-2 text-sm font-medium disabled:opacity-50 transition-all ${confirmClass}`}
          >
            {loading ? "..." : resolvedConfirmLabel}
          </button>
        </div>
      </div>
    </dialog>
  );
}
