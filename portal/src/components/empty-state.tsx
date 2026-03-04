interface EmptyStateProps {
  icon?: React.ReactNode;
  title: string;
  description?: string;
  action?: {
    label: string;
    href?: string;
    onClick?: () => void;
  };
}

export function EmptyState({ icon, title, description, action }: EmptyStateProps) {
  return (
    <div className="flex flex-col items-center justify-center py-16 text-center">
      {icon && <div className="mb-4 text-content-muted">{icon}</div>}
      <h3 className="text-lg font-semibold text-content-primary">{title}</h3>
      {description && (
        <p className="mt-2 max-w-sm text-sm text-content-secondary">{description}</p>
      )}
      {action && (
        action.href ? (
          <a
            href={action.href}
            className="mt-6 inline-flex items-center rounded-lg bg-brand px-4 py-2 text-sm font-medium text-white hover:brightness-110 transition-all"
          >
            {action.label}
          </a>
        ) : (
          <button
            onClick={action.onClick}
            className="mt-6 inline-flex items-center rounded-lg bg-brand px-4 py-2 text-sm font-medium text-white hover:brightness-110 transition-all"
          >
            {action.label}
          </button>
        )
      )}
    </div>
  );
}
