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

function loadMermaid(): Promise<MermaidApi> {
  mermaidPromise ??= import("mermaid").then(({ default: mermaid }) => {
    const dark = window.matchMedia("(prefers-color-scheme: dark)").matches;
    mermaid.initialize({
      startOnLoad: false,
      securityLevel: "strict",
      theme: dark ? "dark" : "default",
      logLevel: "fatal",
    });
    return mermaid;
  });
  return mermaidPromise;
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
      title.textContent = "Mermaid の描画に失敗しました";
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
