import { getRequestConfig } from "next-intl/server";
import { cookies, headers } from "next/headers";

const SUPPORTED_LOCALES = ["pt-BR", "en"] as const;
const DEFAULT_LOCALE = "pt-BR";

function getLocaleFromAcceptLanguage(acceptLanguage: string | null): (typeof SUPPORTED_LOCALES)[number] {
  if (!acceptLanguage) return DEFAULT_LOCALE;
  const parts = acceptLanguage
    .split(",")
    .map((p) => {
      const [locale, q] = p.trim().split(";q=");
      return { locale: locale.trim().toLowerCase(), q: q ? parseFloat(q) : 1 };
    })
    .sort((a, b) => b.q - a.q);

  for (const { locale } of parts) {
    if (locale.startsWith("pt-br") || locale === "pt-br") return "pt-BR";
    if (locale.startsWith("en") || locale === "en") return "en";
  }
  return DEFAULT_LOCALE;
}

export default getRequestConfig(async () => {
  const cookieStore = await cookies();
  const headerStore = await headers();

  const cookieLocale = cookieStore.get("portal_locale")?.value;
  if (cookieLocale && SUPPORTED_LOCALES.includes(cookieLocale as (typeof SUPPORTED_LOCALES)[number])) {
    const locale = cookieLocale as (typeof SUPPORTED_LOCALES)[number];
    return {
      locale,
      messages: (await import(`../../messages/${locale}.json`)).default,
    };
  }

  const acceptLanguage = headerStore.get("accept-language");
  const locale = getLocaleFromAcceptLanguage(acceptLanguage);

  return {
    locale,
    messages: (await import(`../../messages/${locale}.json`)).default,
  };
});
