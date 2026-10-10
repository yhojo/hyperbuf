// Web コアを dist/ にバンドルする。設定は build-options.mjs。
import { copyFile, mkdir } from "node:fs/promises";
import * as esbuild from "esbuild";
import { buildOptions } from "./build-options.mjs";

await esbuild.build(buildOptions);
await mkdir("dist", { recursive: true });
await copyFile("public/index.html", "dist/index.html");
