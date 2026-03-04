import Link from "next/link";

export default function NotFound() {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center px-6 text-center">
      <p className="text-7xl font-bold text-border">404</p>
      <h1 className="mt-4 text-xl font-semibold text-content-primary">
        Página não encontrada
      </h1>
      <p className="mt-2 max-w-md text-sm text-content-secondary">
        A página que você está procurando não existe ou foi movida.
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
