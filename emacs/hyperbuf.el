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

;; Version: 0.1.1
;; Package-Requires: ((emacs "29.1"))
;; Keywords: tools, docs

;;; Commentary:

;; Ask HyperBuf (a Markdown viewer for macOS) to open a document at a
;; given file and line.
;;
;; By default this connects directly to the app's Unix domain socket
;; (`hyperbuf-transport' is `socket').  Set it to `cli' to call the
;; `hyperbuf' command instead.  If the app is not running, it is
;; launched with a `hyperbuf://' URL that carries the open request
;; (see `hyperbuf-launch-if-needed').
;;
;; Main commands:
;;   `hyperbuf-open-file'         Open the current buffer's file at point's line
;;   `hyperbuf-open-other-window' Same, in another viewer window (split)
;;   `hyperbuf-open-project-file' Pick a Markdown file of the project to open
;;
;; Specification: docs/integration-protocol.md
;; Shared examples: protocol/examples/

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'project)
(require 'pulse)
(require 'subr-x)
(require 'url-util)

(defconst hyperbuf-version "0.0.0"
  "Version of the HyperBuf integration package.")

(defconst hyperbuf--protocol-version 1
  "Version of the integration protocol that this package speaks.")

(defgroup hyperbuf nil
  "Integration with HyperBuf."
  :group 'tools
  :prefix "hyperbuf-")

(defcustom hyperbuf-transport 'socket
  "How to send requests to HyperBuf.
`socket' connects to the socket directly (the default).  `cli' calls
the hyperbuf command."
  :type '(choice (const :tag "Connect to the socket directly" socket)
                 (const :tag "Via the hyperbuf CLI" cli))
  :group 'hyperbuf)

(defcustom hyperbuf-executable "hyperbuf"
  "Command to call when `hyperbuf-transport' is `cli'."
  :type 'string
  :group 'hyperbuf)

(defcustom hyperbuf-socket-path nil
  "Path of the socket.
If nil, use the environment variable HYPERBUF_SOCKET_PATH, or else
the default location."
  :type '(choice (const :tag "Default" nil) file)
  :group 'hyperbuf)

(defcustom hyperbuf-launch-if-needed t
  "Whether to launch the app with the open request URL if it is not running.
If nil, just report that HyperBuf is not running."
  :type 'boolean
  :group 'hyperbuf)

(defcustom hyperbuf-app nil
  "Path of the HyperBuf.app to launch (for development).
If nil, launch the app registered for the URL scheme."
  :type '(choice (const :tag "Registered app" nil) directory)
  :group 'hyperbuf)

(defcustom hyperbuf-default-target nil
  "Default place to show the document.
If nil, use the selected window.  Otherwise one of the choices below."
  :type '(choice (const :tag "Selected window" nil)
                 (const "split-right") (const "split-below") (const "new-frame"))
  :group 'hyperbuf)

(defcustom hyperbuf-timeout 3
  "Seconds to wait for confirmation in the app (e.g. for warn-path files).
With a prefix argument, `hyperbuf-wait-timeout' is used instead."
  :type 'number
  :group 'hyperbuf)

(defcustom hyperbuf-wait-timeout 60
  "Seconds to wait when waiting for a long time."
  :type 'number
  :group 'hyperbuf)

(defcustom hyperbuf-save-before-open 'ask
  "Whether to save a modified buffer before opening it in the viewer.
The viewer reads the file on disk.  `ask' asks first, t saves without
asking, and nil does not save."
  :type '(choice (const :tag "Ask" ask) (const :tag "Save" t) (const :tag "Do not save" nil))
  :group 'hyperbuf)

(defcustom hyperbuf-location-max-age 600
  "Age in seconds after which a location marked in the viewer is called stale.
When visiting an older location, say so in the echo area."
  :type 'number
  :group 'hyperbuf)

(define-error 'hyperbuf-not-running "HyperBuf is not running")

(defvar hyperbuf--reply-slack 2
  "Extra seconds to wait for the app's `timeout' reply (at timeoutMs).")

;;;; Input validation (same rules as protocol/examples/open-validation.json)

(defun hyperbuf--validate-open (path &optional line anchor version)
  "Validate the input of an `open' request.
Return nil if valid, otherwise (CODE . MESSAGE).
The rules are the same as the server's (docs/integration-protocol.md
section 6)."
  (cond
   ((and version (/= version hyperbuf--protocol-version))
    (cons "unsupported-version" (format "Unsupported version (v=%s)" version)))
   ((not (and (stringp path)
              (string-prefix-p "/" path)
              (not (string-match-p "[\0-\37\177]" path))
              (not (member ".." (split-string path "/")))))
    (cons "bad-request" "Invalid path (absolute paths only)"))
   ((not (string-suffix-p ".md" path))
    (cons "not-markdown" "Only .md files can be opened"))
   ((and line (< line 1))
    (cons "bad-request" "Invalid line"))
   ;; The length is counted in code points (same as Emacs characters).
   ((and anchor (> (length anchor) 200))
    (cons "bad-request" "anchor is too long"))))

;;;; Socket

(defun hyperbuf--socket-path ()
  "Return the path of the socket.
If the default exceeds the `sun_path' limit (103 bytes), fall back to a
path in the temporary directory."
  (or hyperbuf-socket-path
      (getenv "HYPERBUF_SOCKET_PATH")
      (let ((primary (expand-file-name "~/Library/Application Support/HyperBuf/hyperbuf.sock")))
        (if (<= (string-bytes primary) 103)
            primary
          (expand-file-name (format "hyperbuf-%d.sock" (user-uid))
                            (or (getenv "TMPDIR") temporary-file-directory))))))

(defun hyperbuf--socket-request (request timeout)
  "Send REQUEST (a plist) over the socket and return the reply (a plist).
Signal a `user-error' if there is no reply within TIMEOUT seconds.
Signal `hyperbuf-not-running' if the connection fails."
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
            (user-error "No response from HyperBuf (it may be waiting for confirmation in the app; use C-u to wait longer)"))
          (json-parse-string (car (split-string buffer "\n")) :object-type 'plist :null-object nil
                             :false-object :false))
      (when (process-live-p proc) (delete-process proc)))))

;;;; Launching (URL scheme)

(defun hyperbuf--open-url (request)
  "Build a `hyperbuf://open' URL from REQUEST (a plist).
The keys of REQUEST are :path :line :anchor :project :target."
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
  "Launch the app with a URL that opens REQUEST.
This launches the app and hands over the first request in one step."
  (let ((args (append (and hyperbuf-app (list "-a" (expand-file-name hyperbuf-app)))
                      (list (hyperbuf--open-url request)))))
    (unless (zerop (apply #'call-process "open" nil nil nil args))
      (user-error "Cannot launch HyperBuf"))))

;;;; Requests

(defun hyperbuf--build-request (path line anchor target wait)
  "Build an `open' request (a plist)."
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
  "Report ERROR (a plist with :code and :message) from the app to the user."
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
       (user-error "HyperBuf is not running"))
      (t (hyperbuf--launch request)
         (message "Launched HyperBuf and handed over the open request (the result appears in the app)")
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
  "Open FILE (a Markdown file) in HyperBuf.
Specify the position with LINE (1-based) or ANCHOR (e.g. a heading).
TARGET is where to show it (e.g. \"split-right\").
If WAIT is non-nil, wait longer for confirmation in the app."
  (when (file-remote-p file)
    (user-error "Remote files cannot be opened in HyperBuf: %s" file))
  (let ((path (expand-file-name file)))
    (unless (file-regular-p path) (user-error "No such file: %s" path))
    (when-let* ((problem (hyperbuf--validate-open path line anchor)))
      (user-error "HyperBuf: %s" (cdr problem)))
    (let ((request (hyperbuf--build-request path line anchor target wait)))
      (pcase hyperbuf-transport
        ('socket (hyperbuf--open-via-socket request))
        ('cli (hyperbuf--open-via-cli request))
        (other (user-error "Unknown hyperbuf-transport: %S" other))))))

(defun hyperbuf--maybe-save ()
  "Save the current buffer according to `hyperbuf-save-before-open'."
  (when (and buffer-file-name (buffer-modified-p))
    (pcase hyperbuf-save-before-open
      ('t (save-buffer))
      ('ask (if (y-or-n-p "The viewer reads the file on disk.  Save it first? ")
                (save-buffer)
              (message "Unsaved changes will not show in the viewer")))
      (_ (message "Unsaved changes will not show in the viewer")))))

;;;###autoload
(defun hyperbuf-open-file (&optional wait)
  "Open the current buffer's file in HyperBuf at the current line.
With WAIT (the prefix argument), wait longer for confirmation in the app."
  (interactive "P")
  (unless buffer-file-name (user-error "This buffer is not visiting a file"))
  (hyperbuf--maybe-save)
  (hyperbuf-open buffer-file-name (line-number-at-pos nil t) nil nil wait))

;;;###autoload
(defun hyperbuf-open-other-window (&optional wait)
  "Open the current buffer's file in another HyperBuf window (split right).
With WAIT (the prefix argument), wait longer for confirmation in the app."
  (interactive "P")
  (unless buffer-file-name (user-error "This buffer is not visiting a file"))
  (hyperbuf--maybe-save)
  (hyperbuf-open buffer-file-name (line-number-at-pos nil t) nil "split-right" wait))

;;;###autoload
(defun hyperbuf-open-project-file (&optional wait)
  "Pick a Markdown file of the current project and open it in HyperBuf.
With WAIT (the prefix argument), wait longer for confirmation in the app."
  (interactive "P")
  (let* ((project (or (project-current) (user-error "Not inside a project")))
         (root (project-root project))
         (files (cl-remove-if-not (lambda (f) (string-suffix-p ".md" f))
                                  (mapcar (lambda (f) (file-relative-name f root))
                                          (project-files project))))
         (choice (completing-read "Markdown: " files nil t)))
    (hyperbuf-open (expand-file-name choice root) nil nil nil wait)))

;;;; From the viewer to the edit location ("Edit in Emacs")
;;
;; The place marked in the viewer is mapped to a position in the original
;; Markdown and handed to the editor.  So that a wrong place is never edited
;; silently:
;;  - The position comes from the viewer's syntax tree (not a text search).
;;  - Before moving, it is always checked: (1) the file is the same version
;;    that the viewer rendered, and (2) the expected text and its
;;    surrounding context match the buffer.
;;  - If the check fails, Emacs neither moves nor offers to continue.  It
;;    only shows a warning and the details of the mismatch
;;    (`*hyperbuf-mismatch*').
;;  - After moving, the range is highlighted briefly and the text the viewer
;;    pointed at is shown.
;; Specification: docs/integration-protocol.md section 10.
;; Shared examples: protocol/examples/location-check.json

(defun hyperbuf--file-sha256 (path)
  "Return the SHA-256 of the contents (bytes) of the file PATH.
It is compared with the version that the viewer read."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally path)
    (secure-hash 'sha256 (current-buffer))))

(defun hyperbuf--offset (text line column)
  "Return the 0-based character offset of LINE and COLUMN in TEXT.
Return nil if out of range.  LINE and COLUMN are 1-based; columns are
counted in characters (code points)."
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
  "Check LOCATION (a `get-location' location) against the buffer contents.
TEXT is the whole buffer text and DISK-SHA is the SHA-256 of the file on
disk.  Return a plist: (:status ok :start S :end E :actual ...) on
success, or (:status stale|mismatch :reason ...) on failure.  S and E
are 0-based character offsets."
  (let* ((range (plist-get location :range))
         (start (plist-get range :start))
         (end (plist-get range :end))
         (file (plist-get location :file))
         (expect (plist-get location :expect))
         (context (plist-get location :context)))
    (cond
     ((not (equal (plist-get location :v) hyperbuf--protocol-version))
      (list :status 'mismatch :reason "Unsupported location version"))
     ((not (equal (plist-get file :sha256) disk-sha))
      (list :status 'stale
            :reason "The file differs from the version the viewer rendered (what you see in the viewer and what you would edit do not match)"))
     (t
      (let ((s (hyperbuf--offset text (plist-get start :line) (plist-get start :column)))
            (e (hyperbuf--offset text (plist-get end :line) (plist-get end :column))))
        (if (not (and s e (<= s e)))
            (list :status 'mismatch :reason "The location is outside the document")
          (let ((actual (substring text s e)))
            (cond
             ((not (if (eq (plist-get location :expectTruncated) t)
                       (string-prefix-p expect actual)
                     (equal expect actual)))
              (list :status 'mismatch
                    :reason "The text at that location differs from what the viewer pointed at" :actual actual))
             ((not (string-suffix-p (plist-get context :before) (substring text 0 s)))
              (list :status 'mismatch :reason "The context before the location differs from what the viewer pointed at" :actual actual))
             ((not (string-prefix-p (plist-get context :after) (substring text e)))
              (list :status 'mismatch :reason "The context after the location differs from what the viewer pointed at" :actual actual))
             (t (list :status 'ok :start s :end e :actual actual))))))))))

(defun hyperbuf--abbreviate (string &optional limit)
  "Shorten STRING to LIMIT (default 60) characters, with newlines as spaces."
  (let ((flat (replace-regexp-in-string "[\n\r]+" " " string))
        (limit (or limit 60)))
    (if (> (length flat) limit) (concat (substring flat 0 limit) "…") flat)))

(defun hyperbuf--report-problem (location result path)
  "Show the details of a failed check of LOCATION and signal a `user-error'.
Point does not move.  The details go to the `*hyperbuf-mismatch*'
buffer.  RESULT is the check result; PATH is the file to edit."
  (let ((buffer (get-buffer-create "*hyperbuf-mismatch*"))
        (file (plist-get location :file)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "HyperBuf: The check of the edit location failed, so Emacs did not move.\n\nReason: %s\n"
                        (plist-get result :reason))
                (format "File: %s\n" path)
                (format "Text the viewer pointed at: %s\n"
                        (hyperbuf--abbreviate (or (plist-get (plist-get location :viewer) :selection) "") 200))
                (format "Location: line %d, column %d to line %d, column %d (%s)\n\n"
                        (plist-get (plist-get (plist-get location :range) :start) :line)
                        (plist-get (plist-get (plist-get location :range) :start) :column)
                        (plist-get (plist-get (plist-get location :range) :end) :line)
                        (plist-get (plist-get (plist-get location :range) :end) :column)
                        (plist-get location :precision)))
        (if (eq (plist-get result :status) 'stale)
            (insert (format "Version rendered by the viewer: SHA-256 %s (%s bytes)\nCurrent file: SHA-256 %s (%s bytes)\n\n"
                            (plist-get file :sha256) (plist-get file :size)
                            (hyperbuf--file-sha256 path)
                            (file-attribute-size (file-attributes path)))
                    "Remedy: reopen the file in the viewer (or wait for the external update to be picked up) and mark the location again.\n")
          (insert (format "Text the viewer pointed at:\n  %s\nText at that location now:\n  %s\n\n"
                          (hyperbuf--abbreviate (or (plist-get location :expect) "") 200)
                          (hyperbuf--abbreviate (or (plist-get result :actual) "(none)") 200))
                  "Remedy: check the area around the location by eye.  Emacs does not move automatically, so that no other place is edited by mistake.\n"))
        (special-mode)))
    (display-buffer buffer)
    (user-error "HyperBuf: %s (not moving; see *hyperbuf-mismatch* for details)" (plist-get result :reason))))

(defun hyperbuf--visit (location)
  "Check LOCATION; if it is fine, move to it and highlight it.
Otherwise do not move and signal a `user-error'."
  (let ((path (plist-get location :path)))
    (when-let* ((problem (hyperbuf--validate-open path)))
      (user-error "HyperBuf: Invalid file in location: %s" (cdr problem)))
    (unless (file-regular-p path) (user-error "No such file: %s" path))
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
        (message "HyperBuf: \"%s\"%s%s"
                 (hyperbuf--abbreviate (plist-get result :actual))
                 (if (equal (plist-get location :precision) "block")
                     " (the location is ambiguous, so the whole block is shown)" "")
                 (if (> age hyperbuf-location-max-age)
                     (format " (marked %d minutes ago)" (round (/ age 60))) ""))))))

;;;###autoload
(defun hyperbuf-visit-location ()
  "Move to the location marked with \"Edit in Emacs\" in the viewer.
Before moving, check the file version, the text at the location and
its surrounding context against what the viewer pointed at.  If the
check fails, do not move; show a warning and the details in
*hyperbuf-mismatch*."
  (interactive)
  (let* ((response (condition-case nil
                       (hyperbuf--socket-request
                        (list :v hyperbuf--protocol-version :id (format "emacs-%d" (emacs-pid)) :op "get-location")
                        hyperbuf-timeout)
                     (hyperbuf-not-running (user-error "HyperBuf is not running"))))
         (location (plist-get (plist-get response :result) :location)))
    (when-let* ((error (plist-get response :error))) (hyperbuf--report-error error))
    (unless location
      (user-error "No location marked in the viewer (mark one with \"Edit in Emacs\" in the viewer's context menu)"))
    (hyperbuf--visit location)))

;;;###autoload
(defun hyperbuf-edit-here ()
  "Like `hyperbuf-visit-location', and also raise the Emacs frame.
Meant to be called from emacsclient by the viewer's \"Edit in Emacs\".
Example: emacsclient -n -e \"(hyperbuf-edit-here)\""
  (interactive)
  (select-frame-set-input-focus (selected-frame))
  (hyperbuf-visit-location))

(provide 'hyperbuf)

;;; hyperbuf.el ends here
