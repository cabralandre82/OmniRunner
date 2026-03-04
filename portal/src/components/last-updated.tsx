export function LastUpdated() {
  const now = new Date().toLocaleString("pt-BR", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
  return (
    <p className="text-xs text-zinc-500 mt-4 text-right">
      Atualizado em {now}
    </p>
  );
}
