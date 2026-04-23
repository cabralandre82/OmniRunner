import { ImageResponse } from "next/og";

import {
  OG_IMAGE_SIZE,
  OG_IMAGE_THEMES,
  OG_SITE_NAME,
} from "@/lib/og-metadata";

export const runtime = "edge";
export const contentType = "image/png";
export const size = OG_IMAGE_SIZE;

interface Props {
  params: { code: string };
}

export default function InviteOpengraphImage({ params }: Props) {
  const theme = OG_IMAGE_THEMES.invite;
  const code = (params.code ?? "").slice(0, 10).toUpperCase();

  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "space-between",
          padding: "80px",
          background: `linear-gradient(135deg, ${theme.bgFrom} 0%, ${theme.bgTo} 100%)`,
          color: "white",
          fontFamily: "sans-serif",
        }}
      >
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: "16px",
            fontSize: "32px",
            fontWeight: 600,
            opacity: 0.9,
          }}
        >
          <div
            style={{
              width: "64px",
              height: "64px",
              borderRadius: "16px",
              background: theme.accent,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              fontSize: "32px",
              color: "#2e1065",
            }}
          >
            OR
          </div>
          {OG_SITE_NAME}
        </div>
        <div style={{ display: "flex", flexDirection: "column", gap: "12px" }}>
          <div style={{ fontSize: "80px", fontWeight: 800, lineHeight: 1.05 }}>
            Você foi convidado
          </div>
          <div style={{ fontSize: "40px", opacity: 0.85 }}>
            Aceite o convite para rodar com a sua assessoria.
          </div>
          {code && (
            <div
              style={{
                marginTop: "24px",
                fontSize: "44px",
                fontWeight: 700,
                color: theme.accent,
                letterSpacing: "4px",
              }}
            >
              CÓDIGO: {code}
            </div>
          )}
        </div>
        <div
          style={{
            fontSize: "28px",
            fontWeight: 500,
            color: theme.accent,
          }}
        >
          omnirunner.app
        </div>
      </div>
    ),
    size,
  );
}
