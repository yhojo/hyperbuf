// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Bundles the Web core into dist/. Settings are in build-options.mjs.
import { copyFile, mkdir } from "node:fs/promises";
import * as esbuild from "esbuild";
import { buildOptions } from "./build-options.mjs";

await esbuild.build(buildOptions);
await mkdir("dist", { recursive: true });
await copyFile("public/index.html", "dist/index.html");
