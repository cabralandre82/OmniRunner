import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./src/pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/components/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  darkMode: "class",
  theme: {
    extend: {
      colors: {
        bg: {
          primary: "var(--bg-primary)",
          secondary: "var(--bg-secondary)",
        },
        surface: {
          DEFAULT: "var(--surface)",
          elevated: "var(--surface-elevated)",
        },
        brand: {
          DEFAULT: "var(--primary)",
          soft: "var(--primary-soft)",
          glow: "var(--primary-glow)",
        },
        content: {
          primary: "var(--text-primary)",
          secondary: "var(--text-secondary)",
          muted: "var(--text-muted)",
        },
        success: "var(--success)",
        warning: "var(--warning)",
        error: "var(--error)",
        info: "var(--info)",
        border: {
          DEFAULT: "var(--border)",
          subtle: "var(--border-subtle)",
        },
        overlay: "var(--overlay)",

        // Backward compat: Tailwind default references
        background: "var(--bg-primary)",
        foreground: "var(--text-primary)",
      },
      spacing: {
        xs: "var(--spacing-xs)",
        sm: "var(--spacing-sm)",
        md: "var(--spacing-md)",
        lg: "var(--spacing-lg)",
        xl: "var(--spacing-xl)",
        xxl: "var(--spacing-xxl)",
      },
      borderRadius: {
        sm: "var(--radius-sm)",
        md: "var(--radius-md)",
        lg: "var(--radius-lg)",
        xl: "var(--radius-xl)",
      },
      boxShadow: {
        sm: "var(--shadow-sm)",
        md: "var(--shadow-md)",
        lg: "var(--shadow-lg)",
      },
      fontSize: {
        "display-lg": ["var(--display-large)", { lineHeight: "1.2", fontWeight: "var(--font-weight-bold)" }],
        "display-md": ["var(--display-medium)", { lineHeight: "1.25", fontWeight: "var(--font-weight-bold)" }],
        "title-lg": ["var(--title-large)", { lineHeight: "1.3", fontWeight: "var(--font-weight-semibold)" }],
        "title-md": ["var(--title-medium)", { lineHeight: "1.35", fontWeight: "var(--font-weight-semibold)" }],
        body: ["var(--body)", { lineHeight: "1.5", fontWeight: "var(--font-weight-regular)" }],
        caption: ["var(--caption)", { lineHeight: "1.5", fontWeight: "var(--font-weight-regular)" }],
        label: ["var(--label)", { lineHeight: "1.4", fontWeight: "var(--font-weight-medium)" }],
      },
      transitionDuration: {
        fast: "var(--duration-fast)",
        normal: "var(--duration-normal)",
        slow: "var(--duration-slow)",
      },
      opacity: {
        hover: "var(--opacity-hover)",
        pressed: "var(--opacity-pressed)",
        disabled: "var(--opacity-disabled)",
        focus: "var(--opacity-focus)",
      },
    },
  },
  plugins: [],
};
export default config;
