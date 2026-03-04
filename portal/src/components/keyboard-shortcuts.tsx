"use client";

import { useEffect } from "react";
import { toast } from "sonner";

export function KeyboardShortcuts() {
  useEffect(() => {
    function handleKeyDown(e: KeyboardEvent) {
      if (e.key === "Escape") {
        const modals = document.querySelectorAll("[role='dialog'], [data-modal]");
        const openModal = Array.from(modals).find(
          (el) => el.getAttribute("aria-hidden") !== "true" && (el as HTMLElement).offsetParent != null
        );
        if (openModal) {
          const closeBtn = (openModal as HTMLElement).querySelector("[data-close], [aria-label*='fechar' i], [aria-label*='close' i]");
          if (closeBtn instanceof HTMLElement) closeBtn.click();
        }
      }

      if ((e.metaKey || e.ctrlKey) && e.key === "k") {
        e.preventDefault();
        const searchInput = document.querySelector<HTMLInputElement>(
          "input[type='search'], input[name='search'], [data-search-input], [aria-label*='busca' i], [aria-label*='search' i]"
        );
        if (searchInput) {
          searchInput.focus();
        } else {
          toast.info("Busca em breve");
        }
      }
    }

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, []);

  return null;
}
