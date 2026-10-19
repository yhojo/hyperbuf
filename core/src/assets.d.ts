// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Imported as a file URL (a string) by esbuild's file loader.
declare module "*.wasm" {
  const url: string;
  export default url;
}

// CSS is imported for its side effects (esbuild bundles it into main.css).
declare module "*.css";
