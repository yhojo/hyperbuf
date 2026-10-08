;;; hyperbuf-test.el --- Tests for hyperbuf.el  -*- lexical-binding: t; -*-

(require 'ert)
(require 'hyperbuf)

(ert-deftest hyperbuf-test-version ()
  (should (string-match-p "\\`[0-9]+\\.[0-9]+\\.[0-9]+\\'" hyperbuf-version)))

(ert-deftest hyperbuf-test-default-transport ()
  (should (eq hyperbuf-transport 'socket)))

;;; hyperbuf-test.el ends here
