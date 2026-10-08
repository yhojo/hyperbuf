// Web コアを dist/ にバンドルする(Mermaid などの重い部品は動的 import で別チャンクにする)。
import * as esbuild from "esbuild";

await esbuild.build({
  entryPoints: ["src/index.ts"],
  bundle: true,
  splitting: true,
  format: "esm",
  outdir: "dist",
  target: "safari17", // macOS 14 の Safari 17 に合わせる
  minify: true,
  logLevel: "warning",
});
