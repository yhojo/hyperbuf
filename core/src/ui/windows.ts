// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// 分割ツリーと window の描画。window ごとの閲覧位置(スクロール)を保ち、
// 外部更新・履歴の移動・Mermaid の描画で高さが変わっても、読み手の位置を保つ。

import { firstChangedLine } from "../diff.ts";
import type { HistoryEntry, LayoutNode, Model, Win } from "../model.ts";
import {
  boundaryBelow,
  boundaryRight,
  clampRatio,
  currentEntry,
  isVirtualPath,
  resizableSplit,
  resizeWindow,
  selectedWindow,
  windows,
} from "../model.ts";
import { dirname } from "../paths.ts";
import type { Renderer } from "../pipeline.ts";
import { uniquifyNames } from "../names.ts";
import { findAnchor, topSourceLine, visibleAnchor } from "./anchors.ts";
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
  /** ローカル画像の絶対パスを、読み込める URL にする。 */
  resolveResource: (path: string) => string;
  /** ホストのディレクトリ(バッファ名の `~` の短縮に使う)。 */
  home: string;
  /** ディレクトリの Git ブランチ名(モードライン用)。ないシェルでは、出さない。 */
  vcsBranch?: (dir: string) => Promise<string | null>;
  /** window 内のリンクが選ばれた(クリック)。 */
  onFollow(win: Win, href: string): void;
  /** window が選ばれた(クリック)。 */
  onSelect(win: Win): void;
  /** 表示を更新した、または、閲覧位置が動いた(セッションの保存の契機)。 */
  onChange?(): void;
}

interface WinView {
  el: HTMLElement;
  /** モードライン(window の下)。名前・位置・履歴を、Emacs のモードラインのように出す。 */
  modeLine: {
    el: HTMLElement;
    name: HTMLElement;
    pos: HTMLElement;
    hist: HTMLElement;
    branch: HTMLElement;
  };
  /** スクロールのたびに、モードラインの位置の更新を、1 フレームにまとめる。 */
  modeLinePending: boolean;
  /** ブランチ名を取得した、バッファのディレクトリと版(同じなら、取り直さない)。 */
  branchKey: string | null;
  content: HTMLElement;
  lastEntry: HistoryEntry | null;
  lastKey: string | null;
  /** 最後に描画した本文。外部更新で、最初に変わった行を求めるのに使う。 */
  lastText: string | null;
  linkIndex: number;
  /** プログラムで設定したスクロール位置。これと一致するスクロールイベントは、読み手の操作ではない。 */
  expectScroll: number | null;
  renderToken: number;
  /** いまの閲覧位置を、現在のレイアウトから求め直す関数。 */
  computeTop: (() => number) | null;
}

export class Views {
  readonly stats: RenderStats = { ms: 0, diagrams: "" };
  /** 外部更新のとき、最初に変わった場所へ移る(`toggle-follow-updates`)。 */
  followUpdates = false;
  /** モードラインに Git のブランチ名を出す(設定 `modeLineVcsBranch`)。 */
  showVcsBranch = true;
  private readonly views = new Map<number, WinView>();
  private layoutSig = "";
  /** バッファの識別(絶対パス)→ 表示名(uniquify 済み)。 */
  private names = new Map<string, string>();
  private lastContextTarget: Element | null = null;
  private readonly opts: ViewsOptions;

  constructor(opts: ViewsOptions) {
    this.opts = opts;
  }

  /** 選択中の window の view。 */
  selected(): WinView {
    const view = this.views.get(this.opts.model.selected);
    if (!view) throw new Error("Selected window has no view");
    return view;
  }

  scrollBy(dy: number): void {
    this.selected().content.scrollBy({ top: dy });
  }

  /** window の本文の要素(なければ undefined)。 */
  contentOf(winId: number): HTMLElement | undefined {
    return this.views.get(winId)?.content;
  }

