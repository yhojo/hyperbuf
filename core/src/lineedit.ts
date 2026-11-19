// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Line editing for the minibuffer's input line (docs/dev/interaction-model.md §6.3): Emacs-style movement,
// kill and yank on a single line, with a kill ring. No DOM here; the minibuffer applies the result to its input field.
// Documents are never edited: this is the only place where HyperBuf edits text.

/** The input line and its selection (`start` <= `end`; a cursor is an empty selection). */
export interface Line {
  text: string;
  start: number;
  end: number;
  /** The selection was made backward, so point is at `start` (otherwise at `end`). */
  backward?: boolean;
}

export interface LineEdit {
  line: Line;
  /** Text to write to the system clipboard (a kill or a copy). */
  copy?: string;
}

export interface LineEditor {
  /**
   * Applies a line-editing key. null if `name` is not one (the caller handles it or leaves it to the default).
   * `clipboard` is the system clipboard's text, needed only for `YANK_KEY`.
   */
  key(name: string, line: Line, clipboard?: string | null): LineEdit | null;
  /** Something else happened to the line (typing, cursor movement, a new prompt): ends a run of kills or yanks. */
  reset(): void;
}

/** Number of kills kept. */
export const KILL_RING_LIMIT = 20;
/** The key that takes the system clipboard into the kill ring (the caller reads the clipboard for it). */
export const YANK_KEY = "C-y";

const KEYS = new Set([
  "C-a",
  "C-e",
  "C-f",
  "C-b",
  "M-f",
  "M-b",
  "C-d",
  "M-d",
  "M-DEL",
  "C-k",
  "C-u",
  "C-w",
  "M-w",
  "C-y",
  "M-y",
]);

export function isLineEditKey(name: string): boolean {
  return KEYS.has(name);
}

// A word is a run of letters, digits and combining marks. Everything else separates words,
// so the previous word of a path ends at `/`.
const WORD = "[\\p{L}\\p{N}\\p{M}]";
const WORD_FORWARD = new RegExp(`^(?:(?!${WORD}).)*${WORD}*`, "su");
const WORD_BACKWARD = new RegExp(`${WORD}*(?:(?!${WORD}).)*$`, "su");

const graphemes = new Intl.Segmenter(undefined, { granularity: "grapheme" });

function nextChar(text: string, at: number): number {
  for (const s of graphemes.segment(text.slice(at))) return at + s.segment.length;
  return at;
}

function previousChar(text: string, at: number): number {
  let last = 0;
  for (const s of graphemes.segment(text.slice(0, at))) last = s.index;
  return last;
}

function nextWord(text: string, at: number): number {
  return at + (WORD_FORWARD.exec(text.slice(at))?.[0].length ?? 0);
}

function previousWord(text: string, at: number): number {
  return at - (WORD_BACKWARD.exec(text.slice(0, at))?.[0].length ?? 0);
}

/** The part of clipboard text that fits a single-line input: its first non-empty line. */
export function clipboardLine(text: string | null | undefined): string {
  return (text ?? "").split(/\r\n|\r|\n/).find((line) => line !== "") ?? "";
}

const at = (text: string, point: number): Line => ({ text, start: point, end: point });

export function createLineEditor(limit: number = KILL_RING_LIMIT): LineEditor {
  /** Newest first. */
  let ring: string[] = [];
  /** The entry `C-y` yanks; `M-y` advances it, a new kill puts it back to the newest. */
  let pointer = 0;
  let last: "kill" | "yank" | null = null;
  /** The range the last yank inserted (what `M-y` replaces). */
  let yanked: [number, number] = [0, 0];
  /** The clipboard text already known (written by a kill here, or taken in by a yank): not taken in again. */
  let seen = "";

  const push = (text: string): void => {
    if (ring[0] !== text) ring = [text, ...ring].slice(0, limit);
    pointer = 0;
  };

  /** Kills `from`..`to`. Consecutive kills join into one entry, in the order of the text. */
  const kill = (line: Line, from: number, to: number, forward: boolean): LineEdit => {
    const killed = line.text.slice(from, to);
    if (!killed) return { line };
    const head = ring[0];
    if (last === "kill" && head !== undefined) {
      ring[0] = forward ? head + killed : killed + head;
      pointer = 0;
    } else push(killed);
    last = "kill";
    seen = ring[0] ?? "";
    return { line: at(line.text.slice(0, from) + line.text.slice(to), from), copy: seen };
  };

  const insert = (line: Line, from: number, to: number): LineEdit => {
    const text = ring[pointer] ?? "";
    yanked = [from, from + text.length];
    last = "yank";
    return { line: at(line.text.slice(0, from) + text + line.text.slice(to), yanked[1]) };
  };

  return {
    reset() {
      last = null;
    },
    key(name, line, clipboard) {
      if (!KEYS.has(name)) return null;
      const { text, start, end } = line;
      const point = line.backward ? start : end;
      const move = (to: number): LineEdit => {
        last = null;
        return { line: at(text, to) };
      };
      switch (name) {
        case "C-a":
          return move(0);
        case "C-e":
          return move(text.length);
        case "C-f":
          return move(nextChar(text, point));
        case "C-b":
          return move(previousChar(text, point));
        case "M-f":
          return move(nextWord(text, point));
        case "M-b":
          return move(previousWord(text, point));
        case "C-d": {
          // Deleting is not killing: nothing goes to the kill ring
          last = null;
          const to = start < end ? end : nextChar(text, start);
          return { line: at(text.slice(0, start) + text.slice(to), start) };
        }
        case "M-d":
          return kill(line, point, nextWord(text, point), true);
        case "M-DEL":
          return kill(line, previousWord(text, point), point, false);
        case "C-k":
          return kill(line, point, text.length, true);
        case "C-u":
          return kill(line, 0, point, false);
        case "C-w":
          // There is no mark: the region is the selection. A new kill, never joined to the previous one
          last = null;
          return kill(line, start, end, true);
        case "M-w": {
          last = null;
          const copied = text.slice(start, end);
          if (!copied) return { line };
          push(copied);
          seen = copied;
          return { line, copy: copied };
        }
        case "C-y": {
          // As in Emacs.app: what another app put on the clipboard becomes the newest kill
          const fromClipboard = clipboardLine(clipboard);
          if (fromClipboard && fromClipboard !== seen) {
            push(fromClipboard);
            seen = fromClipboard;
          }
          if (!ring.length) return { line };
          return insert(line, start, end);
        }
        case "M-y":
          if (last !== "yank" || !ring.length) return { line };
          pointer = (pointer + 1) % ring.length;
          return insert(line, yanked[0], yanked[1]);
      }
      return null;
    },
  };
}
