// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

/**
 * The boundary between the shell (the macOS app, etc.) and the Web core. The shell injects it as `window.hyperbufHost`.
 * The Web core uses no shell functionality other than through this.
 * Contract details: docs/dev/integration-protocol.md, docs/history/poc-navigation-results.md
 */
import type { SourceLocation } from "./locate.ts";

/** Result of `markLocation`. */
export interface MarkResult {
  ok: boolean;
  /** Whether the editor was invoked (whether the configured command was run). */
  triggered: boolean;
  /** A description to show to the user. */
  message: string;
}

/** The part of the user's settings (config.json) that the Web core uses. */
export interface HostConfig {
  /** Key sequence -> command name (`null` removes the default binding). */
  keybindings?: Record<string, string | null>;
  /** Whether to restore and save the previous state (window layout, history, reading positions) (default true). */
  restoreSession?: boolean;
  /** Turn `\_` in math back into `_` (compatibility with Marked 2 and others; default true). */
  mathUnescapeUnderscore?: boolean;
  /** When a file is updated externally, scroll to the start of the changed part (default false; toggled with `toggle-follow-updates`). */
  followUpdates?: boolean;
  /** Show the Git branch name in the mode line (default true; docs/dev/buffer-model.md §6.9). */
  modeLineVcsBranch?: boolean;
  /** Move in the reference history with a two-finger horizontal swipe and the mouse back / forward buttons (default true). */
  gestureNavigation?: boolean;
  /** Config problems the shell found (allow paths / warn paths, etc.). Shown under "config problems" in `C-h b`. */
  problems?: string[];
}

/** One entry of a one-level directory listing (only `.md` files and subdirectories). */
export interface DirEntry {
  name: string;
  dir: boolean;
}

export interface DirectoryListing {
  entries: DirEntry[];
  /** Cut off at the entry limit. */
  truncated: boolean;
  /** Reason if it could not be read or does not exist. */
  error?: string;
}

/** A recursive listing of `.md` files under a directory (`C-x p f`). */
export interface TreeListing {
  /** Paths relative to the origin (ascending). */
  files: string[];
  /** Cut off at the file count or time limit. */
  truncated: boolean;
  /** Reason it did not recurse (when the origin is `~` or `/`, etc.). */
  refused?: string;
  error?: string;
}

/**
 * Judgment of file access (docs/dev/file-access.md).
 *  - allow: can be read as is
 *  - confirm: a file under a warn path. Needs user confirmation (if approved, the `remember` path is remembered)
 */
export type Access = { access: "allow" } | { access: "confirm"; remember: string };

/**
 * Judgment of document links (external URLs) (`trustedUrls` in docs/user/configuration.md).
 *  - open: may be opened in the browser as is (matches `trustedUrls`, or is a remembered site)
 *  - confirm: ask the user. `origin` is the unit remembered by "always" (not for mailto)
 *  - deny: not opened (other than `http` / `https` / `mailto`, URLs containing a user name or password, etc.)
 */
export type UrlDecision =
  { action: "open" } | { action: "confirm"; origin?: string } | { action: "deny"; reason: string };

