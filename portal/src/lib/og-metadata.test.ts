import { afterEach, beforeEach, describe, expect, it } from "vitest";

import {
  OG_IMAGE_HEIGHT,
  OG_IMAGE_SIZE,
  OG_IMAGE_THEMES,
  OG_IMAGE_WIDTH,
  OG_SITE_NAME,
  buildOgMetadata,
  getSiteBaseUrl,
} from "./og-metadata";

const originalEnv = { ...process.env };

describe("og-metadata (L15-03)", () => {
  beforeEach(() => {
    delete process.env.NEXT_PUBLIC_PORTAL_BASE_URL;
    delete process.env.PORTAL_BASE_URL;
  });
  afterEach(() => {
    process.env = { ...originalEnv };
  });

  it("falls back to omnirunner.app when no env base is set", () => {
    expect(getSiteBaseUrl()).toBe("https://omnirunner.app");
  });

  it("honours NEXT_PUBLIC_PORTAL_BASE_URL and strips trailing slash", () => {
    process.env.NEXT_PUBLIC_PORTAL_BASE_URL = "https://preview.omni.run/";
    expect(getSiteBaseUrl()).toBe("https://preview.omni.run");
  });

  it("ignores malformed base URL and falls back", () => {
    process.env.NEXT_PUBLIC_PORTAL_BASE_URL = "javascript:alert(1)";
    expect(getSiteBaseUrl()).toBe("https://omnirunner.app");
  });

  it("emits full OG + Twitter payload with dynamic image URL", () => {
    const meta = buildOgMetadata({
      path: "/challenge/abc",
      title: "Desafio aberto",
      description: "Aceite o desafio.",
    });

    expect(meta.title).toBe("Desafio aberto");
    expect(meta.description).toBe("Aceite o desafio.");
    expect(meta.openGraph?.type).toBe("website");
    expect(meta.openGraph?.siteName).toBe(OG_SITE_NAME);
    expect(meta.openGraph?.locale).toBe("pt_BR");
    expect(meta.openGraph?.url).toBe("https://omnirunner.app/challenge/abc");
    expect(Array.isArray(meta.openGraph?.images)).toBe(true);
    const ogImages = meta.openGraph?.images as Array<{
      url: string;
      width?: number;
      height?: number;
    }>;
    expect(ogImages[0]?.url).toBe(
      "https://omnirunner.app/challenge/abc/opengraph-image",
    );
    expect(ogImages[0]?.width).toBe(OG_IMAGE_WIDTH);
    expect(ogImages[0]?.height).toBe(OG_IMAGE_HEIGHT);

    expect(meta.twitter?.card).toBe("summary_large_image");
    expect(meta.alternates?.canonical).toBe(
      "https://omnirunner.app/challenge/abc",
    );
  });

  it("lets callers override image URL", () => {
    const meta = buildOgMetadata({
      path: "/challenge/abc",
      title: "t",
      description: "d",
      imageUrl: "https://cdn.example/og.png",
    });
    const ogImages = meta.openGraph?.images as Array<{ url: string }>;
    expect(ogImages[0]?.url).toBe("https://cdn.example/og.png");
  });

  it("normalises missing leading slash in path", () => {
    const meta = buildOgMetadata({
      path: "invite/XYZ",
      title: "t",
      description: "d",
    });
    expect(meta.openGraph?.url).toBe("https://omnirunner.app/invite/XYZ");
  });

  it("exposes standard OG image size", () => {
    expect(OG_IMAGE_SIZE).toEqual({ width: 1200, height: 630 });
  });

  it("exposes theme palette for challenge + invite + default", () => {
    expect(OG_IMAGE_THEMES.challenge.accent).toBeTypeOf("string");
    expect(OG_IMAGE_THEMES.invite.accent).toBeTypeOf("string");
    expect(OG_IMAGE_THEMES.default.accent).toBeTypeOf("string");
  });
});
