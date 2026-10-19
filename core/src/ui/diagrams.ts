// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Mermaid rendering. Needs the DOM, so it runs after conversion to an HTML string. It is heavy, so it is loaded only for documents with diagrams.
// A rendering failure does not stop the whole document; the error and the source are shown in place.

export interface DiagramStats {
  count: number;
  errors: number;
  ms: number;
}

type MermaidApi = (typeof import("mermaid"))["default"];

let mermaidPromise: Promise<MermaidApi> | null = null;
let diagramSeq = 0;

/** Mermaid theme matching the current appearance (light / dark). */
const currentTheme = (): "dark" | "default" =>
  window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "default";

function initializeMermaid(mermaid: MermaidApi): void {
  mermaid.initialize({
    startOnLoad: false,
    securityLevel: "strict",
    // Mermaid 12's default layout is ELK (elkjs, EPL-2.0). Pin it to dagre (the default up to Mermaid 11), which looks the same as GitHub,
    // and do not bundle elkjs (build-options.mjs; docs/history/license-options.md). If a diagram specifies `layout: elk`,
    // that diagram is shown as an error in its place
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
 * When the appearance changes, re-fit the Mermaid theme to it (colors are fixed at render time,
 * so the caller re-renders the displayed diagrams). Does nothing if not loaded yet (it will use the current appearance when loaded).
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
      box.innerHTML = svg; // SVG sanitized by mermaid in strict mode
    } catch (err) {
      errors += 1;
      document.getElementById(`d${id}`)?.remove(); // temporary element left in body on failure
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
