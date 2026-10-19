// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Mermaid の描画。DOM が要るので、HTML 文字列化の後に行う。重いので、図のある文書でだけ読み込む。
// 描画に失敗しても文書全体は止めず、その場にエラーとソースを表示する。

export interface DiagramStats {
  count: number;
  errors: number;
  ms: number;
}

type MermaidApi = (typeof import("mermaid"))["default"];

let mermaidPromise: Promise<MermaidApi> | null = null;
let diagramSeq = 0;

/** いまの外観(ライト / ダーク)に合う Mermaid のテーマ。 */
const currentTheme = (): "dark" | "default" =>
  window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "default";

function initializeMermaid(mermaid: MermaidApi): void {
  mermaid.initialize({
    startOnLoad: false,
    securityLevel: "strict",
    // Mermaid 12 の既定のレイアウトは ELK(elkjs。EPL-2.0)。GitHub と同じ見た目になる dagre(Mermaid 11 までの既定)に
    // 固定し、elkjs は同梱しない(build-options.mjs。docs/history/license-options.md)。図が `layout: elk` を指定すると、
    // その図は、図の位置にエラーとして表示される
    layout: "dagre",
    theme: currentTheme(),
    logLevel: "fatal",
  });
}

function loadMermaid(): Promise<MermaidApi> {
  mermaidPromise ??= import("mermaid").then(({ default: mermaid }) => {
    initializeMermaid(mermaid);
    return mermaid;
  });
  return mermaidPromise;
}

/**
 * 外観が切り替わったとき、Mermaid のテーマを、いまの外観に合わせ直す(図は、描画時に色が決まるので、
 * 呼び出し側が、表示中の図を描き直す)。まだ読み込んでいなければ、何もしない(読み込むときに、いまの外観になる)。
 */
export async function refreshMermaidTheme(): Promise<void> {
  if (mermaidPromise) initializeMermaid(await mermaidPromise);
}

export async function hydrateDiagrams(root: HTMLElement): Promise<DiagramStats> {
  const blocks = [...root.querySelectorAll<HTMLElement>("pre.mermaid-source")];
  if (!blocks.length) return { count: 0, errors: 0, ms: 0 };
  const t0 = performance.now();
  let errors = 0;
  const mermaid = await loadMermaid();
  for (const pre of blocks) {
    const source = pre.textContent ?? "";
    const id = `mmd-${++diagramSeq}`;
    const box = document.createElement("div");
    try {
      const { svg } = await mermaid.render(id, source);
      box.className = "mermaid-diagram";
      box.innerHTML = svg; // mermaid が strict モードで無害化した SVG
    } catch (err) {
      errors += 1;
      document.getElementById(`d${id}`)?.remove(); // 失敗時に body へ残る一時要素
      box.className = "render-error";
      const title = document.createElement("strong");
      title.textContent = "Mermaid rendering failed";
      const msg = document.createElement("pre");
      const text = err instanceof Error ? err.message : String(err);
      msg.textContent = text.split("\n").slice(0, 4).join("\n");
      const src = document.createElement("pre");
      src.textContent = source;
      box.append(title, msg, src);
    }
    pre.replaceWith(box);
  }
  return { count: blocks.length, errors, ms: performance.now() - t0 };
}
