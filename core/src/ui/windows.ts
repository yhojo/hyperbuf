// 分割ツリーと window の描画。window ごとの閲覧位置(スクロール)を保ち、
// 外部更新・履歴の移動・Mermaid の描画で高さが変わっても、読み手の位置を保つ。

import type { HistoryEntry, LayoutNode, Model, Win } from "../model.ts";
import { currentEntry, windows } from "../model.ts";
import type { Renderer } from "../pipeline.ts";
import { findAnchor, visibleAnchor } from "./anchors.ts";
import { hydrateDiagrams } from "./diagrams.ts";

/** 描画の統計(ステータス行に出す)。 */
export interface RenderStats {
  ms: number;
  diagrams: string;
}

export interface ViewsOptions {
  frame: HTMLElement;
  model: Model;
  renderer: Renderer;
  /** ローカル画像の相対パスを、読み込める URL にする。 */
  resolveResource: (path: string) => string;
  /** window 内のリンクが選ばれた(クリック)。 */
  onFollow(win: Win, href: string): void;
  /** window が選ばれた(クリック)。 */
  onSelect(win: Win): void;
}

interface WinView {
  el: HTMLElement;
  header: HTMLElement;
  content: HTMLElement;
  lastEntry: HistoryEntry | null;
  lastKey: string | null;
  linkIndex: number;
  /** プログラムで設定したスクロール位置。これと一致するスクロールイベントは、読み手の操作ではない。 */
  expectScroll: number | null;
  renderToken: number;
  /** いまの閲覧位置を、現在のレイアウトから求め直す関数。 */
  computeTop: (() => number) | null;
}

export class Views {
  readonly stats: RenderStats = { ms: 0, diagrams: "" };
  private readonly views = new Map<number, WinView>();
  private layoutSig = "";
  private lastContextTarget: Element | null = null;
  private readonly opts: ViewsOptions;

  constructor(opts: ViewsOptions) {
    this.opts = opts;
  }

  /** 選択中の window の view。 */
  selected(): WinView {
    const view = this.views.get(this.opts.model.selected);
    if (!view) throw new Error("選択中の window に view がありません");
    return view;
  }

  scrollBy(dy: number): void {
    this.selected().content.scrollBy({ top: dy });
  }

  pageHeight(): number {
    return this.selected().content.clientHeight;
  }

  /** 選択中の window のリンクを、順に選ぶ(TAB / S-TAB)。 */
  moveLink(dir: 1 | -1): void {
    const view = this.selected();
    const links = [...view.content.querySelectorAll("a")];
    if (!links.length) return;
    view.linkIndex =
      view.linkIndex < 0
        ? dir > 0
          ? 0
          : links.length - 1
        : (view.linkIndex + dir + links.length) % links.length;
    links.forEach((a, i) => a.classList.toggle("link-focus", i === view.linkIndex));
    links[view.linkIndex]?.scrollIntoView({ block: "nearest" });
  }

  /** 直近に右クリックした要素(「エディタで編集」が、指した場所を求めるのに使う)。 */
  contextTarget(): Element | null {
    return this.lastContextTarget;
  }

  /** 選択されているリンクの href。 */
  focusedHref(): string | null {
    const view = this.selected();
    return view.content.querySelectorAll("a")[view.linkIndex]?.getAttribute("href") ?? null;
  }

  /** model の状態に合わせて、全 window を描画し直す。 */
  refresh(): void {
    const { model, frame } = this.opts;
    // 分割構成が変わったときだけ DOM を付け替える。付け替えるとスクロール位置が失われるので、
    // そのときは全 window で保存済みの位置を適用し直す。
    const sig = signature(model.root);
    const relayout = sig !== this.layoutSig;
    if (relayout) {
      this.layoutSig = sig;
      frame.replaceChildren(this.build(model.root));
      const live = new Set(windows(model).map((w) => w.id));
      for (const id of this.views.keys()) if (!live.has(id)) this.views.delete(id);
    }
    for (const win of windows(model)) {
      const view = this.viewOf(win);
      if (relayout) view.lastEntry = null;
      this.update(win, view);
    }
  }

  private build(node: LayoutNode): HTMLElement {
    if (node.type === "leaf") return this.viewOf(node.win).el;
    const el = document.createElement("div");
    el.className = `split ${node.dir}`;
    el.append(...node.children.map((c) => this.build(c)));
    return el;
  }

