// 描画された文書の中のアンカー(見出し・行・脚注)を探す。

/** sanitize が id に付ける接頭辞。アプリの DOM との衝突を防ぐため、外してはならない。 */
export const ID_PREFIX = "user-content-";

/** "line:N" は、元の Markdown の N 行目(以前で最も近いブロック)を指す。 */
export function findAnchor(root: HTMLElement, anchor: string): HTMLElement | null {
  const m = /^line:(\d+)$/.exec(anchor);
  if (m) {
    const n = Number(m[1]);
    let best: HTMLElement | null = null;
    for (const el of root.querySelectorAll<HTMLElement>("[data-source-line]")) {
      if (Number(el.dataset["sourceLine"]) <= n) best = el;
      else if (best) break;
    }
    return best ?? root.querySelector<HTMLElement>("[data-source-line]");
  }
  return (
    root.querySelector<HTMLElement>(`#${CSS.escape(ID_PREFIX + anchor)}`) ??
    root.querySelector<HTMLElement>(`#${CSS.escape(anchor)}`)
  );
}

export interface VisibleAnchor {
  id: string;
  /** 画面の上端が、その要素の上端から何 px 下か。 */
  delta: number;
}

/** 画面の上端にいちばん近い(上側の) id つきの要素。外部更新後の位置の復元に使う。 */
export function visibleAnchor(content: HTMLElement): VisibleAnchor | null {
  let best: VisibleAnchor | null = null;
  for (const el of content.querySelectorAll<HTMLElement>("[id]")) {
    if (el.offsetTop <= content.scrollTop + 1) {
      best = { id: el.id, delta: content.scrollTop - el.offsetTop };
    }
  }
  return best;
}

export interface HeadingInfo {
  level: number;
  text: string;
  /** 接頭辞を除いたアンカー(`path#id` のリンクで使う)。 */
  id: string;
}

/** 見出しは描画後の DOM から取る(id は GitHub 方式で付くので、正規表現による解析とはずれ得る)。 */
export function headingsOf(content: HTMLElement): HeadingInfo[] {
  return [...content.querySelectorAll<HTMLElement>("h1,h2,h3,h4,h5,h6")].map((h) => ({
    level: Number(h.tagName.slice(1)),
    text: h.textContent ?? "",
    id: h.id.startsWith(ID_PREFIX) ? h.id.slice(ID_PREFIX.length) : h.id,
  }));
}
