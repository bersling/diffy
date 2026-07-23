import { defineConfig } from "vite";

export default defineConfig({
  build: {
    outDir: "dist",
    target: "es2022",
    // Single-page local tool: inline everything into as few requests as possible.
    assetsInlineLimit: 100000,
    chunkSizeWarningLimit: 2000,
  },
});
