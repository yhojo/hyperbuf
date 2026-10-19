// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Entry point in the browser (WebView). Uses the `window.hyperbufHost` injected by the shell.
// If absent, uses the dev server's HTTP API (for development).

import "github-markdown-css/github-markdown.css";
import "katex/dist/katex.min.css";
import "@wooorm/starry-night/style/both";
import onigWasm from "vscode-oniguruma/release/onig.wasm";
import "./ui/style.css";
import { createDevHost } from "./dev-host.ts";
import type { HyperbufHost } from "./host.ts";
import { createRenderer } from "./pipeline.ts";
import { startApp } from "./ui/app.ts";
import type { AppHandle } from "./ui/app.ts";

declare global {
  interface Window {
    /** Injected by the shell. */
    hyperbufHost?: HyperbufHost;
    /** Entry point for automated verification (integration tests, headless). Not an API for users. */
    __hyperbuf?: AppHandle;
  }
}

const host = window.hyperbufHost ?? (await createDevHost());
// starry-night fetches WASM from an external CDN by default, so point it at the bundled file (local first)
const renderer = await createRenderer({ onigUrl: new URL(onigWasm, import.meta.url) });
window.__hyperbuf = await startApp({
  // After reading the document, prepare the large grammars its code blocks use, before rendering
  host: {
    ...host,
    readFile: async (path: string) => {
      const text = await host.readFile(path);
      await renderer.prepare(text);
      return text;
    },
  },
  renderer,
}).catch((err: unknown) => {
  const el = document.getElementById("echo");
  if (el) el.textContent = `Startup failed: ${err instanceof Error ? err.message : String(err)}`;
  throw err;
});
