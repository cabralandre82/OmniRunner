"use client";

import { usePathname } from "next/navigation";
import { PageTransition } from "@/components/ui/page-transition";
import { type ReactNode } from "react";

export function PageWrapper({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  return (
    <PageTransition key={pathname}>
      {children}
    </PageTransition>
  );
}
