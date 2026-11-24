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

type Theme = "dark" | "default";

/** Mermaid theme matching the current appearance (light / dark). */
const currentTheme = (): Theme =>
  window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "default";

/** A theme fixed regardless of the appearance (while printing: paper is white). */
let pinnedTheme: Theme | null = null;
/** The theme Mermaid was last initialized with. */
let appliedTheme: Theme | null = null;
/** Source of each rendered diagram, to draw it again in another theme without rendering the document again. */
const sources = new WeakMap<HTMLElement, string>();

function initializeMermaid(mermaid: MermaidApi): void {
  appliedTheme = pinnedTheme ?? currentTheme();
  mermaid.initialize({
    startOnLoad: false,
    securityLevel: "strict",
    // Mermaid 12's default layout is ELK (elkjs, EPL-2.0). Pin it to dagre (the default up to Mermaid 11), which looks the same as GitHub,
    // and do not bundle elkjs (build-options.mjs; docs/history/license-options.md). If a diagram specifies `layout: elk`,
    // that diagram is shown as an error in its place
    layout: "dagre",
    theme: appliedTheme,
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
 * so the caller re-renders the displayed diagrams when this returns true). Does nothing and returns false if Mermaid is
 * not loaded yet (it will use the current appearance when loaded), or if the theme stays the same: while printing,
 * the page is laid out as light for a moment and the theme is pinned (`pinDiagramTheme`).
 */
export async function refreshMermaidTheme(): Promise<boolean> {
  if (!mermaidPromise) return false;
  const mermaid = await mermaidPromise;
  if ((pinnedTheme ?? currentTheme()) === appliedTheme) return false;
  initializeMermaid(mermaid);
  return true;
}

/**
 * Fixes the diagram theme to `theme` (null: follow the appearance again) and, if that changes the theme, draws the
 * diagrams under `root` again in place. Only the drawings are replaced, so reading positions, selections and the
 * rest of the document are left alone. Used for printing: a dark diagram is unreadable on white paper.
 */
export async function pinDiagramTheme(theme: Theme | null, root: ParentNode): Promise<void> {
  pinnedTheme = theme;
  if (!(await refreshMermaidTheme())) return;
  const mermaid = await loadMermaid();
  for (const box of root.querySelectorAll<HTMLElement>(".mermaid-diagram")) {
    const source = sources.get(box);
    if (source === undefined) continue;
    const id = `mmd-${++diagramSeq}`;
    try {
      const { svg } = await mermaid.render(id, source);
      box.innerHTML = svg; // SVG sanitized by mermaid in strict mode
    } catch {
      document.getElementById(`d${id}`)?.remove(); // keep the previous drawing
    }
  }
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
      sources.set(box, source);
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
