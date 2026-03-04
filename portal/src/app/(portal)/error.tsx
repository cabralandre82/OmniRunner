'use client';

export default function PortalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <div className="flex min-h-[60vh] flex-col items-center justify-center gap-4 p-8 text-center">
      <h2 className="text-2xl font-semibold text-gray-800">
        Algo deu errado
      </h2>
      <p className="max-w-md text-sm text-gray-500">
        Ocorreu um erro inesperado. Por favor, tente novamente ou entre em
        contato com o suporte se o problema persistir.
      </p>
      <button
        onClick={reset}
        className="mt-2 rounded-lg bg-blue-600 px-6 py-2.5 text-sm font-medium text-white shadow hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
      >
        Tentar novamente
      </button>
    </div>
  );
}
