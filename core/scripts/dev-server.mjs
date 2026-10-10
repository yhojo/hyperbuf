// 開発用サーバー: dist/ と、1 つのディレクトリ(Markdown の置き場)を HTTP で配る。
// 使い方: node scripts/dev-server.mjs [ディレクトリ] [ポート]
//   既定のディレクトリ: ../fixtures/sample-project、既定のポート: 8765
// 本番のシェル(macOS アプリ)が提供する hyperbufHost の代わりに、ブラウザで Web コアを動かすためのもの。
// パスは絶対パス。ホスト(`~`)は、このディレクトリとして扱う。
// 127.0.0.1 だけで待ち受け、このディレクトリの外と、.md・画像以外は返さない(本番のアクセス判定は、シェルが行う)。

import { createServer } from "node:http";
import { watch } from "node:fs";
import { readdir, readFile, realpath, stat } from "node:fs/promises";
import { extname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const here = fileURLToPath(new URL(".", import.meta.url));
const dist = resolve(here, "../dist");
const projectArg = process.argv[2] ?? resolve(here, "../../fixtures/sample-project");
const port = Number(process.argv[3] ?? 8765);
const root = await realpath(resolve(projectArg));

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".wasm": "application/wasm",
  ".woff2": "font/woff2",
  ".woff": "font/woff",
  ".ttf": "font/ttf",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".webp": "image/webp",
  ".md": "text/markdown; charset=utf-8",
};
const IMAGE_EXT = new Set([".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg"]);

/** ディレクトリ内に収まる実パス(絶対パス)だけを返す(.. やシンボリックリンクによる脱出を拒否)。 */
async function contained(path) {
  try {
    if (!path.startsWith("/")) return null;
    const file = await realpath(resolve(path));
    return file === root || file.startsWith(root + sep) ? file : null;
  } catch {
    return null;
  }
}

const hidden = (name) => name.startsWith(".") || name === "node_modules";

/** ディレクトリの 1 階層(.md とサブディレクトリ)。 */
async function listDirectory(dir, showHidden) {
  const entries = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    if (!showHidden && hidden(entry.name)) continue;
    if (entry.isDirectory()) entries.push({ name: entry.name, dir: true });
    else if (entry.name.endsWith(".md")) entries.push({ name: entry.name, dir: false });
  }
  return entries;
}

/** ディレクトリ以下の .md の、起点からの相対パス(隠しファイル・隠しディレクトリ・node_modules を除く)。 */
async function listTree(base, dir = base) {
  const out = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    if (hidden(entry.name)) continue;
    const full = join(dir, entry.name);
    if (entry.isDirectory()) out.push(...(await listTree(base, full)));
    else if (entry.name.endsWith(".md")) out.push(relative(base, full).split(sep).join("/"));
  }
  return out.sort();
}

/** 大文字小文字を区別しない部分一致の全文検索(開発用の素朴な実装。1 ファイル最大 3 行)。 */
async function search(dir, query, limit) {
  const q = query.toLowerCase();
  const results = [];
  let total = 0;
  for (const path of await listTree(dir)) {
    const lines = (await readFile(join(dir, path), "utf8")).split("\n");
    let found = 0;
    for (let i = 0; i < lines.length && found < 3; i++) {
      if (lines[i].toLowerCase().includes(q)) {
        found += 1;
        total += 1;
        if (results.length < limit)
          results.push({ path: join(dir, path), line: i + 1, text: lines[i].slice(0, 200) });
      }
    }
  }
  return { results, total, truncated: total > results.length };
}

const clients = new Set();
watch(root, { recursive: true }, async (_event, name) => {
  if (name && name.endsWith(".md")) {
    const path = join(root, name);
    const state = (await stat(path).catch(() => null)) ? "changed" : "deleted";
    for (const res of clients) res.write(`data: ${JSON.stringify({ path, state })}\n\n`);
  }
});

