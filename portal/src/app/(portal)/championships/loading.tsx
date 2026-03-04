export default function ChampionshipsLoading() {
  return (
    <div className="space-y-6 animate-pulse">
      <div>
        <div className="h-7 w-40 rounded bg-surface-elevated" />
        <div className="mt-2 h-4 w-64 rounded bg-surface-elevated" />
      </div>
      <div className="space-y-3">
        {Array.from({ length: 4 }).map((_, i) => (
          <div
            key={i}
            className="rounded-xl border border-border bg-surface p-4"
          >
            <div className="flex items-start justify-between gap-3">
              <div className="flex-1 space-y-2">
                <div className="h-4 w-48 rounded bg-surface-elevated" />
                <div className="h-3 w-64 rounded bg-surface-elevated" />
              </div>
              <div className="h-6 w-20 rounded-full bg-surface-elevated" />
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