  private viewOf(win: Win): WinView {
    const existing = this.views.get(win.id);
    if (existing) return existing;
    const el = document.createElement("section");
    el.className = "win";
    const header = document.createElement("div");
    header.className = "win-header";
    const content = document.createElement("div");
    content.className = "content";
    el.append(header, content);
    const view: WinView = {
      el,
      header,
      content,
      lastEntry: null,
      lastKey: null,
      linkIndex: -1,
      expectScroll: null,
      renderToken: 0,
      computeTop: null,
    };
    content.addEventListener("scroll", () => {
      if (view.expectScroll !== null && Math.abs(content.scrollTop - view.expectScroll) < 1) return;
      view.expectScroll = null;
      const entry = currentEntry(win);
      if (entry) entry.scroll = content.scrollTop;
    });
    content.addEventListener("contextmenu", (e) => {
      this.opts.onSelect(win);
      this.lastContextTarget = e.target instanceof Element ? e.target : null;
    });
    content.addEventListener("click", (e) => {
      this.opts.onSelect(win);
      const a = (e.target as Element).closest("a");
      if (a) {
        e.preventDefault();
        this.opts.onFollow(win, a.getAttribute("href") ?? "");
      }
    });
    this.views.set(win.id, view);
    return view;
  }

  private setScroll(view: WinView, top: number): void {
    view.expectScroll = top;
    view.content.scrollTop = top;
  }

  private update(win: Win, view: WinView): void {
    const { model, renderer, resolveResource } = this.opts;
    const entry = currentEntry(win);
    if (!entry) return;
    const buf = model.buffers.get(entry.path);
    if (!buf) return;
    const key = `${entry.path}@${buf.version}`;
    const selected = win.id === model.selected;
    view.el.classList.toggle("selected", selected);
    view.header.textContent = `${selected ? "●" : "○"} ${entry.path}${entry.anchor ? "#" + entry.anchor : ""}   [履歴 ${win.index + 1}/${win.history.length}]`;

    if (view.lastKey !== key) {
      // 外部更新(同じ文書の版が変わった)なら、見出し基準で閲覧位置を維持する
      const reload = view.lastEntry === entry;
      const anchor = reload ? visibleAnchor(view.content) : null;
      const ratio = reload ? view.content.scrollTop / Math.max(1, view.content.scrollHeight) : 0;
      const { html, ms } = renderer.renderMarkdown(buf.text, {
        docPath: entry.path,
        resolveResource,
      });
      this.stats.ms = ms;
      view.content.innerHTML = `<div class="markdown-body">${html}</div>`;
      view.linkIndex = -1;
      const token = ++view.renderToken;
      if (reload) {
        view.computeTop = () => {
          const target =
            anchor && view.content.querySelector<HTMLElement>(`#${CSS.escape(anchor.id)}`);
          return target ? target.offsetTop + anchor.delta : view.content.scrollHeight * ratio;
        };
        this.setScroll(view, view.computeTop());
        entry.scroll = view.content.scrollTop;
      }
      view.lastKey = key;
      if (!reload) view.lastEntry = null; // 新しい表示として位置を適用する
      // Mermaid は描画後に高さが変わるので、読み手が動かしていなければ位置を取り直す
      queueMicrotask(() => void this.settleDiagrams(view, entry, token));
    }
    if (view.lastEntry !== entry) {
      const viaAnchor = !entry.scroll && entry.anchor;
      view.computeTop = viaAnchor
        ? () => findAnchor(view.content, entry.anchor ?? "")?.offsetTop ?? 0
        : () => entry.scroll;
      this.setScroll(view, view.computeTop());
      entry.scroll = view.content.scrollTop;
      view.linkIndex = -1;
      view.lastEntry = entry;
    }
  }

  private async settleDiagrams(view: WinView, entry: HistoryEntry, token: number): Promise<void> {
    const before = view.content.scrollTop;
    const info = await hydrateDiagrams(view.content);
    if (token !== view.renderToken) return;
    this.stats.diagrams = info.count
      ? `図 ${info.count}件(${info.ms.toFixed(0)}ms${info.errors ? `, 失敗${info.errors}` : ""})`
      : "";
    if (view.content.scrollTop === before && view.computeTop) {
      this.setScroll(view, view.computeTop());
      entry.scroll = view.content.scrollTop;
    }
  }
}

function signature(node: LayoutNode): string {
  return node.type === "leaf"
    ? `w${node.win.id}`
    : `${node.dir}(${node.children.map(signature).join(",")})`;
}
