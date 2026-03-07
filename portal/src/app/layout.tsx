import type { Metadata } from "next";
import localFont from "next/font/local";
import { NextIntlClientProvider } from "next-intl";
import { getLocale, getMessages } from "next-intl/server";
import { Toaster } from "sonner";
import { WebVitals } from "@/components/web-vitals";
import { ThemeProvider } from "@/components/theme-provider";
import "./globals.css";

const geistSans = localFont({
  src: "./fonts/GeistVF.woff",
  variable: "--font-geist-sans",
  weight: "100 900",
});

export const metadata: Metadata = {
  title: {
    default: "Omni Runner — Portal",
    template: "%s | Omni Runner",
  },
  description: "Portal de gestão para assessorias esportivas — gerencie atletas, créditos, verificação e engajamento.",
  metadataBase: new URL("https://portal.omnirunner.app"),
  openGraph: {
    title: "Omni Runner Portal",
    description: "Gerencie sua assessoria de corrida com inteligência.",
    siteName: "Omni Runner",
    type: "website",
  },
  robots: {
    index: false,
    follow: false,
  },
};

export default async function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  const locale = await getLocale();
  const messages = await getMessages();

  return (
    <html lang={locale} suppressHydrationWarning>
      <body className={`${geistSans.variable} font-sans antialiased bg-bg-primary text-content-primary`}>
        <ThemeProvider>
          <NextIntlClientProvider messages={messages}>
            <WebVitals />
            {children}
          </NextIntlClientProvider>
          <Toaster richColors position="top-right" />
        </ThemeProvider>
      </body>
    </html>
  );
}
