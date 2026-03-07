"use client";

import { useState, useEffect, useCallback } from "react";

const STORAGE_KEY = "onboarding_completed";
const TOTAL_STEPS = 10;

export type OnboardingStepId =
  | "welcome"
  | "dashboard"
  | "athletes"
  | "training"
  | "financial"
  | "custody"
  | "clearing"
  | "distributions"
  | "help"
  | "settings";

export interface OnboardingStepConfig {
  id: OnboardingStepId;
  targetSelector: string | null;
  title: string;
  description: string;
  icon: React.ReactNode;
}

export function useOnboarding() {
  const [currentStep, setCurrentStep] = useState(0);
  const [isCompleted, setIsCompleted] = useState(true);
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  useEffect(() => {
    if (!mounted || typeof window === "undefined") return;
    const completed = localStorage.getItem(STORAGE_KEY) === "true";
    setIsCompleted(completed);
    if (!completed) setCurrentStep(0);
  }, [mounted]);

  const complete = useCallback(() => {
    if (typeof window === "undefined") return;
    localStorage.setItem(STORAGE_KEY, "true");
    setIsCompleted(true);
    setCurrentStep(0);
  }, []);

  const next = useCallback(() => {
    setCurrentStep((prev) => {
      const nextStep = prev + 1;
      if (nextStep >= TOTAL_STEPS) {
        complete();
        return prev;
      }
      return nextStep;
    });
  }, [complete]);

  const prev = useCallback(() => {
    setCurrentStep((prev) => Math.max(0, prev - 1));
  }, []);

  const skip = useCallback(() => {
    complete();
  }, [complete]);

  const reset = useCallback(() => {
    if (typeof window === "undefined") return;
    localStorage.removeItem(STORAGE_KEY);
    setIsCompleted(false);
    setCurrentStep(0);
  }, []);

  return {
    currentStep,
    totalSteps: TOTAL_STEPS,
    isCompleted,
    isActive: mounted && !isCompleted,
    next,
    prev,
    skip,
    complete,
    reset,
  };
}