const send = (res, status, body, type = "text/plain; charset=utf-8") => {
  res.writeHead(status, { "Content-Type": type, "Cache-Control": "no-store" });
  res.end(body);
};

createServer(async (req, res) => {
  try {
    const url = new URL(req.url ?? "/", "http://localhost");
    const { pathname } = url;
    if (pathname === "/__project/info") {
      return send(res, 200, JSON.stringify({ home: root }), MIME[".json"]);
    }
    if (pathname === "/__project/config") {
      // 開発用: 環境変数 HYPERBUF_CONFIG の JSON(keybindings だけを返す)
      const file = process.env.HYPERBUF_CONFIG;
      const config = file ? JSON.parse(await readFile(file, "utf8").catch(() => "{}")) : {};
      return send(
        res,
        200,
        JSON.stringify({ keybindings: config.keybindings ?? {} }),
        MIME[".json"],
      );
    }
    if (pathname === "/__project/dir") {
      const dir = await contained(url.searchParams.get("path") ?? "");
      if (!dir)
        return send(
          res,
          200,
          JSON.stringify({ entries: [], truncated: false, error: "not found" }),
          MIME[".json"],
        );
      const entries = await listDirectory(dir, url.searchParams.get("hidden") === "1");
      return send(res, 200, JSON.stringify({ entries, truncated: false }), MIME[".json"]);
    }
    if (pathname === "/__project/tree") {
      const dir = await contained(url.searchParams.get("path") ?? "");
      if (!dir)
        return send(
          res,
          200,
          JSON.stringify({ files: [], truncated: false, error: "not found" }),
          MIME[".json"],
        );
      return send(
        res,
        200,
        JSON.stringify({ files: await listTree(dir), truncated: false }),
        MIME[".json"],
      );
    }
    if (pathname === "/__project/file") {
      const path = url.searchParams.get("path") ?? "";
      const file = path.endsWith(".md") ? await contained(path) : null;
      if (!file) return send(res, 404, "not found");
      return send(res, 200, await readFile(file, "utf8"), MIME[".md"]);
    }
    if (pathname.startsWith("/__project/raw/")) {
      const path = "/" + decodeURIComponent(pathname.slice("/__project/raw/".length));
      const ext = extname(path).toLowerCase();
      const file = IMAGE_EXT.has(ext) ? await contained(path) : null;
      if (!file) return send(res, 404, "not found");
      res.setHeader("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'");
      return send(res, 200, await readFile(file), MIME[ext]);
    }
    if (pathname === "/__project/search") {
      const dir = await contained(url.searchParams.get("dir") ?? "");
      const q = url.searchParams.get("q") ?? "";
      const limit = Number(url.searchParams.get("limit") ?? 200);
      if (!dir)
        return send(
          res,
          200,
          JSON.stringify({ results: [], total: 0, truncated: false, error: "not found" }),
          MIME[".json"],
        );
      return send(res, 200, JSON.stringify(await search(dir, q, limit)), MIME[".json"]);
    }
    if (pathname === "/__project/events") {
      res.writeHead(200, { "Content-Type": "text/event-stream", "Cache-Control": "no-store" });
      res.write(": connected\n\n");
      clients.add(res);
      req.on("close", () => clients.delete(res));
      return;
    }
    // 静的ファイル(dist/)
    const rel = pathname === "/" ? "index.html" : pathname.slice(1);
    const file = resolve(dist, rel);
    if (!file.startsWith(dist + sep)) return send(res, 404, "not found");
    const info = await stat(file).catch(() => null);
    if (!info?.isFile()) return send(res, 404, "not found");
    return send(res, 200, await readFile(file), MIME[extname(file)] ?? "application/octet-stream");
  } catch (err) {
    return send(res, 500, String(err));
  }
}).listen(port, "127.0.0.1", () => {
  console.log(`HyperBuf dev server: http://127.0.0.1:${port}/  (root: ${root})`);
});
