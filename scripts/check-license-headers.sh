#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Yasuo Hojo
# ソースファイルに、SPDX のライセンス表記(1 行)があるか検査する。
#   emacs/ 以下: GPL-3.0-or-later、それ以外: Apache-2.0(docs/license-options.md)
# 対象: git の管理下の .ts .mjs .js .swift .sh .css .el(fixtures/・docs/・legal/ は除く)
set -euo pipefail
cd "$(dirname "$0")/.."

bad=0
while IFS= read -r file; do
  case "$file" in
    fixtures/*|docs/*|legal/*) continue ;;
    emacs/*) expected="GPL-3.0-or-later" ;;
    *) expected="Apache-2.0" ;;
  esac
  if ! head -20 "$file" | grep -q "SPDX-License-Identifier: $expected"; then
    echo "ライセンス表記がない、または違う($expected のはず): $file" >&2
    bad=$((bad + 1))
  fi
done < <(git ls-files '*.ts' '*.mjs' '*.js' '*.swift' '*.sh' '*.css' '*.el')

if [ "$bad" -ne 0 ]; then
  echo "NG: $bad 件" >&2
  exit 1
fi
echo "ライセンス表記の検査: OK"
