#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Yasuo Hojo
# Checks that the version strings are consistent (docs/dev/release.md).
#   Taking the app version (Version.swift) as authoritative, verifies that the CLI, the Web core (index.ts),
# the header of
#   the Emacs package, and package.json and package-lock.json of core and protocol are the same,
#   and that CHANGELOG.md has a section for that version (## [x.y.z]).
set -euo pipefail
cd "$(dirname "$0")/.."

app="$(sed -n 's/^public let hyperBufVersion = "\(.*\)"$/\1/p' app/macos/Sources/HyperBufKit/Version.swift)"
cli="$(sed -n 's/^public let cliVersion = "\(.*\)"$/\1/p' cli/Sources/HyperBufCLI/CLI.swift)"
core="$(sed -n 's/^  "version": "\(.*\)",$/\1/p' core/package.json | head -1)"
protocol="$(sed -n 's/^  "version": "\(.*\)",$/\1/p' protocol/package.json | head -1)"
coreindex="$(sed -n 's/^export const version = "\(.*\)";$/\1/p' core/src/index.ts)"
emacs="$(sed -n 's/^;; Version: \(.*\)$/\1/p' emacs/hyperbuf.el | head -1)"
corelock="$(sed -n 's/^  "version": "\(.*\)",$/\1/p' core/package-lock.json | head -1)"
protocollock="$(sed -n 's/^  "version": "\(.*\)",$/\1/p' protocol/package-lock.json | head -1)"

echo "app=$app cli=$cli core=$core protocol=$protocol core-index=$coreindex emacs=$emacs core-lock=$corelock protocol-lock=$protocollock"
bad=0
[ -n "$app" ] || { echo "アプリの版を読めません(app/macos/Sources/HyperBufKit/Version.swift)" >&2; exit 1; }
for pair in "cli:$cli" "core:$core" "protocol:$protocol" "core/src/index.ts:$coreindex" "emacs:$emacs" "core/package-lock.json:$corelock" "protocol/package-lock.json:$protocollock"; do
  if [ "${pair#*:}" != "$app" ]; then
    echo "版がそろっていません: ${pair%%:*} は ${pair#*:}、アプリは $app" >&2
    bad=$((bad + 1))
  fi
done
if ! grep -q "^## \[$app\]" CHANGELOG.md; then
  echo "CHANGELOG.md に、版 $app の節(## [$app])がありません" >&2
  bad=$((bad + 1))
fi
if [ "$bad" -ne 0 ]; then
  echo "NG: バージョンの表記が $bad 件、そろっていません。更新する場所は docs/dev/release.md を参照してください" >&2
  exit 1
fi
echo "OK: バージョンは $app でそろっています"