  /** 選択中の window を、指定の位置(上端)にスクロールする。 */
  scrollTo(top: number): void {
    this.selected().content.scrollTo({ top });
  }

  scrollTop(): number {
    return this.selected().content.scrollTop;
  }

  scrollHeight(): number {
    return this.selected().content.scrollHeight;
  }

  pageHeight(): number {
    return this.selected().content.clientHeight;
  }

  /**
   * 選択中の window のリンクを、順に選ぶ(TAB / S-TAB)。
   * まだ選んでいない、または、選んでいるリンクが画面の外に出ているときは、**見えている範囲**から始める
   * (TAB は、見えている最初のリンク。S-TAB は、見えている最後のリンク)。文書の先頭へは戻らない。
   */
  moveLink(dir: 1 | -1): void {
    const view = this.selected();
    const links = [...view.content.querySelectorAll("a")];
    if (!links.length) return;
    const box = view.content.getBoundingClientRect();
    // 画面に見えているか(リンクの上端が、画面の中にある)
    const visible = (a: Element): boolean => {
      const r = a.getBoundingClientRect();
      return r.top >= box.top - 1 && r.top < box.bottom;
    };
    const focused = view.linkIndex >= 0 ? links[view.linkIndex] : undefined;
    if (!focused || !visible(focused)) {
      const shown = links.map((a, i) => (visible(a) ? i : -1)).filter((i) => i >= 0);
      if (shown.length) {
        view.linkIndex = (dir > 0 ? shown[0] : shown[shown.length - 1]) as number;
      } else {
        // 見えているリンクがない: 画面より後ろ(TAB)・前(S-TAB)の、最も近いもの。なければ、端
        const below = links.findIndex((a) => a.getBoundingClientRect().top >= box.bottom);
        const above = links
          .map((a) => a.getBoundingClientRect().bottom <= box.top)
          .lastIndexOf(true);
        view.linkIndex = dir > 0 ? (below >= 0 ? below : 0) : above >= 0 ? above : links.length - 1;
      }
    } else {
      view.linkIndex = (view.linkIndex + dir + links.length) % links.length;
    }
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

  /**
   * 図(Mermaid)のある window を、描画し直す。図は、描画時に色が決まるので、外観(ライト / ダーク)が
   * 切り替わったときに、呼ぶ。閲覧位置は、外部更新のときと同じく、保つ。
   */
  redrawDiagrams(): void {
    for (const view of this.views.values()) {
      if (view.content.querySelector(".mermaid-diagram, .render-error")) view.lastKey = null;
    }
    this.refresh();
  }

  /** model の状態に合わせて、全 window を描画し直す。 */
  refresh(): void {
    const { model, frame } = this.opts;
    this.names = uniquifyNames([...model.buffers.keys()], this.opts.home);
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
    // 根の要素は、比率を持たない(分割が解消されて、子が根に上がったとき、前の比率が残らないように消す)
    if (frame.firstElementChild instanceof HTMLElement) frame.firstElementChild.style.flexGrow = "";
    this.applyRatios(model.root, frame.firstElementChild);
    for (const win of windows(model)) {
      const view = this.viewOf(win);
      if (relayout) view.lastEntry = null;
      this.update(win, view);
    }
    this.opts.onChange?.();
  }

  /** 分割の割合を DOM に反映する(再構築はしない。スクロール位置を失わないため)。 */
  private applyRatios(node: LayoutNode, el: Element | null): void {
    if (node.type !== "split" || !el) return;
    const ratio = node.ratio ?? 0.5;
    node.children.forEach((child, i) => {
      const childEl = el.children[i];
      if (childEl instanceof HTMLElement)
        childEl.style.flexGrow = String(i === 0 ? ratio : 1 - ratio);
      this.applyRatios(child, childEl ?? null);
    });
  }

  /** 分割の要素(`build` が作ったもの)。割合を px から求めるのに使う。 */
  private readonly splitEls = new WeakMap<LayoutNode, HTMLElement>();

  /**
   * 選択中の window を、`dir` の向きに `px` だけ広げる(負なら狭める)。
   * @returns その向きに分割がなく、広げられなければ false
   */
  resizeSelected(dir: "row" | "col", px: number): boolean {
    const { model } = this.opts;
    const win = selectedWindow(model);
    const found = resizableSplit(model, win, dir);
    const el = found && this.splitEls.get(found.node);
    if (!found || !el) return false;
    const size = dir === "col" ? el.clientHeight : el.clientWidth;
    if (size <= 0) return false;
    resizeWindow(model, win, dir, px / size);
    this.refresh();
    return true;
  }

  /**
   * 選択中の window が、文書の全体を表示してなお余るなら、ちょうど収まる高さまで縮める
   * (`shrink-window-if-larger-than-buffer`)。
   * @returns "shrunk" 縮めた / "fits" 余っていない / "sole" 上下の分割がない
   */
  shrinkToFit(): "shrunk" | "fits" | "sole" {
    const { model } = this.opts;
    const win = selectedWindow(model);
    const view = this.selected();
    const found = resizableSplit(model, win, "col");
    const el = found && this.splitEls.get(found.node);
    if (!found || !el) return "sole";
    const last = view.content.querySelector<HTMLElement>(".markdown-body")?.lastElementChild;
    if (!(last instanceof HTMLElement)) return "fits";
    // 文書の末尾までの高さ + window の枠(モードラインなど)。本文の下の余白(スクロール用)は、含めない
    const chrome = view.el.offsetHeight - view.content.clientHeight;
    const wanted = last.offsetTop + last.offsetHeight + 8 + chrome;
    const excess = view.el.offsetHeight - wanted;
    if (excess <= 1) return "fits";
    resizeWindow(model, win, "col", -excess / el.clientHeight);
    this.refresh();
    return "shrunk";
  }

  /**
   * モードラインのドラッグで、境界を動かす(Emacs と同じ)。モードラインの本体では、下の境界(縦方向)、
   * 右端では、右の境界(横方向)も、いっしょに動かす。
   */
  private bindModeLineDrag(win: Win, view: WinView): void {
    const bar = view.modeLine.el;
    const { model } = this.opts;
    /** 右端とみなす幅(px)。 */
    const EDGE = 24;
    const find = (node: LayoutNode | null) => {
      const el = node && this.splitEls.get(node);
      return node?.type === "split" && el ? { node, el } : null;
    };
    const targets = (e: PointerEvent) => {
      const atEdge = e.clientX >= bar.getBoundingClientRect().right - EDGE;
      const h = atEdge ? find(boundaryRight(model, win)) : null;
      return { v: h ? null : find(boundaryBelow(model, win)), h };
    };
    bar.addEventListener("pointermove", (e) => {
      if (e.buttons !== 0) return;
      const { v, h } = targets(e);
      bar.style.cursor = h ? "col-resize" : v ? "row-resize" : "";
    });
    bar.addEventListener("pointerdown", (e) => {
      const { v, h } = targets(e);
      if (e.button !== 0 || (!v && !h)) return;
      e.preventDefault();
      try {
        bar.setPointerCapture(e.pointerId);
      } catch {
        // 捕捉できなくても、バー上の移動は拾える
      }
      const start = {
        x: e.clientX,
        y: e.clientY,
        v: v?.node.ratio ?? 0.5,
        h: h?.node.ratio ?? 0.5,
      };
      const move = (ev: PointerEvent): void => {
        if (v && v.el.clientHeight > 0) {
          v.node.ratio = clampRatio(start.v + (ev.clientY - start.y) / v.el.clientHeight);
        }
        if (h && h.el.clientWidth > 0) {
          h.node.ratio = clampRatio(start.h + (ev.clientX - start.x) / h.el.clientWidth);
        }
        this.applyRatios(model.root, this.opts.frame.firstElementChild);
      };
      const end = (): void => {
        bar.removeEventListener("pointermove", move);
        bar.removeEventListener("pointerup", end);
        bar.removeEventListener("pointercancel", end);
        this.opts.onSelect(win);
        this.opts.onChange?.();
      };
      bar.addEventListener("pointermove", move);
      bar.addEventListener("pointerup", end);
      bar.addEventListener("pointercancel", end);
    });
  }

  private build(node: LayoutNode): HTMLElement {
    if (node.type === "leaf") return this.viewOf(node.win).el;
    const el = document.createElement("div");
    el.className = `split ${node.dir}`;
    el.append(...node.children.map((c) => this.build(c)));
    this.splitEls.set(node, el);
    return el;
  }

  private viewOf(win: Win): WinView {
    const existing = this.views.get(win.id);
    if (existing) return existing;
    const el = document.createElement("section");
    el.className = "win";
    // モードラインは、Emacs と同じく、window の下。選択中の window は、濃く反転する(CSS)
    const modeLineEl = document.createElement("div");
    modeLineEl.className = "mode-line";
    const modeLine = {
      el: modeLineEl,
      name: document.createElement("span"),
      pos: document.createElement("span"),
      hist: document.createElement("span"),
      branch: document.createElement("span"),
    };
    modeLine.name.className = "ml-name";
    modeLine.pos.className = "ml-pos";
    modeLine.hist.className = "ml-hist";
    modeLine.branch.className = "ml-branch";
    modeLineEl.append(modeLine.name, modeLine.pos, modeLine.hist, modeLine.branch);
    const content = document.createElement("div");
    content.className = "content";
    el.append(content, modeLineEl);
    const view: WinView = {
      el,
      modeLine,
      modeLinePending: false,
      branchKey: null,
      content,
      lastEntry: null,
      lastText: null,
      lastKey: null,
      linkIndex: -1,
      expectScroll: null,
      renderToken: 0,
      computeTop: null,
    };
    content.addEventListener("scroll", () => {
      this.scheduleModeLine(view);
      if (view.expectScroll !== null && Math.abs(content.scrollTop - view.expectScroll) < 1) return;
      view.expectScroll = null;
      const entry = currentEntry(win);
      if (entry) entry.scroll = content.scrollTop;
      this.opts.onChange?.();
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
    this.bindModeLineDrag(win, view);
    this.views.set(win.id, view);
    return view;
  }

  /** モードラインの位置(`Top` / `Bot` / `All` / `NN%`)と、画面の上端の行番号(`L40`)を更新する。 */
  private updateModeLinePosition(view: WinView): void {
    const { content, modeLine } = view;
    if (!content.querySelector(".markdown-body")) {
      modeLine.pos.textContent = "";
      return;
    }
    const max = content.scrollHeight - content.clientHeight;
    const position =
      max <= 1
        ? "All"
        : content.scrollTop <= 0
          ? "Top"
          : content.scrollTop >= max - 1
            ? "Bot"
            : `${Math.round((content.scrollTop / max) * 100)}%`;
    const line = topSourceLine(content);
    modeLine.pos.textContent = line === null ? position : `${position}  L${line}`;
  }

  /** 全 window のブランチ名を、取り直す(アプリがアクティブになったとき。ターミナルなどでの切り替えに追従する)。 */
  refreshBranches(): void {
    for (const view of this.views.values()) view.branchKey = null;
    this.refresh();
  }

  /**
   * モードラインのブランチ名。バッファの表示・切替・再読み込みのときに、シェルへ問い合わせる(監視はしない)。
   * 仮想バッファ(検索結果など)と、Git のルートがないバッファには、出さない。
   */
  private updateBranch(win: Win, view: WinView, key: string): void {
    const el = view.modeLine.branch;
    const path = currentEntry(win)?.path;
    const vcsBranch = this.opts.vcsBranch;
    if (!this.showVcsBranch || !vcsBranch || !path || isVirtualPath(path)) {
      el.textContent = "";
      view.branchKey = null;
      return;
    }
    if (view.branchKey === key) return;
    view.branchKey = key;
    void vcsBranch(dirname(path)).then(
      (branch) => {
        // 問い合わせている間に、別のバッファへ移っていたら、捨てる
        if (view.branchKey === key) el.textContent = branch ?? "";
      },
      () => {
        if (view.branchKey === key) el.textContent = "";
      },
    );
  }

  private scheduleModeLine(view: WinView): void {
    if (view.modeLinePending) return;
    view.modeLinePending = true;
    requestAnimationFrame(() => {
      view.modeLinePending = false;
      this.updateModeLinePosition(view);
    });
  }

  private setScroll(view: WinView, top: number): void {
    view.expectScroll = top;
    view.content.scrollTop = top;
  }

  private update(win: Win, view: WinView): void {
    const { model, renderer, resolveResource } = this.opts;
    const entry = currentEntry(win);
    const selected = win.id === model.selected;
    view.el.classList.toggle("selected", selected);
    if (!entry) {
      // 開いているバッファがない(起動直後など)
      view.modeLine.name.textContent = "(no buffer)";
      view.modeLine.pos.textContent = "";
      view.modeLine.hist.textContent = "";
      view.modeLine.branch.textContent = "";
      view.branchKey = null;
      if (view.lastKey !== "empty") {
        view.content.innerHTML =
          '<div class="empty-state">Type C-x C-f to open a file (C-x p f: search under the base directory)</div>';
        view.lastKey = "empty";
        view.lastEntry = null;
      }
      return;
    }
    const buf = model.buffers.get(entry.path);
    if (!buf) return;
    const key = `${entry.path}@${buf.version}`;
    const name = this.names.get(entry.path) ?? entry.path;
    const gone = buf.missing ? "  (deleted; it may have been moved)" : "";
    view.modeLine.name.textContent = `${name}${gone}`;
    view.modeLine.hist.textContent = `[History ${win.index + 1}/${win.history.length}]${this.followUpdates ? " [Follow]" : ""}`;
    this.updateBranch(win, view, `${entry.path}@${buf.version}`);

    if (view.lastKey !== key) {
      // 外部更新(同じ文書の版が変わった)なら、見出し基準で閲覧位置を維持する
      const reload = view.lastEntry === entry;
      const anchor = reload ? visibleAnchor(view.content) : null;
      const ratio = reload ? view.content.scrollTop / Math.max(1, view.content.scrollHeight) : 0;
      const changedLine =
        reload && this.followUpdates && !!view.lastText
          ? firstChangedLine(view.lastText, buf.text)
          : null;
      view.lastText = buf.text;
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
        if (changedLine !== null) {
          // 最初に変わった場所を、画面の上寄りに出して、一瞬、目立たせる
          const at = () => findAnchor(view.content, `line:${changedLine}`);
          view.computeTop = () => Math.max(0, (at()?.offsetTop ?? 0) - 40);
          at()?.classList.add("changed-flash");
        }
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
    this.updateModeLinePosition(view);
  }

  private async settleDiagrams(view: WinView, entry: HistoryEntry, token: number): Promise<void> {
    const before = view.content.scrollTop;
    const info = await hydrateDiagrams(view.content);
    if (token !== view.renderToken) return;
    this.stats.diagrams = info.count
      ? `Diagrams ${info.count} (${info.ms.toFixed(0)}ms${info.errors ? `, ${info.errors} failed` : ""})`
      : "";
    if (view.content.scrollTop === before && view.computeTop) {
      this.setScroll(view, view.computeTop());
      entry.scroll = view.content.scrollTop;
    }
    this.updateModeLinePosition(view);
  }
}

function signature(node: LayoutNode): string {
  return node.type === "leaf"
    ? `w${node.win.id}`
    : `${node.dir}(${node.children.map(signature).join(",")})`;
}
