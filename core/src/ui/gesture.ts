// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Trackpad / mouse gestures for moving in the reference history (setting `gestureNavigation`).
//
// - Two-finger horizontal swipe: right = back, left = forward (the default macOS direction, "natural scrolling" on).
// - Mouse back / forward buttons (button 3 / 4).
//
// WebKit's own history gestures are not used: the reference history is the Web core's, not WebKit's.
// The decision logic here is pure so it can be tested without a DOM; `installGestures` does the wiring.

import type { Win } from "../model.ts";

export type HistoryDirection = "back" | "forward";

/** Horizontal distance (px) within `SWIPE_WINDOW_MS` that counts as a swipe. */
export const SWIPE_THRESHOLD_PX = 70;
/** Only wheel events this recent (ms) are summed, so earlier scrolling does not count toward or against a swipe. */
export const SWIPE_WINDOW_MS = 250;
/** The horizontal distance must exceed this multiple of the vertical one in the window (ignores slightly tilted vertical scrolling). */
export const SWIPE_DOMINANCE = 2;
/** Horizontal wheel events further apart than this (ms) belong to different swipes. */
export const GESTURE_IDLE_MS = 200;
/**
 * After a swipe fires, its inertia tail keeps the swipe locked so it does not navigate twice. A new swipe made before the tail
 * has died out is recognised by the movement speeding up again (a per-event distance of at least `RISE_MIN_PX` and
 * `RISE_RATIO` times the slowest event since the lock) or by turning around (at least `REVERSE_MIN_PX` the other way).
 */
export const RISE_MIN_PX = 14;
export const RISE_RATIO = 4;
/** A speed-up is not taken as a new swipe within this time (ms) of the last one firing: a long swipe has uneven speed. */
export const RISE_COOLDOWN_MS = 150;
export const REVERSE_MIN_PX = 8;

/** The scroll-related state of one element on the path from the event target up to the window content. */
export interface ScrollAxisInfo {
  overflowX: string;
  scrollLeft: number;
  scrollWidth: number;
  clientWidth: number;
}

/** Whether something under the pointer can still scroll horizontally in the direction of `dx` (then the swipe is a scroll, not navigation). */
export function canScrollHorizontally(path: readonly ScrollAxisInfo[], dx: number): boolean {
  return path.some((el) => {
    if (el.overflowX !== "auto" && el.overflowX !== "scroll") return false;
    const max = el.scrollWidth - el.clientWidth;
    if (max <= 1) return false;
    return dx < 0 ? el.scrollLeft > 0 : el.scrollLeft < max - 1;
  });
}

/**
 * Turns a stream of wheel events into at most one navigation per swipe.
 * A swipe is a stretch of horizontal wheel events with no gap over `GESTURE_IDLE_MS`. Once it fires it stays locked, so the inertia
 * tail does not navigate twice, until the events stop or a new swipe is recognised inside the tail (see `RISE_MIN_PX`).
 * A swipe that starts over something that scrolls horizontally is left alone until it ends. Only the last `SWIPE_WINDOW_MS`
 * of movement is judged, and vertical movement in it counts against the swipe.
 */
export class SwipeTracker {
  private lastHorizontal = Number.NEGATIVE_INFINITY;
  private recent: { dx: number; dy: number; time: number }[] = [];
  private lock: "fired" | "blocked" | null = null;
  private lockSign = 0;
  private firedAt = Number.NEGATIVE_INFINITY;
  /** The smallest horizontal event since the swipe fired (the bottom of its decaying tail). */
  private slowest = Number.POSITIVE_INFINITY;

