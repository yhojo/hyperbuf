#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Yasuo Hojo
# Overall checks (type check, formatting, build, tests). Same content as CI (.github/workflows/ci.yml).
# Usage: scripts/check.sh [license|version|core|protocol|app|cli|emacs]   (all if no argument)
set -euo pipefail
cd "$(dirname "$0")/.."

step() { printf '\n==> %s\n' "$1"; }

check_license() {
  step "License headers: SPDX identifiers (Apache-2.0; emacs/ is GPL-3.0-or-later)"
  scripts/check-license-headers.sh
}

check_version() {
  step "Version strings: app, CLI, package.json, CHANGELOG"
  scripts/check-versions.sh
}

check_core() {
  step "core: typecheck, format, tests"
  (cd core && npm ci --silent && npm run check)
}

check_swift() { # $1=directory
  step "$1: build, tests, format"
  (cd "$1" && swift build && swift test && swift format lint --strict --recursive Sources Tests --configuration .swift-format)
}

check_protocol() {
  step "protocol: JSON Schema and example validation"
  (cd protocol && npm ci --silent && npm run check)
  check_swift protocol/swift
}

check_emacs() {
  step "emacs: byte-compile (warnings as errors), tests"
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