export interface HyperbufHost {
  /** The user's home directory (absolute path). Used to expand `~` and shorten display. */
  readonly home: string;
  /**
   * This frame's previous session (`SessionSnapshot`). null if none.
   * The contents are untrusted (the Web core validates them). The shell decides where it is stored.
   */
  loadSession?(): Promise<unknown>;
  /** Saves the session. The shell limits the size. */
  saveSession?(snapshot: unknown): Promise<void>;
  /** The user's settings. Defaults if absent. */
  getConfig?(): Promise<HostConfig>;
  /** The shell's identifier (for diagnostics). */
  readonly name: string;
  /** One level of a directory (hidden files are included only with `hidden`). Used for input completion. */
  listDirectory(dir: string, options?: { hidden?: boolean }): Promise<DirectoryListing>;
  /** Recursive listing of `.md` files under a directory (excluding hidden files and node_modules). The shell enforces the guard. */
  listTree(dir: string): Promise<TreeListing>;
  /**
   * The project root of `dir` (found by ascending to VCS markers; `dir` itself if none; docs/dev/buffer-model.md §6).
   * When absent (old shell, dev server), `dir` is treated as the root.
   */
  projectRoot?(dir: string): Promise<string>;
  /**
   * The Git branch name of the repository `dir` belongs to (a short hash for detached HEAD). null if there is no Git root.
   * No external command is used; the shell reads `HEAD` directly (docs/dev/buffer-model.md §6.9). When absent (old shell), nothing is shown.
   */
  vcsBranch?(dir: string): Promise<string | null>;
  /**
   * Reads Markdown (absolute path, `.md` only). Does not judge access
   * (paths the user typed or chose, already-judged external requests, restored sessions).
   */
  readFile(path: string): Promise<string>;
  /** Judgment of a file that a link or resource points to. A warn path needs confirmation. */
  checkAccess?(paths: string[]): Promise<Access[]>;
  /** Confirmation approved: remember the `remember` path (persisted). Only paths the shell proposed are remembered. */
  allow?(remember: string): Promise<boolean>;
  /** List of remembered paths, and revocation (`forget-remembered-path`). */
  listRemembered?(): Promise<string[]>;
  forget?(path: string): Promise<boolean>;
  /** Judgment of an external URL, and opening it in the default browser (the shell judges again when opening). */
  checkUrl?(url: string): Promise<UrlDecision>;
  openExternal?(url: string): Promise<boolean>;
  /** "always": remember that site (only the origin of a URL that was answered as needing confirmation). */
  rememberSite?(url: string): Promise<boolean>;
  /** List of remembered sites, and revocation (`forget-remembered-site`). */
  listRememberedSites?(): Promise<string[]>;
  forgetSite?(origin: string): Promise<boolean>;
  /** Frame (macOS window) operations (`C-x 5 …`). */
  frame?(action: "make" | "delete" | "other" | "delete-others"): Promise<void>;
  /**
   * The buffer shown in the selected window changed (absolute path; null for none or a virtual buffer such as search results).
   * The shell builds the frame title from it (setting `frameTitleFormat`). Not called again while the path stays the same.
   */
  activeBuffer?(path: string | null): void;
  /** List of files being displayed (absolute paths). The shell watches only these. */
  watch?(paths: string[]): void;
  /** Notifications of changes (`changed`) and deletions (`deleted`) of displayed files. */
  onFileChanged(callback: (path: string, state: "changed" | "deleted") => void): void;
  /** URLs of local images referenced by a document (absolute path -> loadable URL). The shell judges at load time. */
  resolveResource?(path: string): string;
  /** Full-text search under `dir`. The shell chooses the engine. Result paths are absolute. */
  search?(dir: string, query: string, options?: SearchOptions): Promise<SearchResult>;
  /** "Open" requests from outside (CLI / Emacs integration). */
  onOpen?(callback: (request: OpenRequest) => void): void;
  /** An "open" request was cancelled, e.g. by expiry (closes the minibuffer awaiting confirmation). */
  onOpenCancel?(callback: (id: string) => void): void;
  /**
   * Records the place pointed at in the viewer (the original position) for editor integration ("Edit in Emacs").
   * The shell keeps it with the file's identity information (hash, etc.), and the editor fetches it with `get-location`.
   * If configured, the shell invokes the editor with a fixed command the user configured.
   */
  markLocation?(location: SourceLocation): Promise<MarkResult>;
  /** The shell reports that an "edit in editor" action (context menu, etc.) was chosen. */
  onEdit?(callback: () => void): void;
  /** Registers a response to location queries (`get-view`: the current view). */
  onQuery?(callback: (op: string) => Promise<unknown>): void;
  /** Returns the result of an "open" request (including awaiting confirmation). */
  respond?(id: string, result: unknown): void;
  /**
   * The user approved (or rejected) a request to open a file under a warn path.
   * If approved, the path the shell proposed (`OpenRequest.remember`) is remembered.
   * The Web side cannot make it remember an arbitrary path (it can only approve the id of a request the shell proposed).
   * @returns whether the approval was accepted (if accepted, it can be read)
   */
  confirmOpen?(id: string, accepted: boolean): Promise<boolean>;
  /** Signal that the Web core is ready. Requests that arrived before this are delivered after it. */
  ready?(): void;
  /** Diagnostic log (for development). */
  log?(text: string): void;
}

export interface SearchOptions {
  limit?: number;
  engine?: string;
}

export interface SearchHit {
  path: string;
  line: number;
  text: string;
}

export interface SearchResult {
  results: SearchHit[];
  total: number;
  truncated: boolean;
  /** Reason it did not search (when the origin is `~` or `/`, etc.). */
  refused?: string;
  error?: string;
}

export interface OpenRequest {
  id?: string;
  /** Absolute path. */
  path: string;
  /** A file under a warn path; needs confirmation. */
  confirm?: boolean;
  /** Path to remember if the confirmation is approved (proposed by the shell). */
  remember?: string;
  line?: number;
  anchor?: string;
  error?: string;
}
