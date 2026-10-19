// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// List of syntax-highlighting grammars (starry-night; the same TextMate grammars as GitHub).
// The supported languages, code block info strings and extensions are listed in docs/user/syntax-highlighting.md
// (generated from here by `npm run languages`).
//
//  - EAGER: always included. starry-night's `common` (34 languages) plus a few small grammars
//  - LAZY: large grammars (Emacs Lisp is about 800 KB) are loaded as a separate chunk only when the document has a code block
//    in that language (keeps startup and everyday rendering light). Used by `prepare()` in `pipeline.ts`

import { common } from "@wooorm/starry-night";
import type { Grammar } from "@wooorm/starry-night";

import clojure from "@wooorm/starry-night/source.clojure";
import scheme from "@wooorm/starry-night/source.scheme";
import racket from "@wooorm/starry-night/source.racket";
import commonLisp from "@wooorm/starry-night/source.commonlisp";
import haskell from "@wooorm/starry-night/source.haskell";
import ocaml from "@wooorm/starry-night/source.ocaml";
import fsharp from "@wooorm/starry-night/source.fsharp";
import erlang from "@wooorm/starry-night/source.erlang";
import elixir from "@wooorm/starry-night/source.elixir";
import elm from "@wooorm/starry-night/source.elm";
import purescript from "@wooorm/starry-night/source.purescript";
import scala from "@wooorm/starry-night/source.scala";
import zig from "@wooorm/starry-night/source.zig";
import nim from "@wooorm/starry-night/source.nim";
import crystal from "@wooorm/starry-night/source.crystal";
import dart from "@wooorm/starry-night/source.dart";
import groovy from "@wooorm/starry-night/source.groovy";
import julia from "@wooorm/starry-night/source.julia";
import powershell from "@wooorm/starry-night/source.powershell";
import awk from "@wooorm/starry-night/source.awk";
import viml from "@wooorm/starry-night/source.viml";
import fortran from "@wooorm/starry-night/source.fortran";
import assembly from "@wooorm/starry-night/source.assembly";
import llvm from "@wooorm/starry-night/source.llvm";
import tcl from "@wooorm/starry-night/source.tcl";
import matlab from "@wooorm/starry-night/source.matlab";
import toml from "@wooorm/starry-night/source.toml";
import dockerfile from "@wooorm/starry-night/source.dockerfile";
import nginx from "@wooorm/starry-night/source.nginx";
import hcl from "@wooorm/starry-night/source.hcl";
import cmake from "@wooorm/starry-night/source.cmake";
import just from "@wooorm/starry-night/source.just";
import proto from "@wooorm/starry-night/source.proto";
import nix from "@wooorm/starry-night/source.nix";
import rego from "@wooorm/starry-night/source.rego";
import jsonComments from "@wooorm/starry-night/source.json.comments";
import gitignore from "@wooorm/starry-night/source.gitignore";
import apacheConf from "@wooorm/starry-night/source.apacheconf";
import vue from "@wooorm/starry-night/source.vue";
import svelte from "@wooorm/starry-night/source.svelte";
import sass from "@wooorm/starry-night/source.sass";
import stylus from "@wooorm/starry-night/source.stylus";
import handlebars from "@wooorm/starry-night/text.html.handlebars";
import jade from "@wooorm/starry-night/text.jade";
import astro from "@wooorm/starry-night/source.astro";
import latex from "@wooorm/starry-night/text.tex.latex";
import bibtex from "@wooorm/starry-night/text.bibtex";
import restructuredText from "@wooorm/starry-night/text.restructuredtext";
import asciidoc from "@wooorm/starry-night/text.html.asciidoc";
import dot from "@wooorm/starry-night/source.dot";
import wsd from "@wooorm/starry-night/source.wsd";
import csv from "@wooorm/starry-night/source.csv";
import regexp from "@wooorm/starry-night/source.regexp";

export const EAGER: Grammar[] = [
  ...common,
  clojure,
  scheme,
  racket,
  commonLisp,
  haskell,
  ocaml,
  fsharp,
  erlang,
  elixir,
  elm,
  purescript,
  scala,
  zig,
  nim,
  crystal,
  dart,
  groovy,
  julia,
  powershell,
  awk,
  viml,
  fortran,
  assembly,
  llvm,
  tcl,
  matlab,
  toml,
  dockerfile,
  nginx,
  hcl,
  cmake,
  just,
  proto,
  nix,
  rego,
  jsonComments,
  gitignore,
  apacheConf,
  vue,
  svelte,
  sass,
  stylus,
  handlebars,
  jade,
  astro,
  latex,
  bibtex,
  restructuredText,
  asciidoc,
  dot,
  wsd,
  csv,
  regexp,
];

export interface LazyGrammar {
  scope: string;
  /** Code block info strings (language names, extensions). Lowercase, no leading `.`. Used to decide from the document body whether it is needed. */
  flags: string[];
  load(): Promise<Grammar>;
}

export const LAZY: LazyGrammar[] = [
  {
    scope: "source.emacs.lisp",
    flags: ["emacs-lisp", "elisp", "emacs", "cask", "eask", "el"],
    load: async () => (await import("@wooorm/starry-night/source.emacs.lisp")).default,
  },
  {
    scope: "source.tsx",
    flags: ["tsx"],
    load: async () => (await import("@wooorm/starry-night/source.tsx")).default,
  },
];

/** Collects the languages given to code blocks (```lang / ~~~lang) in Markdown text (lowercase, no leading `.`). */
export function fenceFlags(markdown: string): Set<string> {
  const flags = new Set<string>();
  for (const m of markdown.matchAll(/^[ \t]{0,3}(?:`{3,}|~{3,})[ \t]*([^\s`{]+)/gm)) {
    flags.add((m[1] as string).replace(/^\./, "").toLowerCase());
  }
  return flags;
}
