import Link from "next/link";

export default function PortalNotFound() {
  return (
    <div className="flex flex-1 flex-col items-center justify-center px-6 py-24 text-center">
      <p className="text-6xl font-bold text-gray-200">404</p>
      <h1 className="mt-4 text-lg font-semibold text-gray-900">
        Página não encontrada
      </h1>
      <p className="mt-2 max-w-sm text-sm text-gray-500">
        Essa página não existe ou você não tem permissão para acessá-la.
      </p>
      <Link
        href="/dashboard"
        className="mt-6 rounded-lg bg-blue-600 px-5 py-2.5 text-sm font-medium text-white hover:bg-blue-700"
      >
        Voltar ao Dashboard
      </Link>
    </div>
  );
}
