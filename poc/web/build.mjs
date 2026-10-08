// Web コアを dist/ にバンドルする。Mermaid は動的 import で別チャンクにし、使う文書でだけ読み込む。
import * as esbuild from "esbuild";

const result = await esbuild.build({
  entryPoints: ["app.js"],
  bundle: true,
  splitting: true,
  format: "esm",
  outdir: "dist",
  target: "safari17",
  minify: true,
  loader: { ".woff2": "file", ".woff": "file", ".ttf": "file", ".wasm": "file" },
  metafile: true,
  logLevel: "warning",
});

const out = Object.entries(result.metafile.outputs)
  .map(([file, info]) => ({ file, kb: Math.round(info.bytes / 1024) }))
  .filter((o) => /\.(js|css)$/.test(o.file))
  .sort((a, b) => b.kb - a.kb);
console.table(out);
