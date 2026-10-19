// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Integration test (runs inside the WebView). HyperBuf.app (debug build) opens every document of the project and
// tallies problems in rendering, CSP, search and image loading, returning the result as JSON.
// Run: scripts/integration-test.sh [project directory]
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const alerts = [];
window.alert = (m) => alerts.push(String(m));
const violations = [];
document.addEventListener("securitypolicyviolation", (e) =>
  violations.push(`${e.violatedDirective} ${e.blockedURI}`),
);
const errors = [];
window.addEventListener("error", (e) => errors.push(String(e.message)));
window.addEventListener("unhandledrejection", (e) => errors.push("rejection: " + String(e.reason)));

const app = window.__hyperbuf;
const host = window.hyperbufHost;
const out = { host: host?.name, files: 0, docs: {}, search: null };

// PROJECT is prepended by scripts/integration-test.sh (an absolute path)
const files = (await host.listTree(PROJECT)).files;
out.files = files.length;
for (const file of files) {
  const t0 = performance.now();
  await app.open(`${PROJECT}/${file}`);
  // Wait for Mermaid rendering (up to 20 seconds)
  for (let i = 0; i < 200 && document.querySelector(".win.selected .content pre.mermaid-source"); i++) {
    await sleep(100);
  }
  const content = document.querySelector(".win.selected .content");
  const imgs = [...content.querySelectorAll("img")];
  // Wait for images to load (and for failures to be settled) before counting
  await Promise.all(imgs.map((img) => img.decode().catch(() => {})));
  out.docs[file] = {
    ms: Math.round(performance.now() - t0),
    chars: content.textContent.length,
    renderErrors: content.querySelectorAll(".render-error").length,
    blockedImages: content.querySelectorAll(".blocked-image").length,
    brokenImages: imgs.filter((i) => !(i.complete && i.naturalWidth > 0)).length,
    images: imgs.length,
    mermaid: content.querySelectorAll(".mermaid-diagram svg").length,
    // No elements that lead to execution or loading may remain in the rendered result (except style inside Mermaid SVG)
    dangerous:
      content.querySelectorAll("script,iframe,object,embed,form,meta,base").length +
      [...content.querySelectorAll("style")].filter((s) => !s.closest(".mermaid-diagram")).length,
    inlineHandlers: [...content.querySelectorAll("*")].filter((e) =>
      [...e.attributes].some((a) => /^on/i.test(a.name)),
    ).length,
  };
}

// Full-text search -> virtual buffer
if (files.length) {
  const first = `${PROJECT}/${files[0]}`;
  const word = (await host.readFile(first)).match(/[\p{L}\p{N}]{4,}/u)?.[0] ?? "a";
  await app.open(first); // Make this document the base directory (the search origin)
  await app.search(word);
  await sleep(200);
  const header = document.querySelector(".win.selected .mode-line")?.textContent ?? "";
  out.search = { word, header, items: document.querySelectorAll(".win.selected .content li").length };
}

out.alerts = alerts;
out.violations = [...new Set(violations)];
out.errors = errors;
return JSON.stringify(out);
