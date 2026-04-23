"use client";

import { useState, useEffect, useCallback, useMemo } from "react";

import {
  buildFlowForRole,
  type CoachingRole,
  type OnboardingStepId,
} from "@/lib/onboarding-flows";

const STORAGE_KEY_PREFIX = "onboarding_completed";

export type { OnboardingStepId };

export interface OnboardingStepConfig {
  id: OnboardingStepId;
  targetSelector: string | null;
  title: string;
  description: string;
  icon: React.ReactNode;
}

/**
 * Resolve the per-role storage key so that a coach who gets
 * promoted to admin_master sees the longer tour again — each role
 * has its own completion flag. Missing role (null) falls back to
 * the legacy key so we don't re-run the tour for existing users.
 */
function storageKeyFor(role: CoachingRole | null): string {
  if (role === null) return STORAGE_KEY_PREFIX;
  return `${STORAGE_KEY_PREFIX}_${role}`;
}

export interface UseOnboardingOptions {
  /**
   * Role of the authenticated staff user. When provided, the
   * tour is filtered to steps visible for that role (L07-02).
   * Leave `null` to render the admin_master superset — only use
   * that for pages that sit above the role resolution (e.g. a
   * dedicated /onboarding page that runs before group selection).
   */
  role?: CoachingRole | null;
}

export function useOnboarding(options: UseOnboardingOptions = {}) {
  const role: CoachingRole | null = options.role ?? null;

  const flow = useMemo<ReadonlyArray<OnboardingStepId>>(
    () => (role ? buildFlowForRole(role) : buildFlowForRole("admin_master")),
    [role],
  );
  const totalSteps = flow.length;
  const storageKey = useMemo(() => storageKeyFor(role), [role]);

  const [currentStep, setCurrentStep] = useState(0);
  const [isCompleted, setIsCompleted] = useState(true);
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  useEffect(() => {
    if (!mounted || typeof window === "undefined") return;
    const completed = localStorage.getItem(storageKey) === "true";
    setIsCompleted(completed);
    if (!completed) setCurrentStep(0);
  }, [mounted, storageKey]);

  const complete = useCallback(() => {
    if (typeof window === "undefined") return;
    localStorage.setItem(storageKey, "true");
    setIsCompleted(true);
    setCurrentStep(0);
  }, [storageKey]);

  const next = useCallback(() => {
    setCurrentStep((prev) => {
      const nextStep = prev + 1;
      if (nextStep >= totalSteps) {
        complete();
        return prev;
      }
      return nextStep;
    });
  }, [complete, totalSteps]);

  const prev = useCallback(() => {
    setCurrentStep((prev) => Math.max(0, prev - 1));
  }, []);

  const skip = useCallback(() => {
    complete();
  }, [complete]);

  const reset = useCallback(() => {
    if (typeof window === "undefined") return;
    localStorage.removeItem(storageKey);
    setIsCompleted(false);
    setCurrentStep(0);
  }, [storageKey]);

  return {
    currentStep,
    totalSteps,
    flow,
    isCompleted,
    isActive: mounted && !isCompleted,
    next,
    prev,
    skip,
    complete,
    reset,
  };
}
