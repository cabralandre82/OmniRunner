import type { ReactNode } from "react";

interface TableWrapperProps {
  children: ReactNode;
  className?: string;
}

export function TableWrapper({ children, className = "" }: TableWrapperProps) {
  return (
    <div
      className={`overflow-hidden rounded-xl border border-border bg-surface shadow-sm ${className}`}
    >
      <div className="overflow-x-auto">{children}</div>
    </div>
  );
}

export function Th({
  children,
  className = "",
  ...props
}: React.ThHTMLAttributes<HTMLTableCellElement> & { children?: ReactNode }) {
  return (
    <th
      className={`px-4 py-3 text-left text-xs font-medium uppercase tracking-wide text-content-muted ${className}`}
      {...props}
    >
      {children}
    </th>
  );
}

export function Td({
  children,
  className = "",
  ...props
}: React.TdHTMLAttributes<HTMLTableCellElement> & { children?: ReactNode }) {
  return (
    <td
      className={`whitespace-nowrap px-4 py-3 text-sm text-content-secondary ${className}`}
      {...props}
    >
      {children}
    </td>
  );
}
