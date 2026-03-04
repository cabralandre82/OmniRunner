"use client";

import type { ButtonHTMLAttributes, ReactNode } from "react";

type Variant = "primary" | "secondary" | "ghost" | "danger";

interface ActionButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant;
  size?: "sm" | "md";
  icon?: ReactNode;
  loading?: boolean;
}

const variants: Record<Variant, string> = {
  primary:
    "bg-brand text-white hover:brightness-110 active:brightness-95 disabled:opacity-40",
  secondary:
    "border border-border bg-surface text-content-primary hover:bg-surface-elevated active:bg-bg-secondary disabled:opacity-40",
  ghost:
    "text-content-secondary hover:bg-surface-elevated hover:text-content-primary active:bg-bg-secondary disabled:opacity-40",
  danger:
    "bg-error text-white hover:brightness-110 active:brightness-95 disabled:opacity-40",
};

const sizes: Record<"sm" | "md", string> = {
  sm: "px-3 py-1.5 text-xs",
  md: "px-4 py-2 text-sm",
};

export function ActionButton({
  variant = "primary",
  size = "sm",
  icon,
  loading = false,
  children,
  className = "",
  disabled,
  ...props
}: ActionButtonProps) {
  return (
    <button
      disabled={disabled || loading}
      className={`inline-flex items-center justify-center gap-1.5 rounded-lg font-medium transition-all duration-fast ${variants[variant]} ${sizes[size]} ${className}`}
      {...props}
    >
      {loading ? (
        <svg
          className="h-3.5 w-3.5 animate-spin"
          fill="none"
          viewBox="0 0 24 24"
        >
          <circle
            className="opacity-25"
            cx="12"
            cy="12"
            r="10"
            stroke="currentColor"
            strokeWidth="4"
          />
          <path
            className="opacity-75"
            fill="currentColor"
            d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
          />
        </svg>
      ) : (
        icon
      )}
      {children}
    </button>
  );
}
