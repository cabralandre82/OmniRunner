import type { Metadata } from "next";

const APP_SCHEME = "omnirunner";
const STORE_URL_ANDROID =
  "https://play.google.com/store/apps/details?id=com.omnirunner.omni_runner";
const STORE_URL_IOS =
  "https://apps.apple.com/app/omni-runner/id0000000000";

interface Props {
  params: { code: string };
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  return {
    title: "Convite — Omni Runner",
    description:
      "Você foi convidado para uma assessoria no Omni Runner. Abra o app para se juntar!",
    openGraph: {
      title: "Convite para Assessoria — Omni Runner",
      description: "Toque para aceitar o convite no app.",
      type: "website",
      url: `https://omnirunner.app/invite/${params.code}`,
    },
  };
}

export default function InviteLandingPage({ params }: Props) {
  const deepLink = `${APP_SCHEME}://invite/${params.code}`;

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
          <div className="mx-auto w-20 h-20 rounded-2xl bg-gradient-to-br from-violet-400 to-fuchsia-500 flex items-center justify-center shadow-lg shadow-violet-500/20">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              viewBox="0 0 24 24"
              fill="white"
              className="w-10 h-10"
            >
              <path d="M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5s-3 1.34-3 3 1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5zm8 0c-.29 0-.62.02-.97.05 1.16.84 1.97 1.97 1.97 3.45V19h6v-2.5c0-2.33-4.67-3.5-7-3.5z" />
            </svg>
          </div>

          <div className="space-y-3">
            <h1 className="text-3xl font-bold text-white">
              Convite para Assessoria
            </h1>
            <p className="text-slate-300 text-lg">
              Você foi convidado para fazer parte de uma assessoria de corrida no
              Omni Runner.
            </p>
          </div>

          {/* CTA — Deep Link */}
          <a
            href={deepLink}
            className="inline-block w-full py-4 px-6 rounded-xl bg-gradient-to-r from-violet-500 to-fuchsia-500 text-white font-semibold text-lg shadow-lg shadow-violet-500/30 hover:shadow-violet-500/50 transition-shadow"
          >
            Aceitar Convite no App
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
