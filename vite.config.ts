import { defineConfig } from "vite"
import react from "@vitejs/plugin-react"

// Relative base keeps asset URLs working under whatever subpath (or custom
// domain) GitHub Pages serves from. Site output stays separate from docs/.
export default defineConfig({
  base: "./",
  plugins: [react()],
  build: {
    outDir: "dist-site",
    emptyOutDir: true,
  },
})
