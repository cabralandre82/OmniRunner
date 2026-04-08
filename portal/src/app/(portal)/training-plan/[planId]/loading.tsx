export default function Loading() {
  return (
    <div className="space-y-4 animate-pulse">
      <div className="flex items-center gap-3">
        <div className="h-5 w-20 rounded bg-surface-elevated" />
        <div className="h-6 w-40 rounded bg-surface-elevated" />
      </div>
      {[1, 2, 3].map((i) => (
        <div key={i} className="h-52 rounded-xl bg-surface-elevated" />
      ))}
    </div>
  );
}
