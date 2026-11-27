import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { VitePWA } from "vite-plugin-pwa";

// The manifest is what lets Edge and Chrome on Windows install the site as an
// app with its own window and Start-menu entry. The app is drawn dark
// throughout on iOS and Android, so the install chrome is dark too.
// Built for a Firebase project (`--mode staging` / `--mode prod`, see
// scripts/build-hosting.mjs), the app lives at /app/ on the project's Hosting
// site, next to the existing pages, and is written straight into that site's
// folder. Otherwise (dev server, plain `npm run build`) it is at the root.
const HOSTED_MODES = new Set(["staging", "prod"]);

export default defineConfig(({ mode }) => {
  const hosted = HOSTED_MODES.has(mode);
  return {
  base: hosted ? "/app/" : "/",
  build: hosted ? { outDir: "../backend/Firebase/public/app", emptyOutDir: true } : {},
  plugins: [
    react(),
    VitePWA({
      registerType: "autoUpdate",
      manifest: {
        name: "Instant Teacher",
        short_name: "Instant Teacher",
        description: "A human math teacher within 90 seconds.",
        // Relative, so the installed app and its offline cache cover only its
        // own folder and never the rest of the site.
        start_url: "./",
        scope: "./",
        display: "standalone",
        background_color: "#0b0f1a",
        theme_color: "#0b0f1a",
        icons: [
          { src: "icons/icon-192.png", sizes: "192x192", type: "image/png" },
          { src: "icons/icon-512.png", sizes: "512x512", type: "image/png" },
          { src: "icons/icon-512.png", sizes: "512x512", type: "image/png", purpose: "maskable" },
        ],
      },
    }),
  ],
  server: { port: 5180 },
  };
});
