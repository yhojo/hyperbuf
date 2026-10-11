// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// ブラウザ(WebView)でのエントリ。シェルが注入した `window.hyperbufHost` を使う。
// 無ければ、開発サーバーの HTTP API を使う(開発用)。

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
    /** シェルが注入する。 */
    hyperbufHost?: HyperbufHost;
    /** 自動検証(統合テスト・ヘッドレス)用の入口。利用者向けの API ではない。 */
    __hyperbuf?: AppHandle;
  }
}

const host = window.hyperbufHost ?? (await createDevHost());
// starry-night は既定で外部 CDN から WASM を取得するため、同梱したファイルを指す(local first)
const renderer = await createRenderer({ onigUrl: new URL(onigWasm, import.meta.url) });
window.__hyperbuf = await startApp({ host, renderer }).catch((err: unknown) => {
  const el = document.getElementById("echo");
  if (el) el.textContent = `起動に失敗: ${err instanceof Error ? err.message : String(err)}`;
  throw err;
});
