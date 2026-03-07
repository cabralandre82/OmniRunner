"use client";

import { type ReactNode } from "react";

export interface OnboardingStepProps {
  title: string;
  description: string;
  icon: ReactNode;
  position?: "top" | "bottom" | "left" | "right" | "center";
  targetRect?: DOMRect | null;
}

export function OnboardingStep({
  title,
  description,
  icon,
  position = "center",
  targetRect,
}: OnboardingStepProps) {
  const isCentered = position === "center" || !targetRect;

  return (
    <div
      className="pointer-events-auto rounded-xl border border-border bg-surface-elevated p-5 shadow-lg transition-opacity duration-[var(--duration-normal)]"
      style={{
        maxWidth: "min(400px, 90vw)",
      }}
    >
      <div className="flex items-start gap-4">
        <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-brand-soft text-brand">
          {icon}
        </div>
        <div className="min-w-0 flex-1">
          <h3 className="text-base font-semibold text-content-primary">{title}</h3>
          <p className="mt-1.5 text-sm leading-relaxed text-content-secondary">
            {description}
          </p>
        </div>
      </div>
    </div>
  );
}
