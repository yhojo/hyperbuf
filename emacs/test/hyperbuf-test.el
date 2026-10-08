;;; hyperbuf-test.el --- Tests for hyperbuf.el  -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'json)
(require 'hyperbuf)

(defconst hyperbuf-test--examples
  (expand-file-name "../../protocol/examples/"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "共有の適合テスト用の例(protocol/examples/)。")

(defun hyperbuf-test--example (name)
  "protocol/examples/NAME.json を、plist のリストとして読む。"
  (with-temp-buffer
    (insert-file-contents (expand-file-name (concat name ".json") hyperbuf-test--examples))
    (json-parse-buffer :object-type 'plist :array-type 'list :null-object nil)))

(defmacro hyperbuf-test--with-socket-dir (var &rest body)
  "短い一時ディレクトリを作り、そのソケットのパスを VAR に束ねて BODY を実行する。"
  (declare (indent 1))
  `(let* ((dir (make-temp-file "hbe" t))
          (,var (expand-file-name "s.sock" dir))
          (hyperbuf-socket-path ,var)
          (hyperbuf-launch-if-needed nil))
     (unwind-protect (progn ,@body)
       (delete-directory dir t))))

(defun hyperbuf-test--server (path handler)
  "PATH で待ち受ける、テスト用のサーバー。HANDLER は (PROC LINE) を受け取る。"
  (make-network-process
   :name "hyperbuf-test-server" :server t :family 'local :service path
   :noquery t :coding 'utf-8
   :filter (lambda (proc string) (funcall handler proc string))))

(defun hyperbuf-test--reply (proc plist)
  (process-send-string proc (concat (json-serialize plist) "\n")))

(defmacro hyperbuf-test--with-md-file (var &rest body)
  "一時の .md ファイルを作り、そのパスを VAR に束ねて BODY を実行する。"
  (declare (indent 1))
  `(let* ((dir (make-temp-file "hbm" t))
          (,var (expand-file-name "note.md" dir)))
     (with-temp-file ,var (insert "# 見出し\n\n本文\n"))
     (unwind-protect (progn ,@body)
       (delete-directory dir t))))

;;;; 共有の例

(ert-deftest hyperbuf-test-conformance-open-validation ()
  "protocol/examples/open-validation.json: 検証の結果が、サーバーと同じ。"
  (let ((cases (hyperbuf-test--example "open-validation")))
    (should (> (length cases) 10))
    (dolist (item cases)
      (let* ((name (plist-get item :name))
             (request (plist-get item :request))
             (expect (plist-get item :expect))
             (problem (hyperbuf--validate-open
                       (plist-get request :path) (plist-get request :line)
                       (plist-get request :anchor) (plist-get request :v))))
        (if (equal expect "ok")
            (should-not (and problem (list name problem)))
          (should (equal (list name expect) (list name (car problem)))))))))

(ert-deftest hyperbuf-test-conformance-url ()
  "protocol/examples/url.json: 同じ要求から、同じ URL を作る。"
  (let ((checked 0))
    (dolist (item (hyperbuf-test--example "url"))
      (let ((request (plist-get item :request)))
        (when (and request (equal (plist-get request :op) "open"))
          (cl-incf checked)
          (should (equal (list (plist-get item :name) (plist-get item :url))
                         (list (plist-get item :name)
                               (hyperbuf--open-url
                                (list :path (plist-get request :path)
                                      :line (plist-get request :line)
                                      :anchor (plist-get request :anchor)))))))))
    (should (>= checked 4))))

;;;; 要求の組み立て

(ert-deftest hyperbuf-test-build-request ()
  (let ((r (hyperbuf--build-request "/a/b.md" 12 nil nil nil)))
    (should (equal (plist-get r :op) "open"))
    (should (equal (plist-get r :path) "/a/b.md"))
    (should (= (plist-get r :line) 12))
    (should (= (plist-get r :v) 1))
    (should (= (plist-get r :timeoutMs) (round (* 1000 hyperbuf-timeout))))
    (should-not (plist-member r :anchor))
    (should-not (plist-member r :target)))
  (should (= (plist-get (hyperbuf--build-request "/a.md" nil nil nil t) :timeoutMs)
             (round (* 1000 hyperbuf-wait-timeout))))
  (should (equal (plist-get (hyperbuf--build-request "/a.md" nil nil "split-right" nil) :target)
                 "split-right"))
  (let ((hyperbuf-default-target "new-frame"))
    (should (equal (plist-get (hyperbuf--build-request "/a.md" nil nil nil nil) :target)
                   "new-frame"))))

(ert-deftest hyperbuf-test-default-transport ()
  (should (eq hyperbuf-transport 'socket))
  (should (string-match-p "\\`[0-9]+\\.[0-9]+\\.[0-9]+\\'" hyperbuf-version)))

;;;; ソケットのパス

(ert-deftest hyperbuf-test-socket-path ()
  (let ((hyperbuf-socket-path nil))
    (let ((process-environment (cons "HYPERBUF_SOCKET_PATH=/tmp/x.sock" process-environment)))
      (should (equal (hyperbuf--socket-path) "/tmp/x.sock")))
    (let ((process-environment (cons "HYPERBUF_SOCKET_PATH" process-environment)))
      (should (string-suffix-p "Library/Application Support/HyperBuf/hyperbuf.sock"
                               (hyperbuf--socket-path)))))
  (let ((hyperbuf-socket-path "/custom.sock"))
    (should (equal (hyperbuf--socket-path) "/custom.sock"))))

(ert-deftest hyperbuf-test-socket-path-falls-back-when-too-long ()
  (let ((hyperbuf-socket-path nil)
        (process-environment (cons "HYPERBUF_SOCKET_PATH" process-environment)))
    (cl-letf (((symbol-function 'expand-file-name)
               (lambda (name &optional _dir)
                 (if (string-prefix-p "~/Library" name)
                     (concat "/Volumes/" (make-string 100 ?x) "/hyperbuf.sock")
                   name))))
      (let ((path (hyperbuf--socket-path)))
        (should (<= (string-bytes path) 103))
        (should (string-match-p "hyperbuf-[0-9]+\\.sock\\'" path))))))

;;;; ソケットでの往復(テスト用のサーバー)

(ert-deftest hyperbuf-test-socket-round-trip ()
  (hyperbuf-test--with-socket-dir path
    (hyperbuf-test--with-md-file file
      (let* ((received nil)
             (server (hyperbuf-test--server
                      path
                      (lambda (proc line)
                        (setq received (json-parse-string (string-trim line) :object-type 'plist))
                        (hyperbuf-test--reply
                         proc (list :v 1 :id (plist-get received :id) :ok t
                                    :result (list :path "note.md")))))))
        (unwind-protect
            (let ((response (hyperbuf-open file 3)))
              (should (eq (plist-get response :ok) t))
              (should (equal (plist-get (plist-get response :result) :path) "note.md"))
              (should (equal (plist-get received :op) "open"))
              (should (equal (plist-get received :path) (expand-file-name file)))
              (should (= (plist-get received :line) 3))
              (should (= (plist-get received :v) 1)))
          (delete-process server))))))

(ert-deftest hyperbuf-test-socket-japanese-path-round-trip ()
  (hyperbuf-test--with-socket-dir path
    (let* ((dir (make-temp-file "hbj" t))
           (file (expand-file-name "ハイパー バッファ.md" dir))
           (received nil)
           (server (hyperbuf-test--server
                    path
                    (lambda (proc line)
                      (setq received (json-parse-string (string-trim line) :object-type 'plist))
                      (hyperbuf-test--reply proc (list :v 1 :ok t :result nil))))))
      (with-temp-file file (insert "x"))
      (unwind-protect
          (progn (hyperbuf-open file 1 "参照履歴")
                 (should (equal (plist-get received :path) (expand-file-name file)))
                 (should (equal (plist-get received :anchor) "参照履歴")))
        (delete-process server)
        (delete-directory dir t)))))

(ert-deftest hyperbuf-test-socket-error-response ()
  (hyperbuf-test--with-socket-dir path
    (hyperbuf-test--with-md-file file
      (let ((server (hyperbuf-test--server
                     path
                     (lambda (proc _line)
                       (hyperbuf-test--reply
                        proc (list :v 1 :ok :false
                                   :error (list :code "outside-project"
                                                :message "範囲外のため開きませんでした")))))))
        (unwind-protect
            (let ((err (should-error (hyperbuf-open file) :type 'user-error)))
              (should (string-match-p "範囲外" (cadr err)))
              (should (string-match-p "outside-project" (cadr err))))
          (delete-process server))))))

(ert-deftest hyperbuf-test-socket-timeout ()
  (hyperbuf-test--with-socket-dir path
    (hyperbuf-test--with-md-file file
      (let ((server (hyperbuf-test--server path (lambda (_proc _line) nil)))  ; 応答しない
            (hyperbuf-timeout 0.1)
            (hyperbuf--reply-slack 0))
        (unwind-protect
            (let ((err (should-error (hyperbuf-open file) :type 'user-error)))
              (should (string-match-p "応答がありません" (cadr err))))
          (delete-process server))))))

;;;; アプリが起動していないとき

(ert-deftest hyperbuf-test-not-running-without-launch ()
  (hyperbuf-test--with-socket-dir _path
    (hyperbuf-test--with-md-file file
      (let ((err (should-error (hyperbuf-open file) :type 'user-error)))
        (should (string-match-p "起動していません" (cadr err)))))))

(ert-deftest hyperbuf-test-launches-the-app-with-the-open-url ()
  (hyperbuf-test--with-socket-dir _path
    (hyperbuf-test--with-md-file file
      (let ((hyperbuf-launch-if-needed t)
            (calls nil))
        (cl-letf (((symbol-function 'call-process)
                   (lambda (program &rest args)
                     (push (cons program (nthcdr 3 args)) calls)
                     0)))
          (should-not (hyperbuf-open file 7))
          (let ((call (car calls)))
            (should (equal (car call) "open"))
            (should (string-prefix-p "hyperbuf://open?v=1&path=" (car (last call))))
            (should (string-suffix-p "&line=7" (car (last call))))))))))

(ert-deftest hyperbuf-test-launch-with-app-path-and-failure ()
  (hyperbuf-test--with-socket-dir _path
    (hyperbuf-test--with-md-file file
      (let ((hyperbuf-launch-if-needed t)
            (hyperbuf-app "/Applications/HyperBuf.app")
            (calls nil))
        (cl-letf (((symbol-function 'call-process)
                   (lambda (program &rest args) (push (cons program (nthcdr 3 args)) calls) 0)))
          (hyperbuf-open file)
          (should (equal (butlast (cdr (car calls))) '("-a" "/Applications/HyperBuf.app"))))
        (cl-letf (((symbol-function 'call-process) (lambda (&rest _) 1)))
          (should-error (hyperbuf-open file) :type 'user-error))))))

;;;; 入力の検証(接続の前)

(ert-deftest hyperbuf-test-rejects-bad-files-before-connecting ()
  (hyperbuf-test--with-socket-dir _path
    (let ((dir (make-temp-file "hbv" t)))
      (unwind-protect
          (progn
            (with-temp-file (expand-file-name "a.txt" dir) (insert "x"))
            (should-error (hyperbuf-open (expand-file-name "missing.md" dir)) :type 'user-error)
            (should-error (hyperbuf-open (expand-file-name "a.txt" dir)) :type 'user-error)
            (should-error (hyperbuf-open dir) :type 'user-error)
            (should-error (hyperbuf-open "/ssh:example.invalid:/tmp/a.md") :type 'user-error)
            (hyperbuf-test--with-md-file file
              (should-error (hyperbuf-open file 0) :type 'user-error)
              (should-error (hyperbuf-open file nil (make-string 201 ?a)) :type 'user-error)))
        (delete-directory dir t)))))

;;;; CLI 経由

(ert-deftest hyperbuf-test-cli-transport ()
  (hyperbuf-test--with-md-file file
    (let ((hyperbuf-transport 'cli)
          (calls nil))
      (cl-letf (((symbol-function 'call-process)
                 (lambda (program _in _out _display &rest args)
                   (push (cons program args) calls)
                   0)))
        (hyperbuf-open file 5 nil "split-right" t))
      (let ((call (car calls)))
        (should (equal (car call) "hyperbuf"))
        (should (equal (cdr call)
                       (list "--line" "5" "--target" "split-right" "--wait" "--"
                             (expand-file-name file)))))
      (cl-letf (((symbol-function 'call-process)
                 (lambda (_program _in out &rest _)
                   (with-current-buffer out (insert "範囲外のため開きませんでした"))
                   4)))
        (let ((err (should-error (hyperbuf-open file) :type 'user-error)))
          (should (string-match-p "範囲外" (cadr err))))))))

;;;; コマンド

(ert-deftest hyperbuf-test-open-file-uses-the-current-line ()
  (hyperbuf-test--with-md-file file
    (let ((hyperbuf-save-before-open nil)
          (captured nil))
      (cl-letf (((symbol-function 'hyperbuf-open)
                 (lambda (&rest args) (setq captured args))))
        (with-current-buffer (find-file-noselect file)
          (goto-char (point-min))
          (forward-line 2)
          (hyperbuf-open-file)
          (should (equal captured (list file 3 nil nil nil)))
          (hyperbuf-open-other-window t)
          (should (equal captured (list file 3 nil "split-right" t)))
          (kill-buffer))))))

(ert-deftest hyperbuf-test-open-file-saves-modified-buffers-when-asked ()
  (hyperbuf-test--with-md-file file
    (cl-letf (((symbol-function 'hyperbuf-open) (lambda (&rest _) nil)))
      (with-current-buffer (find-file-noselect file)
        (let ((hyperbuf-save-before-open t))
          (goto-char (point-max))
          (insert "追記\n")
          (should (buffer-modified-p))
          (hyperbuf-open-file)
          (should-not (buffer-modified-p))
          (should (string-match-p "追記" (with-temp-buffer (insert-file-contents file) (buffer-string)))))
        (let ((hyperbuf-save-before-open nil))
          (insert "未保存\n")
          (hyperbuf-open-file)
          (should (buffer-modified-p))
          (set-buffer-modified-p nil))
        (kill-buffer)))))

(ert-deftest hyperbuf-test-open-file-requires-a-file-buffer ()
  (with-temp-buffer
    (should-error (hyperbuf-open-file) :type 'user-error)))

;;; hyperbuf-test.el ends here
