;;; hyperbuf-test.el --- Tests for hyperbuf.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Yasuo Hojo
;; SPDX-License-Identifier: GPL-3.0-or-later

(require 'ert)
(require 'cl-lib)
(require 'json)
(require 'hyperbuf)

(defconst hyperbuf-test--examples
  (expand-file-name "../../protocol/examples/"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "Shared conformance examples (protocol/examples/).")

(defun hyperbuf-test--example (name)
  "Read protocol/examples/NAME.json as a list of plists."
  (with-temp-buffer
    (insert-file-contents (expand-file-name (concat name ".json") hyperbuf-test--examples))
    (json-parse-buffer :object-type 'plist :array-type 'list :null-object nil)))

(defmacro hyperbuf-test--with-socket-dir (var &rest body)
  "Make a short temp directory, bind its socket path to VAR and run BODY."
  (declare (indent 1))
  `(let* ((dir (make-temp-file "hbe" t))
          (,var (expand-file-name "s.sock" dir))
          (hyperbuf-socket-path ,var)
          (hyperbuf-launch-if-needed nil))
     (unwind-protect (progn ,@body)
       (delete-directory dir t))))

(defun hyperbuf-test--server (path handler)
  "Start a test server listening on PATH.  HANDLER receives (PROC LINE)."
  (make-network-process
   :name "hyperbuf-test-server" :server t :family 'local :service path
   :noquery t :coding 'utf-8
   :filter (lambda (proc string) (funcall handler proc string))))

(defun hyperbuf-test--reply (proc plist)
  (process-send-string proc (concat (json-serialize plist) "\n")))

(defmacro hyperbuf-test--with-md-file (var &rest body)
  "Make a temporary .md file, bind its path to VAR and run BODY."
  (declare (indent 1))
  `(let* ((dir (make-temp-file "hbm" t))
          (,var (expand-file-name "note.md" dir)))
     (with-temp-file ,var (insert "# Heading\n\nBody\n"))
     (unwind-protect (progn ,@body)
       (delete-directory dir t))))

;;;; Shared examples

(ert-deftest hyperbuf-test-conformance-open-validation ()
  "protocol/examples/open-validation.json: validation matches the server."
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
  "protocol/examples/url.json: the URL that launches the app is the ping URL."
  (let ((checked 0))
    (dolist (item (hyperbuf-test--example "url"))
      (let ((request (plist-get item :request)))
        (when (and request (equal (plist-get request :op) "ping"))
          (cl-incf checked)
          (should (equal (plist-get item :url) hyperbuf--ping-url)))))
    (should (= checked 1))))

;;;; Building requests

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

;;;; Socket path

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

;;;; Round trips over the socket (test server)

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
                                                :message "Not opened because it is a warn path")))))))
        (unwind-protect
            (let ((err (should-error (hyperbuf-open file) :type 'user-error)))
              (should (string-match-p "warn path" (cadr err)))
              (should (string-match-p "outside-project" (cadr err))))
          (delete-process server))))))

