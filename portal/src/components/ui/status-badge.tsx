const VARIANT_CLASSES: Record<string, string> = {
  success: "bg-green-50 text-green-700 ring-green-600/20",
  warning: "bg-yellow-50 text-yellow-700 ring-yellow-600/20",
  error: "bg-red-50 text-red-700 ring-red-600/20",
  info: "bg-blue-50 text-blue-700 ring-blue-600/20",
  neutral: "bg-gray-50 text-gray-700 ring-gray-600/20",
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

  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-medium ring-1 ring-inset ${classes}`}
    >
      {dot && (
        <span
          className={`h-1.5 w-1.5 rounded-full ${
            variant === "success"
              ? "bg-green-500"
              : variant === "warning"
                ? "bg-yellow-500"
                : variant === "error"
                  ? "bg-red-500"
                  : variant === "info"
                    ? "bg-blue-500"
                    : "bg-gray-500"
          }`}
        />
      )}
      {label}
    </span>
  );
}
