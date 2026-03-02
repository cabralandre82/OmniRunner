import Link from "next/link";

export default function NotFound() {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center px-6 text-center">
      <p className="text-7xl font-bold text-gray-200">404</p>
      <h1 className="mt-4 text-xl font-semibold text-gray-900">
        Página não encontrada
      </h1>
      <p className="mt-2 max-w-md text-sm text-gray-500">
        A página que você está procurando não existe ou foi movida.
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
