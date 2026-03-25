const sassPlugin = require("esbuild-plugin-sass");

require("esbuild")
  .build({
    entryPoints: ["app/javascript/application.js"],
    bundle: true,
    sourcemap: true,
    format: "esm",
    outdir: "app/assets/builds",
    publicPath: "/assets",
    loader: { ".png": "file", ".svg": "file", ".css": "css" }, // Use css loader
    plugins: [sassPlugin()],
  })
  .catch(() => process.exit(1));