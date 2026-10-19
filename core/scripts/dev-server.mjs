// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Dev server: serves dist/ and one directory (where the Markdown lives) over HTTP.
// Usage: node scripts/dev-server.mjs [directory] [port]
//   Default directory: ../fixtures/sample-project, default port: 8765
// Runs the Web core in a browser, standing in for the hyperbufHost that the production shell (macOS app)
// provides.
// Paths are absolute. The host (`~`) is treated as this directory.
// Listens on 127.0.0.1 only and serves nothing outside this directory except .md and images (production
// access checks are done by the shell).

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

/** Returns only real paths (absolute) contained in the directory (rejects escapes via .. or symlinks). */
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

/** One level of a directory (.md files and subdirectories). */
async function listDirectory(dir, showHidden) {
  const entries = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    if (!showHidden && hidden(entry.name)) continue;
    if (entry.isDirectory()) entries.push({ name: entry.name, dir: true });
    else if (entry.name.endsWith(".md")) entries.push({ name: entry.name, dir: false });
  }
  return entries;
}

/** Relative paths from the origin of the .md files under a directory (excluding hidden files/directories and node_modules). */
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

/** Case-insensitive substring full-text search (a naive implementation for development; up to 3 lines per file). */
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
      // For development: JSON of the HYPERBUF_CONFIG environment variable (returns keybindings only)
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
    // Static files (dist/)
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
