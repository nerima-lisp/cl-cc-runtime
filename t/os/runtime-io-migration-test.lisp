(in-package :cl-cc/runtime/os/test)

(it-sequential "rt-format-nil-stream-returns-string"
  (expect (cl-cc/runtime/os:rt-format nil "~A" 42) :to-equal "42"))

(it-sequential "rt-format-explicit-stream-writes-to-it"
  (let ((s (make-string-output-stream)))
    (cl-cc/runtime/os:rt-format s "~A" "hello")
    (expect (get-output-stream-string s) :to-equal "hello")))

(it-sequential "rt-make-string-output-stream-creates-stream-and-get-empty"
  (let ((s (cl-cc/runtime/os:rt-make-string-output-stream)))
    (expect (streamp s) :to-be-truthy)
    (expect (cl-cc/runtime/os:rt-get-output-stream-string s) :to-equal "")))

(it-sequential "rt-get-output-stream-string-after-write-returns-content"
  (let ((s (cl-cc/runtime/os:rt-make-string-output-stream)))
    (write-string "hello world" s)
    (expect (cl-cc/runtime/os:rt-get-output-stream-string s) :to-equal "hello world")))

(it-sequential "rt-get-output-stream-string-works-with-standard-stream"
  (let ((s (make-string-output-stream)))
    (write-string "test" s)
    (expect (cl-cc/runtime/os:rt-get-output-stream-string s) :to-equal "test")))

(it-sequential "rt-stream-op-output-wrappers-write-in-order"
  (let ((s (make-string-output-stream)))
    (cl-cc/runtime/os:rt-write-char #\A s)
    (cl-cc/runtime/os:rt-write-string "BC" s)
    (cl-cc/runtime/os:rt-write-line "D" s)
    (expect (get-output-stream-string s) :to-equal (format nil "ABCD~%"))))

(it-sequential "rt-stream-op-input-wrappers-read-and-peek"
  (let ((s (make-string-input-stream "xyz")))
    (expect (cl-cc/runtime/os:rt-read-char s) :to-equal #\x)
    (expect (cl-cc/runtime/os:rt-peek-char s) :to-equal #\y)
    (expect (cl-cc/runtime/os:rt-read-char s) :to-equal #\y)))

(it-sequential "rt-read-line-from-string-stream"
  (let ((s (make-string-input-stream "hello")))
    (expect (cl-cc/runtime/os:rt-read-line s) :to-equal "hello")))

(it-sequential "rt-read-byte-write-byte-roundtrip-through-file"
  (let* ((path (merge-pathnames "cl-cc-runtime-io-bytes.bin" (uiop:temporary-directory)))
         (out (open path :direction :output :if-exists :supersede :element-type '(unsigned-byte 8))))
    (unwind-protect
         (progn
           (cl-cc/runtime/os:rt-write-byte 65 out)
           (cl-cc/runtime/os:rt-write-byte 66 out)
           (close out)
           (let ((in (open path :direction :input :element-type '(unsigned-byte 8))))
             (unwind-protect
                  (progn
                    (expect (cl-cc/runtime/os:rt-read-byte in) :to-equal 65)
                    (expect (cl-cc/runtime/os:rt-read-byte in) :to-equal 66))
               (close in))))
      (when (probe-file path)
        (delete-file path)))))

(it-sequential "rt-write-line-to-string"
  (let ((s (make-string-output-stream)))
    (cl-cc/runtime/os:rt-write-line "test" s)
    (expect (get-output-stream-string s) :to-equal (format nil "test~%"))))

(it-sequential "rt-peek-char-does-not-advance"
  (let ((s (make-string-input-stream "abc")))
    (let ((first-peek  (cl-cc/runtime/os:rt-peek-char s))
          (second-peek (cl-cc/runtime/os:rt-peek-char s)))
      (expect first-peek :to-equal #\a)
      (expect second-peek :to-equal #\a))))

(it-sequential "rt-make-string-stream-input-direction"
  (let ((in (cl-cc/runtime/os:rt-make-string-stream "abc" :direction :input)))
    (expect (read-char in) :to-equal #\a)))

(it-sequential "rt-make-string-stream-output-direction"
  (let ((out (cl-cc/runtime/os:rt-make-string-stream "ignored" :direction :output)))
    (write-string "ok" out)
    (expect (cl-cc/runtime/os:rt-get-output-stream-string out) :to-equal "ok")))

(it-sequential "rt-stream-element-type-is-character"
  (expect (cl-cc/runtime/os:rt-stream-element-type *standard-input*) :to-equal 'character))

(it-sequential "rt-interactive-stream-p-is-zero-for-string-stream"
  (let ((s (make-string-input-stream "x")))
    (expect (= 0 (cl-cc/runtime/os:rt-interactive-stream-p s)) :to-be-truthy)))
