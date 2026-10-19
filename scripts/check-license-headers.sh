#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Yasuo Hojo
# Checks that source files have an SPDX license line (one line).
#   Under emacs/: GPL-3.0-or-later; everything else: Apache-2.0 (docs/history/license-options.md)
# Targets: .ts .mjs .js .swift .sh .css .el under git control (excluding fixtures/, docs/, legal/)
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
