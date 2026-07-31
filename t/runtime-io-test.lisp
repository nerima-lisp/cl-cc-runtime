;;;; t/runtime-io-test.lisp — Runtime I/O Unit Tests
;;;;
;;;; Tests for packages/runtime/src/runtime-io.lisp:
;;;; define-rt-stream-op macro, format/read-line/write-line/peek-char,
;;;; string-output-stream helpers, stream predicates, and pathname utilities.
(in-package :cl-cc-runtime/test)

;;; ─── rt-format ──────────────────────────────────────────────────────────────
(it-sequential
  "rt-format with nil stream returns the formatted string directly."
  (expect (cl-cc/runtime::rt-format nil "~A" 42) :to-equal "42"))

(it-sequential
  "rt-format with an explicit stream writes the formatted output to that stream."
  (let ((s (make-string-output-stream)))
    (cl-cc/runtime::rt-format s "~A" "hello")
    (expect (get-output-stream-string s) :to-equal "hello")))

;;; ─── String output stream helpers ──────────────────────────────────────────
(it-sequential
  "rt-make-string-output-stream produces a stream; get-output-stream-string returns empty initially."
  (let ((s (cl-cc/runtime::rt-make-string-output-stream)))
    (expect (streamp s) :to-be-truthy)
    (expect (cl-cc/runtime::rt-get-output-stream-string s) :to-equal "")))

(it-sequential
  "rt-get-output-stream-string returns the written content after write-string."
  (let ((s (cl-cc/runtime::rt-make-string-output-stream)))
    (write-string "hello world" s)
    (expect (cl-cc/runtime::rt-get-output-stream-string s) :to-equal "hello world")))

(it-sequential
  "rt-get-output-stream-string also works with a standard make-string-output-stream."
  (let ((s (make-string-output-stream)))
    (write-string "test" s)
    (expect (cl-cc/runtime::rt-get-output-stream-string s) :to-equal "test")))

