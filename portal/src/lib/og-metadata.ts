/**
 * og-metadata.ts — canonical Open Graph + Twitter metadata builder.
 *
 * L15-03: every shareable page in the portal (challenges, invites, etc.)
 * pipes its Metadata through this helper so previews on WhatsApp /
 * Instagram / X / Telegram are consistent, use the dynamic OG image
 * emitted by the co-located `opengraph-image.tsx` route segment, and
 * carry the right Twitter card shape.
 *
 * Keeping this logic in one file also means we only have one place to
 * enforce the canonical site URL, brand copy, and image dimensions.
 *
 * Next.js 13+/14 auto-injects `opengraph-image` (and `twitter-image`)
 * emitted from a route segment, so consumers don't need to set
 * `openGraph.images` themselves — but we still set a deterministic URL
 * to make the feature observable and cacheable.
 */
import type { Metadata } from "next";

export const OG_SITE_NAME = "Omni Runner";
export const OG_DEFAULT_LOCALE = "pt_BR";
export const OG_IMAGE_WIDTH = 1200;
export const OG_IMAGE_HEIGHT = 630;

export function getSiteBaseUrl(): string {
  const envUrl =
    process.env.NEXT_PUBLIC_PORTAL_BASE_URL ??
    process.env.PORTAL_BASE_URL ??
    "";
  if (envUrl && /^https?:\/\//i.test(envUrl)) {
    return envUrl.replace(/\/+$/, "");
  }
  return "https://omnirunner.app";
}

export interface OgPageInput {
  /** Full absolute path of the shareable page, e.g. "/challenge/abc". */
  path: string;
  /** Main page title — shows as og:title / twitter:title. */
  title: string;
  /** 1-2 sentence description — og:description / twitter:description. */
  description: string;
  /**
   * Override for the OG image absolute URL. When omitted, Next.js
   * resolves the co-located `opengraph-image` segment automatically;
   * we keep the hook for integration tests and for the rare case
   * where a non-dynamic image makes more sense.
   */
  imageUrl?: string;
  /** Open Graph type — defaults to "website". */
  type?: "website" | "article" | "profile";
  /** Twitter card style — defaults to "summary_large_image". */
  twitterCard?: "summary" | "summary_large_image";
  /** Locale — defaults to pt_BR. */
  locale?: string;
}

/**
 * Build the full Metadata payload for a shareable page. The result is
 * designed to be returned directly from a route's `generateMetadata`.
 */
export function buildOgMetadata(input: OgPageInput): Metadata {
  const base = getSiteBaseUrl();
  const cleanPath = input.path.startsWith("/") ? input.path : `/${input.path}`;
  const url = `${base}${cleanPath}`;
  const ogImage =
    input.imageUrl ??
    `${url}/opengraph-image`;

  const title = input.title;
  const description = input.description;

  return {
    title,
    description,
    openGraph: {
      title,
      description,
      type: input.type ?? "website",
      url,
      siteName: OG_SITE_NAME,
      locale: input.locale ?? OG_DEFAULT_LOCALE,
      images: [
        {
          url: ogImage,
          width: OG_IMAGE_WIDTH,
          height: OG_IMAGE_HEIGHT,
          alt: title,
        },
      ],
    },
    twitter: {
      card: input.twitterCard ?? "summary_large_image",
      title,
      description,
      images: [ogImage],
    },
    alternates: { canonical: url },
  };
}

/**
 * Centralised colour palette for the ImageResponse-based dynamic OG
 * images. Exposed so the per-route `opengraph-image.tsx` files share
 * the same look-and-feel (brand consistency + single point of change).
 */
export const OG_IMAGE_THEMES = {
  challenge: {
    bgFrom: "#064e3b",
    bgTo: "#0891b2",
    accent: "#34d399",
  },
  invite: {
    bgFrom: "#1e1b4b",
    bgTo: "#7e22ce",
    accent: "#c084fc",
  },
  default: {
    bgFrom: "#0f172a",
    bgTo: "#1e293b",
    accent: "#22d3ee",
  },
} as const;

export type OgImageThemeKey = keyof typeof OG_IMAGE_THEMES;

/** Standard size used by ImageResponse OG routes in the portal. */
export const OG_IMAGE_SIZE = {
  width: OG_IMAGE_WIDTH,
  height: OG_IMAGE_HEIGHT,
} as const;
