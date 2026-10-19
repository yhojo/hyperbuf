// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// An empty implementation bundled in place of elkjs (EPL-2.0). Only Mermaid's ELK layout (`layout: elk` / `flowchart-elk`)
// uses it. A diagram that uses ELK fails at the layout call and is shown as an error in place of the diagram (the whole document does not stop).
// Mermaid calls `new ELK()` when it evaluates the ELK chunk (this also happens for ordinary diagrams), so
// the constructor does not throw. Every method returns a rejected Promise when called.
// Reason: docs/history/license-options.md (avoids bundling EPL-2.0, keeps license options open; the roughly 1.5 MB chunk also goes away).
const unsupported = () =>
  Promise.reject(new Error("The ELK layout is not supported in HyperBuf (layout: elk)"));

export default class ELK {
  constructor() {
    return new Proxy(this, {
      // so that await and Promise.resolve do not mistake it for a thenable
      get: (_target, property) => (property === "then" ? undefined : unsupported),
    });
  }
}