(ert-deftest hyperbuf-test-socket-timeout ()
  (hyperbuf-test--with-socket-dir path
    (hyperbuf-test--with-md-file file
      (let ((server (hyperbuf-test--server path (lambda (_proc _line) nil)))  ; never replies
            (hyperbuf-timeout 0.1)
            (hyperbuf--reply-slack 0))
        (unwind-protect
            (let ((err (should-error (hyperbuf-open file) :type 'user-error)))
              (should (string-match-p "No response" (cadr err))))
          (delete-process server))))))

;;;; When the app is not running

(ert-deftest hyperbuf-test-not-running-without-launch ()
  (hyperbuf-test--with-socket-dir _path
    (hyperbuf-test--with-md-file file
      (let ((err (should-error (hyperbuf-open file) :type 'user-error)))
        (should (string-match-p "not running" (cadr err)))))))

(defmacro hyperbuf-test--with-launch (path received &rest body)
  "Run BODY where `open' \"launches\" the app by starting a test server on PATH.
The program and arguments of each `call-process' are collected in the
variable `calls'.  The open request that the server receives is stored in
RECEIVED.  The server replies with success."
  (declare (indent 2))
  `(let ((hyperbuf-launch-if-needed t)
         (hyperbuf-launch-timeout 2)
         (calls nil)
         (server nil))
     (unwind-protect
         (cl-letf (((symbol-function 'call-process)
                    (lambda (program &rest args)
                      (push (cons program (nthcdr 3 args)) calls)
                      (setq server
                            (hyperbuf-test--server
                             ,path
                             (lambda (proc line)
                               (setq ,received (json-parse-string (string-trim line)
                                                                  :object-type 'plist))
                               (hyperbuf-test--reply
                                proc (list :v 1 :id (plist-get ,received :id) :ok t
                                           :result (list :path "note.md"))))))
                      0)))
           ,@body)
       (when server (delete-process server)))))

(ert-deftest hyperbuf-test-launches-the-app-with-ping-and-sends-over-the-socket ()
  (hyperbuf-test--with-socket-dir path
    (hyperbuf-test--with-md-file file
      (let ((received nil))
        (hyperbuf-test--with-launch path received
          (let ((response (hyperbuf-open file 7)))
            ;; The app is launched with the ping URL only (no open request in the URL).
            (should (equal (car calls) '("open" "hyperbuf://ping")))
            (should (= (length calls) 1))
            ;; The request goes over the socket, and the result comes back.
            (should (equal (plist-get received :op) "open"))
            (should (= (plist-get received :line) 7))
            (should (equal (plist-get (plist-get response :result) :path) "note.md"))))))))

(ert-deftest hyperbuf-test-launch-reports-the-result-after-launching ()
  "A refusal by the launched app (e.g. a warn path) comes back to Emacs."
  (hyperbuf-test--with-socket-dir path
    (hyperbuf-test--with-md-file file
      (let ((hyperbuf-launch-if-needed t)
            (hyperbuf-launch-timeout 2)
            (server nil))
        (unwind-protect
            (cl-letf (((symbol-function 'call-process)
                       (lambda (&rest _)
                         (setq server
                               (hyperbuf-test--server
                                path
                                (lambda (proc _line)
                                  (hyperbuf-test--reply
                                   proc (list :v 1 :ok :false
                                              :error (list :code "outside-project"
                                                           :message "Not opened because it is a warn path"))))))
                         0)))
              (let ((err (should-error (hyperbuf-open file) :type 'user-error)))
                (should (string-match-p "warn path" (cadr err)))))
          (when server (delete-process server)))))))

(ert-deftest hyperbuf-test-launch-with-app-path-and-failure ()
  (hyperbuf-test--with-socket-dir path
    (hyperbuf-test--with-md-file file
      (let ((received nil)
            (hyperbuf-app "/Applications/HyperBuf.app"))
        (hyperbuf-test--with-launch path received
          (hyperbuf-open file)
          (should (equal (car calls) '("open" "-a" "/Applications/HyperBuf.app" "hyperbuf://ping")))))
      (let ((hyperbuf-launch-if-needed t))
        (cl-letf (((symbol-function 'call-process) (lambda (&rest _) 1)))
          (should-error (hyperbuf-open file) :type 'user-error))))))

(ert-deftest hyperbuf-test-launch-gives-up-when-the-socket-never-appears ()
  (hyperbuf-test--with-socket-dir _path
    (hyperbuf-test--with-md-file file
      (let ((hyperbuf-launch-if-needed t)
            (hyperbuf-launch-timeout 0.2))
        (cl-letf (((symbol-function 'call-process) (lambda (&rest _) 0)))
          (let ((err (should-error (hyperbuf-open file) :type 'user-error)))
            (should (string-match-p "Cannot connect to the launched" (cadr err)))))))))

;;;; Input validation (before connecting)

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

;;;; Via the CLI

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
                   (with-current-buffer out (insert "Not opened because it is a warn path"))
                   4)))
        (let ((err (should-error (hyperbuf-open file) :type 'user-error)))
          (should (string-match-p "warn path" (cadr err))))))))

;;;; Commands

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
          (insert "Appended\n")
          (should (buffer-modified-p))
          (hyperbuf-open-file)
          (should-not (buffer-modified-p))
          (should (string-match-p "Appended" (with-temp-buffer (insert-file-contents file) (buffer-string)))))
        (let ((hyperbuf-save-before-open nil))
          (insert "Unsaved\n")
          (hyperbuf-open-file)
          (should (buffer-modified-p))
          (set-buffer-modified-p nil))
        (kill-buffer)))))

(ert-deftest hyperbuf-test-open-file-requires-a-file-buffer ()
  (with-temp-buffer
    (should-error (hyperbuf-open-file) :type 'user-error)))

;;;; From the viewer to the edit location (hyperbuf-visit-location)

(defun hyperbuf-test--sha (text)
  "SHA-256 of TEXT as UTF-8 bytes."
  (secure-hash 'sha256 (encode-coding-string text 'utf-8)))

(ert-deftest hyperbuf-test-offset ()
  (let ((text "ab\n日本語\n\nlast"))
    (should (= (hyperbuf--offset text 1 1) 0))
    (should (= (hyperbuf--offset text 1 3) 2))          ; end of line (just before the newline)
    (should (= (hyperbuf--offset text 2 1) 3))
    (should (= (hyperbuf--offset text 2 4) 6))
    (should (= (hyperbuf--offset text 3 1) 7))          ; empty line
    (should (= (hyperbuf--offset text 4 5) (length text)))
    (should-not (hyperbuf--offset text 1 4))            ; beyond the line length
    (should-not (hyperbuf--offset text 5 1))            ; not enough lines
    (should-not (hyperbuf--offset text 1 0))))

(ert-deftest hyperbuf-test-conformance-location-check ()
  "protocol/examples/location-check.json: check results match the shared examples."
  (let ((cases (hyperbuf-test--example "location-check")))
    (should (>= (length cases) 8))
    (dolist (item cases)
      (let* ((name (plist-get item :name))
             (text (plist-get item :text))
             (disk-sha (hyperbuf-test--sha text))
             (location (plist-get item :location))
             (file (plist-get location :file))
             (location (plist-put (copy-sequence location) :file
                                  (plist-put (copy-sequence file) :sha256
                                             (if (equal (plist-get file :sha256) "auto")
                                                 disk-sha
                                               (plist-get file :sha256)))))
             (result (hyperbuf--check-location location text disk-sha)))
        (should (equal (list name (plist-get item :status))
                       (list name (symbol-name (plist-get result :status)))))))))

(defun hyperbuf-test--location (path text start-line start-col end-line end-col expect
                                     &optional precision before after)
  "Build a get-location location (a plist) for PATH with contents TEXT."
  (list :v 1 :path path
        :range (list :start (list :line start-line :column start-col)
                     :end (list :line end-line :column end-col))
        :precision (or precision "exact")
        :expect expect :expectTruncated :false
        :context (list :before (or before "") :after (or after ""))
        :file (list :sha256 (hyperbuf-test--sha text) :mtime 1 :size (string-bytes text))
        :viewer (list :selection expect :version 1 :readAt 1)
        :markedAt (* 1000 (float-time))))

(defmacro hyperbuf-test--with-viewer (location-form &rest body)
  "Run BODY connected to a test viewer that returns LOCATION-FORM for get-location."
  (declare (indent 1))
  `(hyperbuf-test--with-socket-dir path
     (let ((server (hyperbuf-test--server
                    path
                    (lambda (proc _line)
                      (hyperbuf-test--reply
                       proc (list :v 1 :ok t
                                  :result (list :location ,location-form)))))))
       (unwind-protect (progn ,@body)
         (delete-process server)))))

(ert-deftest hyperbuf-test-visit-moves-to-the-exact-position-and-highlights ()
  (hyperbuf-test--with-md-file file
    (let* ((text (with-temp-buffer (insert-file-contents file) (buffer-string)))
           ;; The 7 characters of "Heading" (from column 3 of line 1)
           (location (hyperbuf-test--location file text 1 3 1 10 "Heading"
                                              "exact" "# " "\n\nBody\n"))
           (pulsed nil)
           (messages nil))
      (hyperbuf-test--with-viewer location
        (cl-letf (((symbol-function 'pulse-momentary-highlight-region)
                   (lambda (start end &rest _) (setq pulsed (list start end))))
                  ((symbol-function 'message)
                   (lambda (format-string &rest args) (push (apply #'format format-string args) messages))))
          (save-window-excursion
            (hyperbuf-visit-location)
            (should (file-equal-p (buffer-file-name) file))
            (should (= (point) 3))
            (should (equal pulsed '(3 10)))
            (should (string-match-p "Heading" (car messages)))
            (kill-buffer)))))))

(ert-deftest hyperbuf-test-visit-says-so-when-the-position-is-only-block-precise ()
  (hyperbuf-test--with-md-file file
    (let* ((text (with-temp-buffer (insert-file-contents file) (buffer-string)))
           (location (hyperbuf-test--location file text 1 1 1 10 "# Heading" "block" "" "\n\nBody\n"))
           (messages nil))
      (hyperbuf-test--with-viewer location
        (cl-letf (((symbol-function 'pulse-momentary-highlight-region) #'ignore)
                  ((symbol-function 'message)
                   (lambda (format-string &rest args) (push (apply #'format format-string args) messages))))
          (save-window-excursion
            (hyperbuf-visit-location)
            (should (string-match-p "ambiguous" (car messages)))
            (kill-buffer)))))))

(ert-deftest hyperbuf-test-visit-refuses-a-stale-view ()
  "If the file changed after the viewer rendered it, warn and do not move (no way to continue)."
  (hyperbuf-test--with-md-file file
    (let* ((text (with-temp-buffer (insert-file-contents file) (buffer-string)))
           (location (hyperbuf-test--location file text 1 3 1 10 "Heading" "exact" "# " "\n\nBody\n")))
      ;; The file was rewritten after the location was marked
      (with-temp-file file (insert "# New heading\n\nOther body\n"))
      (hyperbuf-test--with-viewer location
        (let ((before (current-buffer))
              (err (should-error (hyperbuf-visit-location) :type 'user-error)))
          (should (eq (current-buffer) before))
          (should (string-match-p "not moving" (cadr err)))
          (should (string-match-p "rendered" (cadr err)))
          (with-current-buffer "*hyperbuf-mismatch*"
            (should (string-match-p "SHA-256" (buffer-string)))
            (should (string-match-p "reopen the file in the viewer" (buffer-string)))))))))

(ert-deftest hyperbuf-test-visit-refuses-when-the-text-at-the-position-differs ()
  (hyperbuf-test--with-md-file file
    (let* ((text (with-temp-buffer (insert-file-contents file) (buffer-string)))
           ;; The viewer pointed at "Body", but the location points at the heading line (mismatch)
           (location (hyperbuf-test--location file text 1 3 1 10 "Body" "exact" "# " "")))
      (hyperbuf-test--with-viewer location
        (let ((err (should-error (hyperbuf-visit-location) :type 'user-error)))
          (should (string-match-p "text at that location differs" (cadr err)))
          (with-current-buffer "*hyperbuf-mismatch*"
            (should (string-match-p "Body" (buffer-string)))
            (should (string-match-p "Heading" (buffer-string)))))))))

(ert-deftest hyperbuf-test-visit-checks-the-unsaved-buffer-not-just-the-disk ()
  "If unsaved edits shifted the text, do not move even if the disk is unchanged."
  (hyperbuf-test--with-md-file file
    (let* ((text (with-temp-buffer (insert-file-contents file) (buffer-string)))
           (location (hyperbuf-test--location file text 1 3 1 10 "Heading" "exact" "# " "\n\nBody\n")))
      (with-current-buffer (find-file-noselect file)
        (goto-char (point-min))
        (insert "Line added at the top\n")  ; not saved: the disk keeps the version the viewer read
        (hyperbuf-test--with-viewer location
          (let ((err (should-error (hyperbuf-visit-location) :type 'user-error)))
            (should (string-match-p "not moving" (cadr err)))))
        (set-buffer-modified-p nil)
        (kill-buffer)))))

(ert-deftest hyperbuf-test-visit-without-a-marked-location-or-viewer ()
  (hyperbuf-test--with-viewer nil
    (let ((err (should-error (hyperbuf-visit-location) :type 'user-error)))
      (should (string-match-p "No location marked" (cadr err)))))
  (hyperbuf-test--with-socket-dir _path
    (let ((err (should-error (hyperbuf-visit-location) :type 'user-error)))
      (should (string-match-p "not running" (cadr err))))))

(ert-deftest hyperbuf-test-visit-rejects-unsafe-paths-from-the-viewer ()
  "Even for a location returned by the socket peer, validate the path (absolute .md paths only)."
  (hyperbuf-test--with-viewer (hyperbuf-test--location "/etc/passwd" "x" 1 1 1 2 "x")
    (should-error (hyperbuf-visit-location) :type 'user-error))
  (hyperbuf-test--with-viewer (hyperbuf-test--location "relative.md" "x" 1 1 1 2 "x")
    (should-error (hyperbuf-visit-location) :type 'user-error)))

(ert-deftest hyperbuf-test-edit-here-raises-the-frame ()
  (let ((raised nil))
    (cl-letf (((symbol-function 'select-frame-set-input-focus) (lambda (_f) (setq raised t)))
              ((symbol-function 'hyperbuf-visit-location) #'ignore))
      (hyperbuf-edit-here)
      (should raised))))

;;; hyperbuf-test.el ends here
