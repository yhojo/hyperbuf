// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Rendering of the split tree and windows. Keeps each window's reading position (scroll) and
// preserves the reader's position even when the height changes due to external updates, history moves or Mermaid rendering.

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

/** Rendering statistics (shown on the status line). */
export interface RenderStats {
  ms: number;
  diagrams: string;
}

export interface ViewsOptions {
  frame: HTMLElement;
  model: Model;
  renderer: Renderer;
  /** Turns the absolute path of a local image into a loadable URL. */
  resolveResource: (path: string) => string;
  /** The host's directory (used to shorten `~` in buffer names). */
  home: string;
  /** Git branch name of the directory (for the mode line). Not shown on shells without it. */
  vcsBranch?: (dir: string) => Promise<string | null>;
  /** A link in a window was chosen (click). */
  onFollow(win: Win, href: string): void;
  /** A window was chosen (click). */
  onSelect(win: Win): void;
  /** The display was updated or the reading position moved (a trigger for saving the session). */
  onChange?(): void;
}

interface WinView {
  el: HTMLElement;
  /** Mode line (below the window). Shows name, position and history like the Emacs mode line. */
  modeLine: {
    el: HTMLElement;
    name: HTMLElement;
    pos: HTMLElement;
    hist: HTMLElement;
    branch: HTMLElement;
  };
  /** Coalesces mode line position updates into one frame per scroll. */
  modeLinePending: boolean;
  /** Directory and version of the buffer for which the branch name was fetched (not refetched if the same). */
  branchKey: string | null;
  content: HTMLElement;
  lastEntry: HistoryEntry | null;
  lastKey: string | null;
  /** The last rendered body. Used to find the first changed line on an external update. */
  lastText: string | null;
  linkIndex: number;
  /** Scroll position set programmatically. A scroll event matching it is not a reader's action. */
  expectScroll: number | null;
  renderToken: number;
  /** Function that recomputes the current reading position from the current layout. */
  computeTop: (() => number) | null;
}

export class Views {
  readonly stats: RenderStats = { ms: 0, diagrams: "" };
  /** On an external update, move to the first changed place (`toggle-follow-updates`). */
  followUpdates = false;
  /** Show the Git branch name in the mode line (setting `modeLineVcsBranch`). */
  showVcsBranch = true;
  private readonly views = new Map<number, WinView>();
  private layoutSig = "";
  /** Buffer identity (absolute path) -> display name (uniquified). */
  private names = new Map<string, string>();
  private lastContextTarget: Element | null = null;
  private readonly opts: ViewsOptions;

  constructor(opts: ViewsOptions) {
    this.opts = opts;
  }

  /** The view of the selected window. */
  selected(): WinView {
    const view = this.views.get(this.opts.model.selected);
    if (!view) throw new Error("Selected window has no view");
    return view;
  }

  scrollBy(dy: number): void {
    this.selected().content.scrollBy({ top: dy });
  }

  /** The element of a window's body (undefined if none). */
  contentOf(winId: number): HTMLElement | undefined {
    return this.views.get(winId)?.content;
  }

