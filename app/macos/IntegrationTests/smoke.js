// 統合テスト(WebView の中で実行される)。HyperBuf.app(デバッグビルド)が、プロジェクトの全文書を開き、
// 描画・CSP・検索・画像の読み込みに問題がないかを集計して、JSON で返す。
// 実行: scripts/integration-test.sh [プロジェクトのディレクトリ]
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

const files = await host.listFiles();
out.files = files.length;
for (const file of files) {
  const t0 = performance.now();
  await app.open(file);
  // Mermaid の描画待ち(最大 20 秒)
  for (let i = 0; i < 200 && document.querySelector(".win.selected .content pre.mermaid-source"); i++) {
    await sleep(100);
  }
  const content = document.querySelector(".win.selected .content");
  const imgs = [...content.querySelectorAll("img")];
  // 画像の読み込み(と失敗の確定)を待ってから数える
  await Promise.all(imgs.map((img) => img.decode().catch(() => {})));
  out.docs[file] = {
    ms: Math.round(performance.now() - t0),
    chars: content.textContent.length,
    renderErrors: content.querySelectorAll(".render-error").length,
    blockedImages: content.querySelectorAll(".blocked-image").length,
    brokenImages: imgs.filter((i) => !(i.complete && i.naturalWidth > 0)).length,
    images: imgs.length,
    mermaid: content.querySelectorAll(".mermaid-diagram svg").length,
    // 実行・読み込みにつながる要素が、描画結果に残っていないこと(Mermaid の SVG 内の style を除く)
    dangerous:
      content.querySelectorAll("script,iframe,object,embed,form,meta,base").length +
      [...content.querySelectorAll("style")].filter((s) => !s.closest(".mermaid-diagram")).length,
    inlineHandlers: [...content.querySelectorAll("*")].filter((e) =>
      [...e.attributes].some((a) => /^on/i.test(a.name)),
    ).length,
  };
}

// 全文検索 → 仮想 buffer
if (files.length) {
  const word = (await host.readFile(files[0])).match(/[\p{L}\p{N}]{4,}/u)?.[0] ?? "a";
  await app.search(word);
  await sleep(200);
  const header = document.querySelector(".win.selected .win-header")?.textContent ?? "";
  out.search = { word, header, items: document.querySelectorAll(".win.selected .content li").length };
}

out.alerts = alerts;
out.violations = [...new Set(violations)];
out.errors = errors;
return JSON.stringify(out);
