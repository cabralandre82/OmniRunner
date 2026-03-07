"use client";

import { useState, useRef, useEffect, type ReactNode } from "react";

interface InfoTooltipProps {
  text: string;
  children?: ReactNode;
  className?: string;
}

export function InfoTooltip({ text, children, className = "" }: InfoTooltipProps) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    function close(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener("mousedown", close);
    return () => document.removeEventListener("mousedown", close);
  }, [open]);

  return (
    <span className={`relative inline-flex items-center ${className}`} ref={ref}>
      {children}
      <button
        type="button"
        aria-label="Mais informações"
        onClick={() => setOpen((v) => !v)}
        onMouseEnter={() => setOpen(true)}
        onMouseLeave={() => setOpen(false)}
        className="ml-1 inline-flex h-4 w-4 flex-shrink-0 items-center justify-center rounded-full bg-content-muted/20 text-content-muted transition-colors hover:bg-brand/20 hover:text-brand"
      >
        <svg viewBox="0 0 16 16" fill="currentColor" className="h-3 w-3">
          <path d="M8 1a7 7 0 1 0 0 14A7 7 0 0 0 8 1Zm-.75 3.5a.75.75 0 0 1 1.5 0v.5a.75.75 0 0 1-1.5 0v-.5ZM8 7a.75.75 0 0 1 .75.75v3.5a.75.75 0 0 1-1.5 0v-3.5A.75.75 0 0 1 8 7Z" />
        </svg>
      </button>
      {open && (
        <div
          role="tooltip"
          className="absolute bottom-full left-1/2 z-50 mb-2 w-64 -translate-x-1/2 rounded-lg border border-border bg-surface p-3 text-xs leading-relaxed text-content-secondary shadow-lg"
        >
          {text}
          <div className="absolute left-1/2 top-full -translate-x-1/2 border-4 border-transparent border-t-surface" />
        </div>
      )}
    </span>
  );
}