  /** Scrolls the selected window to the given position (top edge). */
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
   * Selects links of the selected window in order (TAB / S-TAB).
   * When none is selected yet, or the selected link is off screen, start from the **visible range**
   * (TAB: the first visible link; S-TAB: the last visible link). It does not go back to the start of the document.
   */
  moveLink(dir: 1 | -1): void {
    const view = this.selected();
    const links = [...view.content.querySelectorAll("a")];
    if (!links.length) return;
    const box = view.content.getBoundingClientRect();
    // Whether it is visible on screen (the link's top edge is inside the screen)
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
        // No visible link: the nearest one after (TAB) / before (S-TAB) the screen. If none, the end
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

  /** The most recently right-clicked element ("edit in editor" uses it to find the pointed location). */
  contextTarget(): Element | null {
    return this.lastContextTarget;
  }

  /** href of the selected link. */
  focusedHref(): string | null {
    const view = this.selected();
    return view.content.querySelectorAll("a")[view.linkIndex]?.getAttribute("href") ?? null;
  }

  /**
   * Re-renders windows that have diagrams (Mermaid). Diagram colors are fixed at render time, so call this
   * when the appearance (light / dark) changes. The reading position is kept, as with external updates.
   */
  redrawDiagrams(): void {
    for (const view of this.views.values()) {
      if (view.content.querySelector(".mermaid-diagram, .render-error")) view.lastKey = null;
    }
    this.refresh();
  }

  /** Re-renders all windows to match the model state. */
  refresh(): void {
    const { model, frame } = this.opts;
    this.names = uniquifyNames([...model.buffers.keys()], this.opts.home);
    // Re-attach the DOM only when the split structure changed. Re-attaching loses scroll positions,
    // so in that case reapply the saved positions in all windows.
    const sig = signature(model.root);
    const relayout = sig !== this.layoutSig;
    if (relayout) {
      this.layoutSig = sig;
      frame.replaceChildren(this.build(model.root));
      const live = new Set(windows(model).map((w) => w.id));
      for (const id of this.views.keys()) if (!live.has(id)) this.views.delete(id);
    }
    // The root element has no ratio (cleared so that a previous ratio does not remain when a split is dissolved and a child is promoted to the root)
    if (frame.firstElementChild instanceof HTMLElement) frame.firstElementChild.style.flexGrow = "";
    this.applyRatios(model.root, frame.firstElementChild);
    for (const win of windows(model)) {
      const view = this.viewOf(win);
      if (relayout) view.lastEntry = null;
      this.update(win, view);
    }
    this.opts.onChange?.();
  }

  /** Reflects the split ratios into the DOM (no rebuild, so scroll positions are not lost). */
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

  /** The split element (made by `build`). Used to derive ratios from px. */
  private readonly splitEls = new WeakMap<LayoutNode, HTMLElement>();

  /**
   * Widens the selected window by `px` in direction `dir` (narrows it if negative).
   * @returns false if there is no split in that direction and it cannot be widened
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
   * If the selected window shows the whole document and still has room to spare, shrink it to exactly fit the height
   * (`shrink-window-if-larger-than-buffer`)。
   * @returns "shrunk" shrunk / "fits" no spare room / "sole" no vertical split
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
    // Height to the end of the document + the window frame (mode line etc.). The bottom margin of the body (for scrolling) is not included
    const chrome = view.el.offsetHeight - view.content.clientHeight;
    const wanted = last.offsetTop + last.offsetHeight + 8 + chrome;
    const excess = view.el.offsetHeight - wanted;
    if (excess <= 1) return "fits";
    resizeWindow(model, win, "col", -excess / el.clientHeight);
    this.refresh();
    return "shrunk";
  }

  /**
   * Move the boundary by dragging the mode line (as in Emacs). On the mode line body, the lower (vertical) boundary moves;
   * at the right end, the right (horizontal) boundary moves along with it.
   */
  private bindModeLineDrag(win: Win, view: WinView): void {
    const bar = view.modeLine.el;
    const { model } = this.opts;
    /** Width (px) regarded as the right end. */
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
        // Even if capture fails, movement over the bar is still picked up
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
    // The mode line is below the window, as in Emacs. The selected window is inverted dark (CSS)
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

  /** Updates the mode line position (`Top` / `Bot` / `All` / `NN%`) and the line number at the top of the screen (`L40`). */
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

  /** Refetch branch names of all windows (when the app becomes active; follows switches made in a terminal etc.). */
  refreshBranches(): void {
    for (const view of this.views.values()) view.branchKey = null;
    this.refresh();
  }

  /**
   * Branch name on the mode line. Asks the shell when a buffer is shown, switched or reloaded (no watching).
   * Not shown for virtual buffers (search results etc.) and for buffers with no Git root.
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
        // If we moved to another buffer while querying, discard
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
      // No open buffer (just after startup, etc.)
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
      // On an external update (the same document's version changed), keep the reading position based on headings
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
          // Show the first changed place near the top of the screen and briefly highlight it
          const at = () => findAnchor(view.content, `line:${changedLine}`);
          view.computeTop = () => Math.max(0, (at()?.offsetTop ?? 0) - 40);
          at()?.classList.add("changed-flash");
        }
        this.setScroll(view, view.computeTop());
        entry.scroll = view.content.scrollTop;
      }
      view.lastKey = key;
      if (!reload) view.lastEntry = null; // Apply the position as a new display
      // Mermaid changes height after rendering, so refetch the position if the reader has not moved
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
