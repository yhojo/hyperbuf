// Web コアのバンドルの設定。build.mjs(ビルド)と scripts/licenses.mjs(同梱するライブラリの洗い出し)が共有する。
// Mermaid は動的 import で別チャンクにし、図のある文書でだけ読み込む。
export const buildOptions = {
  entryPoints: ["src/main.ts"],
  bundle: true,
  splitting: true,
  format: "esm",
  outdir: "dist",
  target: "safari17", // macOS 14 の Safari 17 に合わせる
  minify: true,
  loader: { ".woff2": "file", ".woff": "file", ".ttf": "file", ".wasm": "file" },
  logLevel: "warning",
};
