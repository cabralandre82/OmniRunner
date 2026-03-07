"use client";

import { useLocale } from "next-intl";
import { useRouter } from "next/navigation";
import { useState, useRef, useEffect } from "react";

const LOCALE_COOKIE = "portal_locale";
const COOKIE_MAX_AGE = 365 * 24 * 60 * 60; // 1 year

const LOCALES = [
  { value: "pt-BR", label: "PT" },
  { value: "en", label: "EN" },
] as const;

function setLocaleCookie(value: string) {
  document.cookie = `${LOCALE_COOKIE}=${value}; path=/; max-age=${COOKIE_MAX_AGE}; SameSite=Lax`;
}

export function LocaleSwitcher() {
  const locale = useLocale();
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function handleClickOutside(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        setOpen(false);
      }
    }
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  const currentLabel = LOCALES.find((l) => l.value === locale)?.label ?? "PT";

  function handleSelect(value: string) {
    if (value === locale) {
      setOpen(false);
      return;
    }
    setLocaleCookie(value);
    setOpen(false);
    router.refresh();
  }

  return (
    <div ref={ref} className="relative">
      <button
        type="button"
        onClick={() => setOpen((prev) => !prev)}
        className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-xs text-content-muted hover:bg-surface-elevated hover:text-content-primary transition-colors"
        title="Idioma / Language"
      >
        <svg
          className="h-4 w-4"
          fill="none"
          viewBox="0 0 24 24"
          strokeWidth={1.5}
          stroke="currentColor"
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            d="M10.5 21l5.25-11.25L21 21m-9-3h7.5M3 5.621a48.474 48.474 0 016-.371m0 0c1.12 0 2.233.038 3.334.114M9 5.25V3m3.334 2.364C11.176 10.658 7.69 15.08 3 17.502m9.334-12.138c.896.061 1.785.147 2.666.257m-4.589 8.495a18.023 18.023 0 01-3.827-5.802"
          />
        </svg>
        <span>Idioma: {currentLabel}</span>
        <svg
          className={`h-3.5 w-3.5 ml-auto transition-transform ${open ? "rotate-180" : ""}`}
          fill="none"
          viewBox="0 0 24 24"
          strokeWidth={2}
          stroke="currentColor"
        >
          <path strokeLinecap="round" strokeLinejoin="round" d="M19.5 8.25l-7.5 7.5-7.5-7.5" />
        </svg>
      </button>

      {open && (
        <div className="absolute bottom-full left-0 right-0 mb-1 rounded-lg border border-border bg-bg-primary shadow-lg overflow-hidden z-50">
          {LOCALES.map(({ value, label }) => (
            <button
              key={value}
              type="button"
              onClick={() => handleSelect(value)}
              className={`block w-full px-3 py-2 text-left text-xs font-medium transition-colors ${
                value === locale
                  ? "bg-brand-soft text-brand"
                  : "text-content-secondary hover:bg-surface-elevated hover:text-content-primary"
              }`}
            >
              {label === "PT" ? "Português" : "English"}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
