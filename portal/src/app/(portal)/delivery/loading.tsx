export default function Loading() {
  return (
    <div className="space-y-6 p-6">
      <div className="h-8 w-48 animate-shimmer rounded" />
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
        {[1, 2, 3, 4, 5].map((i) => (
          <div key={i} className="h-24 animate-shimmer rounded-xl" />
        ))}
      </div>
      <div className="h-32 animate-shimmer rounded-xl" />
      <div className="h-96 animate-shimmer rounded-xl" />
    </div>
  );
}
