;;; hyperbuf.el --- Open Markdown in HyperBuf  -*- lexical-binding: t; -*-

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
  "アプリ内の確認(プロジェクト外のファイルなど)を待つ秒数。
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

(provide 'hyperbuf)

;;; hyperbuf.el ends here
