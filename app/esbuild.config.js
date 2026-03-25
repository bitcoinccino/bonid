// esbuild.config.js
import path from "path"
import { build } from "esbuild"
import rails from "esbuild-rails"

const entryPoints = [
  "app/javascript/application.js",
  "app/javascript/styles/partner_portal/banking_agents.scss" // 👈 build this too
]

build({
  entryPoints,
  bundle: true,
  sourcemap: true,
  outdir: path.join(process.cwd(), "app/assets/builds"),
  absWorkingDir: process.cwd(),
  plugins: [rails()],
  loader: { ".scss": "css" },
  watch: process.argv.includes("--watch"),
}).catch(() => process.exit(1))
