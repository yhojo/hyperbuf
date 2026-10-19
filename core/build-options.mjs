// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Settings for the Web core bundle. Shared by build.mjs (build) and scripts/licenses.mjs (listing of bundled
// libraries).
// Mermaid is split into a separate chunk via dynamic import and loaded only for documents with diagrams.
export const buildOptions = {
  entryPoints: ["src/main.ts"],
  bundle: true,
  splitting: true,
  format: "esm",
  outdir: "dist",
  target: "safari17", // matches Safari 17 of macOS 14
  minify: true,
  loader: { ".woff2": "file", ".woff": "file", ".ttf": "file", ".wasm": "file" },
  // elkjs (EPL-2.0) is not bundled. Diagrams that use the ELK layout are shown as an error at the diagram's
  // position
  alias: { "elkjs/lib/elk.bundled.js": "./src/stubs/elkjs-disabled.js" },
  logLevel: "warning",
};