  /**
   * Feeds one wheel event. `blocked(dx)` is asked once per swipe, when it starts
   * (true: the pointer is over horizontally scrollable content, so the whole swipe is left alone).
   */
  feed(
    dx: number,
    dy: number,
    time: number,
    blocked: (dx: number) => boolean,
  ): HistoryDirection | null {
    if (dx !== 0) {
      const size = Math.abs(dx);
      if (time - this.lastHorizontal > GESTURE_IDLE_MS) {
        this.lock = blocked(dx) ? "blocked" : null;
      } else if (this.lock === "fired") {
        const turned = Math.sign(dx) !== this.lockSign && size >= REVERSE_MIN_PX;
        const sped =
          time - this.firedAt >= RISE_COOLDOWN_MS &&
          size >= Math.max(RISE_MIN_PX, RISE_RATIO * this.slowest);
        if (turned || sped) {
          this.recent = [];
          this.lock = blocked(dx) ? "blocked" : null;
        } else {
          this.slowest = Math.min(this.slowest, size);
        }
      }
      this.lastHorizontal = time;
    }
    this.recent.push({ dx, dy, time });
    while (this.recent[0] && time - this.recent[0].time > SWIPE_WINDOW_MS) this.recent.shift();
    if (this.lock || dx === 0) return null;
    let sumX = 0;
    let sumY = 0;
    for (const e of this.recent) {
      sumX += e.dx;
      sumY += e.dy;
    }
    if (Math.abs(sumX) < SWIPE_THRESHOLD_PX) return null;
    if (Math.abs(sumX) < SWIPE_DOMINANCE * Math.abs(sumY)) return null;
    this.lock = "fired";
    this.lockSign = Math.sign(sumX);
    this.firedAt = time;
    this.slowest = Math.abs(dx);
    this.recent = [];
    // Fingers moving right scroll the content left (negative deltaX): that is "back", as in Safari
    return sumX < 0 ? "back" : "forward";
  }
}

/** Maps a MouseEvent button to a direction (3: the mouse's back button, 4: forward). */
export function buttonDirection(button: number): HistoryDirection | null {
  return button === 3 ? "back" : button === 4 ? "forward" : null;
}

export interface GestureOptions {
  /** Window whose content contains the element (null: not inside a window). */
  windowOf(target: Element): Win | null;
  /** Select the window and move in its history. */
  navigate(win: Win, direction: HistoryDirection): void;
  /** Gestures are ignored while this returns false (minibuffer input, setting off). */
  enabled(): boolean;
  /** The element that scrolls the window (the path from the target stops here). */
  contentOf(win: Win): HTMLElement | undefined;
}

/** Listens for swipes and mouse buttons. Returns a function that removes the listeners. */
export function installGestures(options: GestureOptions): () => void {
  const tracker = new SwipeTracker();
  const pathOf = (target: Element, content: HTMLElement): ScrollAxisInfo[] => {
    const path: ScrollAxisInfo[] = [];
    for (let el: Element | null = target; el; el = el.parentElement) {
      path.push({
        overflowX: getComputedStyle(el).overflowX,
        scrollLeft: el.scrollLeft,
        scrollWidth: el.scrollWidth,
        clientWidth: el.clientWidth,
      });
      if (el === content) break;
    }
    return path;
  };
  const onWheel = (e: WheelEvent): void => {
    // ctrl + wheel is pinch zoom; vertical-only events can never navigate
    if (e.ctrlKey || e.deltaX === 0 || !options.enabled()) return;
    if (!(e.target instanceof Element)) return;
    const win = options.windowOf(e.target);
    const content = win && options.contentOf(win);
    if (!win || !content) return;
    const target = e.target;
    const direction = tracker.feed(e.deltaX, e.deltaY, e.timeStamp, (dx) =>
      canScrollHorizontally(pathOf(target, content), dx),
    );
    if (direction) options.navigate(win, direction);
  };
  const onMouseUp = (e: MouseEvent): void => {
    const direction = buttonDirection(e.button);
    if (!direction || !options.enabled()) return;
    if (!(e.target instanceof Element)) return;
    const win = options.windowOf(e.target);
    if (!win) return;
    e.preventDefault();
    options.navigate(win, direction);
  };
  // Some WebKit versions also navigate on these buttons by default; the mousedown guard keeps the page from reacting
  const onMouseDown = (e: MouseEvent): void => {
    if (buttonDirection(e.button) && options.enabled()) e.preventDefault();
  };
  window.addEventListener("wheel", onWheel, { passive: true });
  window.addEventListener("mouseup", onMouseUp);
  window.addEventListener("mousedown", onMouseDown);
  return () => {
    window.removeEventListener("wheel", onWheel);
    window.removeEventListener("mouseup", onMouseUp);
    window.removeEventListener("mousedown", onMouseDown);
  };
}
