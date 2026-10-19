#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Yasuo Hojo
# 全体のチェック(型検査・整形・ビルド・テスト)。CI(.github/workflows/ci.yml)と同じ内容。
# 使い方: scripts/check.sh [license|version|core|protocol|app|cli|emacs]   (引数なしですべて)
set -euo pipefail
cd "$(dirname "$0")/.."

step() { printf '\n==> %s\n' "$1"; }

check_license() {
  step "ライセンス表記: SPDX の表記(Apache-2.0 / emacs/ は GPL-3.0-or-later)"
  scripts/check-license-headers.sh
}

check_version() {
  step "バージョンの表記: アプリ・CLI・package.json・CHANGELOG"
  scripts/check-versions.sh
}

check_core() {
  step "core: 型検査・整形・テスト"
  (cd core && npm ci --silent && npm run check)
}

check_swift() { # $1=ディレクトリ
  step "$1: ビルド・テスト・整形"
  (cd "$1" && swift build && swift test && swift format lint --strict --recursive Sources Tests --configuration .swift-format)
}

check_protocol() {
  step "protocol: JSON Schema・例の検証"
  (cd protocol && npm ci --silent && npm run check)
  check_swift protocol/swift
}

check_emacs() {
  step "emacs: バイトコンパイル(警告をエラー扱い)・テスト"
  emacs -Q --batch -L emacs --eval '(setq byte-compile-error-on-warn t)' -f batch-byte-compile emacs/hyperbuf.el
  rm -f emacs/hyperbuf.elc
  emacs -Q --batch -L emacs -l ert -l emacs/test/hyperbuf-test.el -f ert-run-tests-batch-and-exit
}

case "${1:-all}" in
  core) check_core ;;
  app) check_swift app/macos ;;
  cli) check_swift cli ;;
  protocol) check_protocol ;;
  emacs) check_emacs ;;
  license) check_license ;;
  version) check_version ;;
  all) check_license; check_version; check_core; check_protocol; check_swift app/macos; check_swift cli; check_emacs ;;
  *) echo "usage: scripts/check.sh [license|version|core|protocol|app|cli|emacs]" >&2; exit 1 ;;
esac
printf '\nOK\n'
