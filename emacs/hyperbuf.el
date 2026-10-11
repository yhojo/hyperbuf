;;; hyperbuf.el --- Open Markdown in HyperBuf  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Yasuo Hojo

;; Author: Yasuo Hojo
;; SPDX-License-Identifier: GPL-3.0-or-later

;; This file is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;; Version: 0.0.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: tools, docs

;;; Commentary:

;; HyperBuf (macOS 向けの Markdown ビューア) に、ファイル・行を指定して文書を開かせる。
;;
;; 標準では、アプリの Unix ドメインソケットに直接接続する(`hyperbuf-transport' が `socket')。
;; `cli' にすると、`hyperbuf' コマンドを呼ぶ。アプリが起動していなければ、開く要求の
;; `hyperbuf://' URL で起動する(`hyperbuf-launch-if-needed')。
;;
;; 主なコマンド:
;;   `hyperbuf-open-file'         現在のバッファのファイルを、現在行つきで開く
;;   `hyperbuf-open-other-window' 同、ビューアの別の window(分割)に開く
;;   `hyperbuf-open-project-file' プロジェクトの Markdown を選んで開く
;;
;; 仕様: docs/integration-protocol.md  共有の例: protocol/examples/

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'project)
(require 'pulse)
(require 'subr-x)
(require 'url-util)

(defconst hyperbuf-version "0.0.0"
  "HyperBuf 連携パッケージのバージョン。")

(defconst hyperbuf--protocol-version 1
  "対応する連携プロトコルのバージョン。")

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

(defcustom hyperbuf-executable "hyperbuf"
  "`hyperbuf-transport' が `cli' のときに呼ぶコマンド。"
  :type 'string
  :group 'hyperbuf)

(defcustom hyperbuf-socket-path nil
  "ソケットのパス。
nil なら、環境変数 HYPERBUF_SOCKET_PATH、なければ標準の場所。"
  :type '(choice (const :tag "標準" nil) file)
  :group 'hyperbuf)

(defcustom hyperbuf-launch-if-needed t
  "アプリが起動していないとき、開く要求の URL で、アプリを起動するか。
nil なら、「アプリが起動していません」と通知して終わる。"
  :type 'boolean
  :group 'hyperbuf)

(defcustom hyperbuf-app nil
  "起動する HyperBuf.app のパス(開発用)。
nil なら、URL スキームに登録されたアプリを起動する。"
  :type '(choice (const :tag "登録されたアプリ" nil) directory)
  :group 'hyperbuf)

(defcustom hyperbuf-default-target nil
  "表示先の既定。
nil なら選択中の window。それ以外は、次のいずれか。"
  :type '(choice (const :tag "選択中の window" nil)
                 (const "split-right") (const "split-below") (const "new-frame"))
  :group 'hyperbuf)

(defcustom hyperbuf-timeout 3
  "アプリ内の確認(警告パスのファイルなど)を待つ秒数。
プレフィックス引数つきなら `hyperbuf-wait-timeout'。"
  :type 'number
  :group 'hyperbuf)

(defcustom hyperbuf-wait-timeout 60
  "長く待つときの秒数。"
  :type 'number
  :group 'hyperbuf)

(defcustom hyperbuf-save-before-open 'ask
  "未保存の変更があるバッファを開くとき、先に保存するか。
ビューアは、ディスク上のファイルを読む。
`ask' は確認し、t は確認なしで保存し、nil は保存しない。"
  :type '(choice (const :tag "確認する" ask) (const :tag "保存する" t) (const :tag "保存しない" nil))
  :group 'hyperbuf)

(defcustom hyperbuf-location-max-age 600
  "ビューアで指した位置が、これ(秒)より古いとき、移動の際に、その旨を知らせる。"
  :type 'number
  :group 'hyperbuf)

(define-error 'hyperbuf-not-running "HyperBuf が起動していません")

(defvar hyperbuf--reply-slack 2
  "アプリが期限(timeoutMs)で返す `timeout' 応答を、待つための余白(秒)。")

;;;; 入力の検証(protocol/examples/open-validation.json と同じ規則)

(defun hyperbuf--validate-open (path &optional line anchor version)
  "`open' 要求の入力を検証する。
正しければ nil、誤りなら (CODE . MESSAGE) を返す。
サーバーと同じ規則(docs/integration-protocol.md §6)。"
  (cond
   ((and version (/= version hyperbuf--protocol-version))
    (cons "unsupported-version" (format "未対応のバージョンです(v=%s)" version)))
   ((not (and (stringp path)
              (string-prefix-p "/" path)
              (not (string-match-p "[\0-\37\177]" path))
              (not (member ".." (split-string path "/")))))
    (cons "bad-request" "path が不正です(絶対パスのみ)"))
   ((not (string-suffix-p ".md" path))
    (cons "not-markdown" ".md のみ開けます"))
   ((and line (< line 1))
    (cons "bad-request" "line が不正です"))
   ;; 長さは、コードポイントの数(Emacs の文字数と同じ)
   ((and anchor (> (length anchor) 200))
    (cons "bad-request" "anchor が長すぎます"))))

;;;; ソケット

(defun hyperbuf--socket-path ()
  "ソケットのパス。
`sun_path' の上限(103 バイト)を超えるときは、一時ディレクトリの代替。"
  (or hyperbuf-socket-path
      (getenv "HYPERBUF_SOCKET_PATH")
      (let ((primary (expand-file-name "~/Library/Application Support/HyperBuf/hyperbuf.sock")))
        (if (<= (string-bytes primary) 103)
            primary
          (expand-file-name (format "hyperbuf-%d.sock" (user-uid))
                            (or (getenv "TMPDIR") temporary-file-directory))))))

(defun hyperbuf--socket-request (request timeout)
  "REQUEST(plist)をソケットで送り、応答(plist)を返す。
TIMEOUT 秒で応答がなければ、`user-error' にする。
接続できなければ、`hyperbuf-not-running' を通知する。"
  (let* ((buffer "")
         (done nil)
         (proc (condition-case nil
                   (make-network-process
                    :name "hyperbuf" :family 'local :service (hyperbuf--socket-path)
                    :noquery t :coding 'utf-8
                    :filter (lambda (_proc chunk)
                              (setq buffer (concat buffer chunk))
                              (when (string-search "\n" buffer) (setq done t))))
                 (file-error (signal 'hyperbuf-not-running nil)))))
    (unwind-protect
        (progn
          (process-send-string proc (concat (json-serialize request) "\n"))
          (let ((deadline (+ (float-time) timeout)))
            (while (and (not done) (< (float-time) deadline) (process-live-p proc))
              (accept-process-output proc 0.05)))
          (unless done
            (user-error "HyperBuf の応答がありません(アプリ内で確認を待っているかもしれません。C-u で長く待てます)"))
          (json-parse-string (car (split-string buffer "\n")) :object-type 'plist :null-object nil
                             :false-object :false))
      (when (process-live-p proc) (delete-process proc)))))

;;;; 起動(URL スキーム)

(defun hyperbuf--open-url (request)
  "REQUEST(plist)から、`hyperbuf://open' の URL を作る。
REQUEST のキーは、:path :line :anchor :project :target。"
  (let ((params `(("v" . ,(number-to-string hyperbuf--protocol-version))
                  ("path" . ,(plist-get request :path))
                  ("line" . ,(and (plist-get request :line) (number-to-string (plist-get request :line))))
                  ("anchor" . ,(plist-get request :anchor))
                  ("project" . ,(plist-get request :project))
                  ("target" . ,(plist-get request :target)))))
    (concat "hyperbuf://open?"
            (mapconcat (lambda (kv) (concat (car kv) "=" (url-hexify-string (cdr kv))))
                       (cl-remove-if-not #'cdr params) "&"))))

(defun hyperbuf--launch (request)
  "アプリを、REQUEST を開く URL で起動する。
起動と最初の要求の引き渡しが、1 回で済む。"
  (let ((args (append (and hyperbuf-app (list "-a" (expand-file-name hyperbuf-app)))
                      (list (hyperbuf--open-url request)))))
    (unless (zerop (apply #'call-process "open" nil nil nil args))
      (user-error "HyperBuf を起動できません"))))

;;;; 要求

(defun hyperbuf--build-request (path line anchor target wait)
  "`open' 要求(plist)を作る。"
  (let ((timeout (if wait hyperbuf-wait-timeout hyperbuf-timeout)))
    (append (list :v hyperbuf--protocol-version
                  :id (format "emacs-%d" (emacs-pid))
                  :op "open"
                  :path path)
            (and line (list :line line))
            (and anchor (list :anchor anchor))
            (and (or target hyperbuf-default-target)
                 (list :target (or target hyperbuf-default-target)))
            (list :timeoutMs (round (* 1000 timeout))))))

(defun hyperbuf--report-error (error)
  "アプリが返した ERROR(plist: :code :message)を、利用者に知らせる。"
  (user-error "HyperBuf: %s (%s)" (plist-get error :message) (plist-get error :code)))

(defun hyperbuf--open-via-socket (request)
  (condition-case nil
      (let ((response (hyperbuf--socket-request
                       request (+ hyperbuf--reply-slack
                                  (/ (plist-get request :timeoutMs) 1000.0)))))
        (when-let* ((error (plist-get response :error))) (hyperbuf--report-error error))
        response)
    (hyperbuf-not-running
     (cond
      ((not hyperbuf-launch-if-needed)
       (user-error "HyperBuf が起動していません"))
      (t (hyperbuf--launch request)
         (message "HyperBuf を起動して、開く要求を渡しました(結果は、アプリの画面に表示されます)")
         nil)))))

(defun hyperbuf--open-via-cli (request)
  (let* ((args (append (and (plist-get request :line) (list "--line" (number-to-string (plist-get request :line))))
                       (and (plist-get request :anchor) (list "--anchor" (plist-get request :anchor)))
                       (and (plist-get request :target) (list "--target" (plist-get request :target)))
                       (and (> (plist-get request :timeoutMs) 5000) (list "--wait"))
                       (list "--" (plist-get request :path))))
         (output (generate-new-buffer " *hyperbuf-cli*"))
         (status (unwind-protect
                     (apply #'call-process hyperbuf-executable nil output nil args)
                   nil)))
    (unwind-protect
        (unless (eql status 0)
          (user-error "hyperbuf: %s"
                      (string-trim (with-current-buffer output (buffer-string)))))
      (kill-buffer output))))

;;;###autoload
(defun hyperbuf-open (file &optional line anchor target wait)
  "FILE(Markdown)を HyperBuf で開く。
LINE(1 始まり)か ANCHOR(見出しなど)で、位置を指定する。
TARGET は表示先(\"split-right\" など)。
WAIT が非 nil なら、アプリ内の確認を長く待つ。"
  (when (file-remote-p file)
    (user-error "リモートのファイルは、HyperBuf では開けません: %s" file))
  (let ((path (expand-file-name file)))
    (unless (file-regular-p path) (user-error "ファイルがありません: %s" path))
    (when-let* ((problem (hyperbuf--validate-open path line anchor)))
      (user-error "HyperBuf: %s" (cdr problem)))
    (let ((request (hyperbuf--build-request path line anchor target wait)))
      (pcase hyperbuf-transport
        ('socket (hyperbuf--open-via-socket request))
        ('cli (hyperbuf--open-via-cli request))
        (other (user-error "不明な hyperbuf-transport: %S" other))))))

(defun hyperbuf--maybe-save ()
  "`hyperbuf-save-before-open' に従って、現在のバッファを保存する。"
  (when (and buffer-file-name (buffer-modified-p))
    (pcase hyperbuf-save-before-open
      ('t (save-buffer))
      ('ask (if (y-or-n-p "ビューアはディスク上のファイルを読みます。先に保存しますか? ")
                (save-buffer)
              (message "未保存の変更は、ビューアに反映されません")))
      (_ (message "未保存の変更は、ビューアに反映されません")))))

;;;###autoload
(defun hyperbuf-open-file (&optional wait)
  "現在のバッファのファイルを、現在行つきで HyperBuf に開く。
WAIT(プレフィックス引数)つきなら、アプリ内の確認を長く待つ。"
  (interactive "P")
  (unless buffer-file-name (user-error "このバッファは、ファイルではありません"))
  (hyperbuf--maybe-save)
  (hyperbuf-open buffer-file-name (line-number-at-pos nil t) nil nil wait))

;;;###autoload
(defun hyperbuf-open-other-window (&optional wait)
  "現在のバッファのファイルを、HyperBuf の別の window(右に分割)に開く。"
  (interactive "P")
  (unless buffer-file-name (user-error "このバッファは、ファイルではありません"))
  (hyperbuf--maybe-save)
  (hyperbuf-open buffer-file-name (line-number-at-pos nil t) nil "split-right" wait))

;;;###autoload
(defun hyperbuf-open-project-file (&optional wait)
  "現在のプロジェクトの Markdown を選んで、HyperBuf に開く。"
  (interactive "P")
  (let* ((project (or (project-current) (user-error "プロジェクトの中ではありません")))
         (root (project-root project))
         (files (cl-remove-if-not (lambda (f) (string-suffix-p ".md" f))
                                  (mapcar (lambda (f) (file-relative-name f root))
                                          (project-files project))))
         (choice (completing-read "Markdown: " files nil t)))
    (hyperbuf-open (expand-file-name choice root) nil nil nil wait)))

;;;; ビューアから、編集位置へ(「Emacs で編集」)
;;
;; ビューアで指した場所を、元の Markdown の位置にして、エディタに渡す。誤った場所を、黙って編集させないために、
;;  - 位置は、ビューアが構文木から求めたもの(文言の検索ではない)
;;  - 移動の前に、必ず照合する: (1) ファイルが、ビューアが描画した版と同じか (2) その位置にあるはずの文字列と
;;    前後の文脈が、バッファと一致するか
;;  - 照合に失敗したら、移動も、続行もしない。警告と、食い違いの詳細(`*hyperbuf-mismatch*')だけを出す
;;  - 移動したら、範囲を一時的に強調し、ビューアが指していた文字列を表示する
;; 仕様: docs/integration-protocol.md §10。共有の例: protocol/examples/location-check.json

(defun hyperbuf--file-sha256 (path)
  "PATH のファイルの内容(バイト列)の SHA-256。ビューアが読んだ版との比較に使う。"
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally path)
    (secure-hash 'sha256 (current-buffer))))

(defun hyperbuf--offset (text line column)
  "TEXT の LINE 行 COLUMN 桁の、0 始まりの文字位置。範囲外なら nil。
LINE と COLUMN は 1 始まり。桁は、文字(コードポイント)で数える。"
  (let ((pos 0) (current 1))
    (while (and pos (< current line))
      (let ((newline (string-search "\n" text pos)))
        (setq pos (and newline (1+ newline))
              current (1+ current))))
    (when (and pos (>= column 1))
      (let ((line-end (or (string-search "\n" text pos) (length text)))
            (offset (+ pos (1- column))))
        (and (<= offset line-end) offset)))))

(defun hyperbuf--check-location (location text disk-sha)
  "LOCATION(`get-location' の位置)を、バッファの内容と照合する。
TEXT はバッファの全文、DISK-SHA はディスク上のファイルの SHA-256。
結果は plist。成功なら (:status ok :start S :end E :actual …)。
失敗なら (:status stale|mismatch :reason …)。S・E は 0 始まりの文字位置。"
  (let* ((range (plist-get location :range))
         (start (plist-get range :start))
         (end (plist-get range :end))
         (file (plist-get location :file))
         (expect (plist-get location :expect))
         (context (plist-get location :context)))
    (cond
     ((not (equal (plist-get location :v) hyperbuf--protocol-version))
      (list :status 'mismatch :reason "未対応のバージョンの位置です"))
     ((not (equal (plist-get file :sha256) disk-sha))
      (list :status 'stale
            :reason "ファイルが、ビューアが描画した版と違います(ビューアで見ている内容と、編集する内容が食い違います)"))
     (t
      (let ((s (hyperbuf--offset text (plist-get start :line) (plist-get start :column)))
            (e (hyperbuf--offset text (plist-get end :line) (plist-get end :column))))
        (if (not (and s e (<= s e)))
            (list :status 'mismatch :reason "位置が、文書の範囲外です")
          (let ((actual (substring text s e)))
            (cond
             ((not (if (eq (plist-get location :expectTruncated) t)
                       (string-prefix-p expect actual)
                     (equal expect actual)))
              (list :status 'mismatch
                    :reason "その位置の文字列が、ビューアが指していたものと違います" :actual actual))
             ((not (string-suffix-p (plist-get context :before) (substring text 0 s)))
              (list :status 'mismatch :reason "位置の直前の文脈が、ビューアが指していたものと違います" :actual actual))
             ((not (string-prefix-p (plist-get context :after) (substring text e)))
              (list :status 'mismatch :reason "位置の直後の文脈が、ビューアが指していたものと違います" :actual actual))
             (t (list :status 'ok :start s :end e :actual actual))))))))))

(defun hyperbuf--abbreviate (string &optional limit)
  "STRING を、改行を空白にして、LIMIT(既定 60)文字までに縮める。"
  (let ((flat (replace-regexp-in-string "[\n\r]+" " " string))
        (limit (or limit 60)))
    (if (> (length flat) limit) (concat (substring flat 0 limit) "…") flat)))

(defun hyperbuf--report-problem (location result path)
  "照合に失敗した LOCATION の詳細を出して、`user-error' にする(移動しない)。
詳細は `*hyperbuf-mismatch*' バッファに出す。PATH は、編集するファイル。"
  (let ((buffer (get-buffer-create "*hyperbuf-mismatch*"))
        (file (plist-get location :file)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "HyperBuf: 編集位置の照合に失敗したので、移動しませんでした。\n\n理由: %s\n"
                        (plist-get result :reason))
                (format "ファイル: %s\n" path)
                (format "ビューアが指していた文字列: %s\n"
                        (hyperbuf--abbreviate (or (plist-get (plist-get location :viewer) :selection) "") 200))
                (format "位置: %d 行 %d 桁 〜 %d 行 %d 桁(%s)\n\n"
                        (plist-get (plist-get (plist-get location :range) :start) :line)
                        (plist-get (plist-get (plist-get location :range) :start) :column)
                        (plist-get (plist-get (plist-get location :range) :end) :line)
                        (plist-get (plist-get (plist-get location :range) :end) :column)
                        (plist-get location :precision)))
        (if (eq (plist-get result :status) 'stale)
            (insert (format "ビューアが描画した版: SHA-256 %s(%s バイト)\nいまのファイル: SHA-256 %s(%s バイト)\n\n"
                            (plist-get file :sha256) (plist-get file :size)
                            (hyperbuf--file-sha256 path)
                            (file-attribute-size (file-attributes path)))
                    "対処: ビューアで、ファイルを開き直して(または、外部更新の反映を待って)、もう一度、指してください。\n")
          (insert (format "ビューアが指していた文字列:\n  %s\nいま、その位置にある文字列:\n  %s\n\n"
                          (hyperbuf--abbreviate (or (plist-get location :expect) "") 200)
                          (hyperbuf--abbreviate (or (plist-get result :actual) "(なし)") 200))
                  "対処: 位置の近くを、目で確かめてください。別の場所を編集しないように、自動では移動しません。\n"))
        (special-mode)))
    (display-buffer buffer)
    (user-error "HyperBuf: %s(移動しません。詳細は *hyperbuf-mismatch*)" (plist-get result :reason))))

(defun hyperbuf--visit (location)
  "LOCATION を照合して、問題がなければ、その位置へ移動して強調する。
問題があれば、移動せず、`user-error'。"
  (let ((path (plist-get location :path)))
    (when-let* ((problem (hyperbuf--validate-open path)))
      (user-error "HyperBuf: 位置のファイルが不正です: %s" (cdr problem)))
    (unless (file-regular-p path) (user-error "ファイルがありません: %s" path))
    (let* ((buffer (find-file-noselect path))
           (disk-sha (hyperbuf--file-sha256 path))
           (text (with-current-buffer buffer
                   (save-restriction (widen) (buffer-substring-no-properties (point-min) (point-max)))))
           (result (hyperbuf--check-location location text disk-sha)))
      (unless (eq (plist-get result :status) 'ok)
        (hyperbuf--report-problem location result path))
      (switch-to-buffer buffer)
      (widen)
      (let ((start (+ (point-min) (plist-get result :start)))
            (end (+ (point-min) (plist-get result :end)))
            (age (- (float-time) (/ (or (plist-get location :markedAt) 0) 1000.0))))
        (goto-char start)
        (pulse-momentary-highlight-region start end)
        (message "HyperBuf: 「%s」%s%s"
                 (hyperbuf--abbreviate (plist-get result :actual))
                 (if (equal (plist-get location :precision) "block")
                     "(位置が曖昧なため、ブロック全体を示しています)" "")
                 (if (> age hyperbuf-location-max-age)
                     (format "(%d 分前に指した位置です)" (round (/ age 60))) ""))))))

;;;###autoload
(defun hyperbuf-visit-location ()
  "ビューアで「Emacs で編集」と指した位置へ、移動する。
移動の前に、ファイルの版・その位置の文字列・前後の文脈を、
ビューアが指していたものと照合する。
照合に失敗したら、移動せず、警告と詳細(*hyperbuf-mismatch*)を出す。"
  (interactive)
  (let* ((response (condition-case nil
                       (hyperbuf--socket-request
                        (list :v hyperbuf--protocol-version :id (format "emacs-%d" (emacs-pid)) :op "get-location")
                        hyperbuf-timeout)
                     (hyperbuf-not-running (user-error "HyperBuf が起動していません"))))
         (location (plist-get (plist-get response :result) :location)))
    (when-let* ((error (plist-get response :error))) (hyperbuf--report-error error))
    (unless location
      (user-error "ビューアで指した位置がありません(ビューアの右クリックメニュー「Emacs で編集」で指してください)"))
    (hyperbuf--visit location)))

;;;###autoload
(defun hyperbuf-edit-here ()
  "`hyperbuf-visit-location' に加えて、Emacs のフレームを前面に出す。
ビューアの「Emacs で編集」が、emacsclient から呼び出すのに使う。
例: emacsclient -n -e \"(hyperbuf-edit-here)\""
  (interactive)
  (select-frame-set-input-focus (selected-frame))
  (hyperbuf-visit-location))

(provide 'hyperbuf)

;;; hyperbuf.el ends here
