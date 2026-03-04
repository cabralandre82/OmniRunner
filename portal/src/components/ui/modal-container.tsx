"use client";

import { useRef, useEffect, type ReactNode } from "react";

interface ModalContainerProps {
  open: boolean;
  onClose: () => void;
  title: string;
  description?: string;
  children: ReactNode;
  size?: "sm" | "md" | "lg";
}

const sizeClasses: Record<"sm" | "md" | "lg", string> = {
  sm: "max-w-sm",
  md: "max-w-md",
  lg: "max-w-lg",
};

export function ModalContainer({
  open,
  onClose,
  title,
  description,
  children,
  size = "md",
}: ModalContainerProps) {
  const dialogRef = useRef<HTMLDialogElement>(null);

  useEffect(() => {
    const el = dialogRef.current;
    if (!el) return;
    if (open && !el.open) el.showModal();
    if (!open && el.open) el.close();
  }, [open]);

  return (
    <dialog
      ref={dialogRef}
      onClose={onClose}
      className={`w-full ${sizeClasses[size]} rounded-xl border border-border bg-surface p-0 shadow-lg backdrop:bg-overlay`}
    >
      <div className="p-6">
        <h2 className="text-lg font-semibold text-content-primary">{title}</h2>
        {description && (
          <p className="mt-1 text-sm text-content-secondary">{description}</p>
        )}
        <div className="mt-5">{children}</div>
      </div>
    </dialog>
  );
}
