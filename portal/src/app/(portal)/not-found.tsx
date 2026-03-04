import Link from "next/link";

export default function PortalNotFound() {
  return (
    <div className="flex flex-1 flex-col items-center justify-center px-6 py-24 text-center">
      <p className="text-6xl font-bold text-border">404</p>
      <h1 className="mt-4 text-lg font-semibold text-content-primary">
        Página não encontrada
      </h1>
      <p className="mt-2 max-w-sm text-sm text-content-secondary">
        Essa página não existe ou você não tem permissão para acessá-la.
      </p>
      <Link
        href="/dashboard"
        className="mt-6 rounded-lg bg-brand px-5 py-2.5 text-sm font-medium text-white hover:brightness-110"
      >
        Voltar ao Dashboard
      </Link>
    </div>
  );
}