(it-sequential
  "rt-write-char, rt-write-string, rt-write-line all target an explicit output stream."
  (let ((s (make-string-output-stream)))
    (cl-cc/runtime::rt-write-char #\A s)
    (cl-cc/runtime::rt-write-string "BC" s)
    (cl-cc/runtime::rt-write-line "D" s)
    (expect (get-output-stream-string s) :to-equal (format nil "ABCD~%"))))

(it-sequential
  "rt-read-char consumes; rt-peek-char does not advance the stream."
  (let ((s (make-string-input-stream "xyz")))
    (expect (cl-cc/runtime::rt-read-char s) :to-equal #\x)
    (expect (cl-cc/runtime::rt-peek-char s) :to-equal #\y)
    (expect (cl-cc/runtime::rt-read-char s) :to-equal #\y)))

;;; ─── rt-read-line ───────────────────────────────────────────────────────────
(it-sequential
  "rt-read-line reads a line from a string input stream."
  (let ((s (make-string-input-stream "hello")))
    (expect (cl-cc/runtime::rt-read-line s) :to-equal "hello")))

(it-sequential
  "Binary byte helpers round-trip bytes through a temporary file stream."
  (let* ((path (merge-pathnames "cl-cc-runtime-io-bytes.bin" (uiop:temporary-directory)))
         (out
        (open
          path
          :direction
          :output
          :if-exists
          :supersede
          :element-type
          '(unsigned-byte 8))))
    (unwind-protect (progn
        (cl-cc/runtime::rt-write-byte 65 out)
        (cl-cc/runtime::rt-write-byte 66 out)
        (close out)
        (let ((in (open path :direction :input :element-type '(unsigned-byte 8))))
          (unwind-protect (progn
              (expect (cl-cc/runtime::rt-read-byte in) :to-equal 65)
              (expect (cl-cc/runtime::rt-read-byte in) :to-equal 66))
            (close in))))
      (when (probe-file path)
        (delete-file path)))))

;;; ─── rt-write-line ──────────────────────────────────────────────────────────
(it-sequential
  "rt-write-line writes string followed by newline to stream."
  (let ((s (make-string-output-stream)))
    (cl-cc/runtime::rt-write-line "test" s)
    (expect (get-output-stream-string s) :to-equal (format nil "test~%"))))

;;; ─── Package wrappers ───────────────────────────────────────────────────────
(it-sequential
  "rt-make-package creates a runtime package descriptor and records it in the registry."
  (let* ((pkg-name (gensym "RT-PKG-"))
         (pkg (cl-cc/runtime::rt-make-package pkg-name :use '(:cl))))
    (expect (hash-table-p pkg) :to-be-truthy)
    (expect (gethash :name pkg) :to-equal (string pkg-name))
    (expect
      (gethash (string pkg-name) cl-cc/runtime::*rt-package-registry*)
      :to-be
      pkg)))

(it-sequential
  "rt-find-package returns the descriptor created through rt-make-package."
  (let* ((pkg-name (gensym "RT-PKG-"))
         (pkg (cl-cc/runtime::rt-make-package pkg-name :use '(:cl))))
    (expect (cl-cc/runtime::rt-find-package pkg-name) :to-be pkg)))

(it-sequential
  "rt-find-package resolves through runtime registry metadata once seeded."
  (let* ((pkg-name (gensym "RT-PKG-"))
         (pkg (cl-cc/runtime::rt-make-package pkg-name :use '(:cl))))
    (expect
      (gethash (string pkg-name) cl-cc/runtime::*rt-package-registry*)
      :to-be
      pkg)
    (expect (cl-cc/runtime::rt-find-package pkg-name) :to-be pkg)))

(it-sequential
  "rt-export records the symbol in runtime package metadata."
  (let* ((pkg-name (gensym "RT-PKG-"))
         (pkg (cl-cc/runtime::rt-make-package pkg-name :use '(:cl)))
         (sym (cl-cc/runtime::rt-intern "FOO" pkg)))
    (cl-cc/runtime::rt-export sym pkg)
    (expect (member sym (gethash :exports pkg) :test #'eq) :to-be-truthy)))

(it-sequential
  "rt-use-package de-duplicates use-list entries and rt-unuse-package rebuilds inherited symbols."
  (let ((cl-cc/runtime::*rt-package-registry* (make-hash-table :test #'equal)))
    (let* ((lib (cl-cc/runtime::rt-make-package "RT-USE-LIB"))
           (user (cl-cc/runtime::rt-make-package "RT-USE-USER"))
           (sym (cl-cc/runtime::rt-intern "EXPORTED" lib)))
      (cl-cc/runtime::rt-export sym lib)
      (expect (cl-cc/runtime::rt-use-package lib user) :to-be-truthy)
      (multiple-value-bind (found status) (cl-cc/runtime::rt-find-symbol "EXPORTED" user)
        (expect found :to-be sym)
        (expect status :to-be :inherited))
      (expect (cl-cc/runtime::rt-use-package lib user) :to-be-truthy)
      (expect (length (gethash :use-list user)) :to-equal 1)
      (cl-cc/runtime::rt-unuse-package lib user)
      (multiple-value-bind (found status) (cl-cc/runtime::rt-find-symbol "EXPORTED" user)
        (expect found :to-be nil)
        (expect status :to-be nil)))))

;;; ─── rt-peek-char ───────────────────────────────────────────────────────────
(it-sequential
  "rt-peek-char returns next character without consuming it; peeking twice gives same char."
  (let ((s (make-string-input-stream "abc")))
    (let ((first-peek (cl-cc/runtime::rt-peek-char s))
          (second-peek (cl-cc/runtime::rt-peek-char s)))
      (expect first-peek :to-equal #\a)
      (expect second-peek :to-equal #\a))))

(it-sequential
  "rt-make-string-stream :input creates a readable stream; first char is 'a'."
  (let ((in (cl-cc/runtime::rt-make-string-stream "abc" :direction :input)))
    (expect (read-char in) :to-equal #\a)))

(it-sequential
  "rt-make-string-stream :output creates a writable stream; written content is retrievable."
  (let ((out (cl-cc/runtime::rt-make-string-stream "ignored" :direction :output)))
    (write-string "ok" out)
    (expect (cl-cc/runtime::rt-get-output-stream-string out) :to-equal "ok")))

;;; ─── Stream predicates ──────────────────────────────────────────────────────
(it-sequential
  "rt-stream-element-type returns 'character for standard-input."
  (expect
    (cl-cc/runtime::rt-stream-element-type *standard-input*)
    :to-equal
    'character))

(it-sequential
  "rt-interactive-stream-p returns 0 for a non-interactive string input stream."
  (let ((s (make-string-input-stream "x")))
    (expect (cl-cc/runtime::rt-interactive-stream-p s) :to-equal 0)))
