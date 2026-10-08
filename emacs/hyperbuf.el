;;; hyperbuf.el --- Open Markdown in HyperBuf  -*- lexical-binding: t; -*-

;; Version: 0.0.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: tools, docs

;;; Commentary:

;; HyperBuf (macOS Markdown viewer) との連携。M5 で、ソケット経由で文書を開く
;; コマンド(`hyperbuf-open-file' など)を実装する。
;; 仕様: docs/integration-protocol.md

;;; Code:

(defconst hyperbuf-version "0.0.0"
  "HyperBuf 連携パッケージのバージョン。")

(defgroup hyperbuf nil
  "HyperBuf との連携。"
  :group 'tools
  :prefix "hyperbuf-")

(defcustom hyperbuf-transport 'socket
  "HyperBuf への要求の送り方。
`socket' は直接ソケットに接続する(標準)。`cli' は hyperbuf コマンドを呼ぶ。"
  :type '(choice (const :tag "ソケットに直接接続" socket)
                 (const :tag "hyperbuf CLI 経由" cli))
  :group 'hyperbuf)

(provide 'hyperbuf)

;;; hyperbuf.el ends here
