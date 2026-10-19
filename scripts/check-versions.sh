#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Yasuo Hojo
# バージョンの表記がそろっているか検査する(docs/dev/release.md)。
#   アプリの版(Version.swift)を正として、CLI、core と protocol の package.json が同じこと、
#   CHANGELOG.md に、その版の節(## [x.y.z])があることを確かめる。
set -euo pipefail
cd "$(dirname "$0")/.."

app="$(sed -n 's/^public let hyperBufVersion = "\(.*\)"$/\1/p' app/macos/Sources/HyperBufKit/Version.swift)"
cli="$(sed -n 's/^public let cliVersion = "\(.*\)"$/\1/p' cli/Sources/HyperBufCLI/CLI.swift)"
core="$(sed -n 's/^  "version": "\(.*\)",$/\1/p' core/package.json | head -1)"
protocol="$(sed -n 's/^  "version": "\(.*\)",$/\1/p' protocol/package.json | head -1)"

echo "app=$app cli=$cli core=$core protocol=$protocol"
bad=0
[ -n "$app" ] || { echo "アプリの版を読めません(app/macos/Sources/HyperBufKit/Version.swift)" >&2; exit 1; }
for pair in "cli:$cli" "core:$core" "protocol:$protocol"; do
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
