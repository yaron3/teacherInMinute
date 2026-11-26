import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { VitePWA } from "vite-plugin-pwa";

// The manifest is what lets Edge and Chrome on Windows install the site as an
// app with its own window and Start-menu entry. The app is drawn dark
// throughout on iOS and Android, so the install chrome is dark too.
export default defineConfig({
  plugins: [
    react(),
    VitePWA({
      registerType: "autoUpdate",
      manifest: {
        name: "Instant Teacher",
        short_name: "Instant Teacher",
        description: "A human math teacher within 90 seconds.",
        start_url: "/",
        display: "standalone",
        background_color: "#0b0f1a",
        theme_color: "#0b0f1a",
        icons: [
          { src: "/icons/icon-192.png", sizes: "192x192", type: "image/png" },
          { src: "/icons/icon-512.png", sizes: "512x512", type: "image/png" },
          { src: "/icons/icon-512.png", sizes: "512x512", type: "image/png", purpose: "maskable" },
        ],
      },
    }),
  ],
  server: { port: 5180 },
});
