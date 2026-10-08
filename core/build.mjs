// Web コアを dist/ にバンドルする。Mermaid は動的 import で別チャンクにし、図のある文書でだけ読み込む。
import { copyFile, mkdir } from "node:fs/promises";
import * as esbuild from "esbuild";

await esbuild.build({
  entryPoints: ["src/main.ts"],
  bundle: true,
  splitting: true,
  format: "esm",
  outdir: "dist",
  target: "safari17", // macOS 14 の Safari 17 に合わせる
  minify: true,
  loader: { ".woff2": "file", ".woff": "file", ".ttf": "file", ".wasm": "file" },
  logLevel: "warning",
});
await mkdir("dist", { recursive: true });
await copyFile("public/index.html", "dist/index.html");
