import type { Metadata } from "next";

const APP_SCHEME = "omnirunner";
const STORE_URL_ANDROID =
  "https://play.google.com/store/apps/details?id=com.omnirunner.omni_runner";
const STORE_URL_IOS =
  "https://apps.apple.com/app/omni-runner/id0000000000";

interface Props {
  params: { id: string };
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  return {
    title: "Desafio — Omni Runner",
    description:
      "Você recebeu um convite para um desafio no Omni Runner. Abra o app para participar!",
    openGraph: {
      title: "Desafio no Omni Runner",
      description: "Toque para abrir o desafio no app.",
      type: "website",
      url: `https://omnirunner.app/challenge/${params.id}`,
    },
  };
}

export default function ChallengeLandingPage({ params }: Props) {
  const deepLink = `${APP_SCHEME}://challenge/${params.id}`;

  return (
    <html lang="pt-BR">
      <head>
        <meta
          httpEquiv="refresh"
          content={`3;url=${deepLink}`}
        />
      </head>
      <body className="min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900 flex items-center justify-center p-6">
        <div className="max-w-md w-full text-center space-y-8">
          {/* Logo / Icon */}
          <div className="mx-auto w-20 h-20 rounded-2xl bg-gradient-to-br from-emerald-400 to-cyan-500 flex items-center justify-center shadow-lg shadow-emerald-500/20">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              viewBox="0 0 24 24"
              fill="white"
              className="w-10 h-10"
            >
              <path d="M13.5 5.5c1.1 0 2-.9 2-2s-.9-2-2-2-2 .9-2 2 .9 2 2 2zM9.89 19.38l1-4.38L13 17v6h2v-7.5l-2.11-2 .61-3A8.26 8.26 0 0 0 19 13v-2c-1.91 0-3.6-.86-4.73-2.19l-1-1.24c-.4-.5-1-.81-1.64-.81-.27 0-.54.06-.78.16L6 9.8V14h2v-2.73l1.29-.53L7.5 20l2.39-.62z" />
            </svg>
          </div>

          <div className="space-y-3">
            <h1 className="text-3xl font-bold text-white">
              Desafio no Omni Runner
            </h1>
            <p className="text-slate-300 text-lg">
              Você recebeu um convite para participar de um desafio de corrida.
            </p>
          </div>

          {/* CTA — Deep Link */}
          <a
            href={deepLink}
            className="inline-block w-full py-4 px-6 rounded-xl bg-gradient-to-r from-emerald-500 to-cyan-500 text-white font-semibold text-lg shadow-lg shadow-emerald-500/30 hover:shadow-emerald-500/50 transition-shadow"
          >
            Abrir no App
          </a>

          {/* Store badges */}
          <div className="space-y-3">
            <p className="text-slate-400 text-sm">
              Ainda não tem o app? Baixe agora:
            </p>
            <div className="flex flex-col sm:flex-row gap-3 justify-center">
              <a
                href={STORE_URL_ANDROID}
                className="inline-flex items-center justify-center gap-2 py-3 px-5 rounded-lg bg-slate-700 hover:bg-slate-600 transition-colors text-white text-sm font-medium"
              >
                <svg viewBox="0 0 24 24" fill="currentColor" className="w-5 h-5">
                  <path d="M17.523 2.237a.6.6 0 0 0-.829.2L15.08 5.1A8.434 8.434 0 0 0 12 4.5a8.434 8.434 0 0 0-3.08.6L7.306 2.437a.6.6 0 1 0-1.028.623L7.82 5.6A8.5 8.5 0 0 0 3.5 13h17a8.5 8.5 0 0 0-4.32-7.4l1.543-2.54a.6.6 0 0 0-.2-.823zM8.5 10a1 1 0 1 1 0-2 1 1 0 0 1 0 2zm7 0a1 1 0 1 1 0-2 1 1 0 0 1 0 2zM3.5 14v6a2 2 0 0 0 2 2h1V14h-3zm15 0v8h1a2 2 0 0 0 2-2v-6h-3zm-12 0v8.5h2.5V14H6.5zm3.5 0v8.5h4V14h-4zm5 0v8.5H17.5V14H15z" />
                </svg>
                Google Play
              </a>
              <a
                href={STORE_URL_IOS}
                className="inline-flex items-center justify-center gap-2 py-3 px-5 rounded-lg bg-slate-700 hover:bg-slate-600 transition-colors text-white text-sm font-medium"
              >
                <svg viewBox="0 0 24 24" fill="currentColor" className="w-5 h-5">
                  <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z" />
                </svg>
                App Store
              </a>
            </div>
          </div>

          <p className="text-slate-500 text-xs">
            Se o app não abrir automaticamente em 3 segundos, toque no botão
            acima.
          </p>
        </div>
      </body>
    </html>
  );
}
