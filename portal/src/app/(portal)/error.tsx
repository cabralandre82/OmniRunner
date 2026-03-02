"use client";

import { useEffect } from "react";
import * as Sentry from "@sentry/nextjs";

export default function PortalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    Sentry.captureException(error);
  }, [error]);
  return (
    <div className="flex flex-col items-center justify-center px-6 py-24 text-center">
      <div className="mb-4 flex h-14 w-14 items-center justify-center rounded-full bg-red-100">
        <svg
          className="h-7 w-7 text-red-600"
          fill="none"
          viewBox="0 0 24 24"
          strokeWidth={1.5}
          stroke="currentColor"
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126ZM12 15.75h.007v.008H12v-.008Z"
          />
        </svg>
      </div>
      <h2 className="text-lg font-semibold text-gray-900">
        Algo deu errado
      </h2>
      <p className="mt-2 max-w-md text-sm text-gray-500">
        {error.message || "Ocorreu um erro inesperado. Tente novamente."}
      </p>
      {error.digest && (
        <p className="mt-1 font-mono text-xs text-gray-400">
          Ref: {error.digest}
        </p>
      )}
      <button
        onClick={reset}
        className="mt-6 rounded-lg bg-blue-600 px-5 py-2.5 text-sm font-medium text-white hover:bg-blue-700"
      >
        Tentar novamente
      </button>
    </div>
  );
}
