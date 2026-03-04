const VARIANT_CLASSES: Record<string, string> = {
  success: "bg-success-soft text-success ring-success/20",
  warning: "bg-warning-soft text-warning ring-warning/20",
  error: "bg-error-soft text-error ring-error/20",
  info: "bg-info-soft text-info ring-info/20",
  neutral: "bg-neutral-soft text-content-secondary ring-border/30",
};

const DOT_CLASSES: Record<string, string> = {
  success: "bg-success",
  warning: "bg-warning",
  error: "bg-error",
  info: "bg-info",
  neutral: "bg-content-muted",
};

interface StatusBadgeProps {
  label: string;
  variant?: keyof typeof VARIANT_CLASSES;
  dot?: boolean;
}

export function StatusBadge({
  label,
  variant = "neutral",
  dot = false,
}: StatusBadgeProps) {
  const classes = VARIANT_CLASSES[variant] ?? VARIANT_CLASSES.neutral;
  const dotClass = DOT_CLASSES[variant as string] ?? DOT_CLASSES.neutral;

  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-medium ring-1 ring-inset ${classes}`}
    >
      {dot && <span className={`h-1.5 w-1.5 rounded-full ${dotClass}`} />}
      {label}
    </span>
  );
}
