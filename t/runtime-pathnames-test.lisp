;;;; t/runtime-pathnames-test.lisp — Coverage for src/runtime-pathnames.lisp
;;;;
;;;; Native bignum slow-path arithmetic, pathname constructors/accessors,
;;;; filesystem operations, compound streams, sequence I/O, and LOAD.
(in-package :cl-cc-runtime/test)

(defvar *pathnames-load-flag* nil)

(defun %pn-temp (name)
  (merge-pathnames name (uiop:temporary-directory)))

;;; ------------------------------------------------------------
;;; Native bignum slow path
;;; ------------------------------------------------------------
(it-sequential
  "rt-native-bignum-allocate boxes a CL integer; rt-native-bignum-p recognises it."
  (let ((big (cl-cc/runtime::rt-native-bignum-allocate (expt 2 60))))
    (expect (cl-cc/runtime::rt-native-bignum-p big) :to-be-truthy)
    (expect (cl-cc/runtime::rt-native-bignum-to-integer big) :to-equal (expt 2 60))
    (expect (cl-cc/runtime::rt-native-bignum-p 5) :to-be-falsy)))

(it-sequential
  "rt-native-integer->value keeps small integers as fixnums, boxes large ones."
  (expect
    (cl-cc/runtime::rt-native-bignum-p
      (cl-cc/runtime::rt-native-integer->value 100))
    :to-be-falsy)
  (expect
    (cl-cc/runtime::rt-native-bignum-p
      (cl-cc/runtime::rt-native-integer->value (expt 2 60)))
    :to-be-truthy))

(it-sequential
  "Bignum add/sub/mul round-trip through the runtime value representation."
  (let ((a (cl-cc/runtime::rt-native-integer->value 10))
        (b (cl-cc/runtime::rt-native-integer->value 20)))
    (expect
      (cl-cc/runtime::rt-native-bignum-to-integer
        (cl-cc/runtime::rt-native-bignum-add a b))
      :to-equal
      30)
    (expect
      (cl-cc/runtime::rt-native-bignum-to-integer
        (cl-cc/runtime::rt-native-bignum-sub a b))
      :to-equal
      -10)
    (expect
      (cl-cc/runtime::rt-native-bignum-to-integer
        (cl-cc/runtime::rt-native-bignum-mul a b))
      :to-equal
      200)))

(it-sequential
  "Adding two near-fixnum-max values promotes the result to a bignum."
  (let* ((half (cl-cc/runtime::rt-native-integer->value (expt 2 49)))
         (sum (cl-cc/runtime::rt-native-bignum-add half half)))
    (expect (cl-cc/runtime::rt-native-bignum-p sum) :to-be-truthy)
    (expect (cl-cc/runtime::rt-native-bignum-to-integer sum) :to-equal (expt 2 50))))

;;; ------------------------------------------------------------
;;; Pathname constructors and accessors
;;; ------------------------------------------------------------
(it-sequential
  "rt-make-pathname builds a pathname whose parts are readable back."
  (let ((p (cl-cc/runtime::rt-make-pathname :name "foo" :type "lisp")))
    (expect (pathnamep p) :to-be-truthy)
    (expect (cl-cc/runtime::rt-pathnamep p) :to-be-truthy)
    (expect (cl-cc/runtime::rt-pathname-name p) :to-equal "foo")
    (expect (cl-cc/runtime::rt-pathname-type p) :to-equal "lisp")
    (expect (stringp (cl-cc/runtime::rt-namestring p)) :to-be-truthy)))

(it-sequential
  "rt-make-pathname-native accepts positional args and drops NILs."
  (let ((p
        (cl-cc/runtime::rt-make-pathname-native
          nil
          nil
          '(:relative "d")
          "b"
          "c"
          nil
          nil)))
    (expect (cl-cc/runtime::rt-pathname-name p) :to-equal "b")
    (expect (cl-cc/runtime::rt-pathname-type p) :to-equal "c")
    (expect (cl-cc/runtime::rt-pathname-directory p) :to-equal '(:relative "d"))))

(it-sequential
  "rt-merge-pathnames fills defaults from the second argument."
  (let ((merged
        (cl-cc/runtime::rt-merge-pathnames
          (make-pathname :name "only")
          (make-pathname :type "txt"))))
    (expect (pathname-name merged) :to-equal "only")
    (expect (pathname-type merged) :to-equal "txt")))

;;; ------------------------------------------------------------
;;; Filesystem operations
;;; ------------------------------------------------------------
(it-sequential
  "probe / write-date / truename / rename / delete operate on a real file."
  (let ((path (%pn-temp "clcc-pn-file.txt"))
        (renamed (%pn-temp "clcc-pn-file-2.txt")))
    (ignore-errors (delete-file path))
    (ignore-errors (delete-file renamed))
    (with-open-file (s path :direction :output :if-exists :supersede :if-does-not-exist :create)
      (write-string "hi" s))
    (expect (cl-cc/runtime::rt-probe-file path) :to-be-truthy)
    (expect (integerp (cl-cc/runtime::rt-file-write-date path)) :to-be-truthy)
    (expect (pathnamep (cl-cc/runtime::rt-truename path)) :to-be-truthy)
    (cl-cc/runtime::rt-rename-file path renamed)
    (expect (cl-cc/runtime::rt-probe-file path) :to-be-falsy)
    (expect (cl-cc/runtime::rt-probe-file renamed) :to-be-truthy)
    (cl-cc/runtime::rt-delete-file renamed)
    (expect (cl-cc/runtime::rt-probe-file renamed) :to-be-falsy)))

(it-sequential
  "rt-ensure-directories-exist creates a directory that rt-directory can list."
  (let* ((dir (merge-pathnames "clcc-pn-dir/" (uiop:temporary-directory)))
         (file (merge-pathnames "member.txt" dir)))
    (cl-cc/runtime::rt-ensure-directories-exist dir)
    (expect (cl-cc/runtime::rt-probe-file dir) :to-be-truthy)
    (with-open-file (s file :direction :output :if-exists :supersede :if-does-not-exist :create)
      (write-string "x" s))
    (let ((entries (cl-cc/runtime::rt-directory (merge-pathnames "*.txt" dir))))
      (expect
        (member "member" entries :key #'pathname-name :test #'equal)
        :to-be-truthy))
    (ignore-errors (delete-file file))))

;;; ------------------------------------------------------------
;;; Compound streams
;;; ------------------------------------------------------------
(it-sequential
  "rt-make-broadcast-stream forwards writes to each target stream."
  (let* ((out (make-string-output-stream))
         (bc (cl-cc/runtime::rt-make-broadcast-stream out)))
    (write-string "hello" bc)
    (expect (get-output-stream-string out) :to-equal "hello")))

(it-sequential
  "rt-make-concatenated-stream reads through its component streams in order."
  (let ((cc
        (cl-cc/runtime::rt-make-concatenated-stream
          (make-string-input-stream "ab")
          (make-string-input-stream "cd"))))
    (expect
      (coerce
        (loop for ch = (read-char cc nil nil)
              while ch
              collect ch)
        'string)
      :to-equal
      "abcd")))

(it-sequential
  "Compound stream constructors return the corresponding stream types."
  (let ((in (make-string-input-stream "z"))
        (out (make-string-output-stream)))
    (expect
      (typep (cl-cc/runtime::rt-make-echo-stream in out) (quote echo-stream))
      :to-be-truthy)
    (expect
      (typep
        (cl-cc/runtime::rt-make-two-way-stream (make-string-input-stream "q") out)
        (quote two-way-stream))
      :to-be-truthy)
    (expect
      (typep
        (cl-cc/runtime::rt-make-synonym-stream '*standard-output*)
        (quote synonym-stream))
      :to-be-truthy)))

;;; ------------------------------------------------------------
;;; Sequence I/O
;;; ------------------------------------------------------------
(it-sequential
  "rt-write-sequence and rt-read-sequence move characters through streams."
  (let ((out (make-string-output-stream)))
    (cl-cc/runtime::rt-write-sequence "hello" out)
    (expect (get-output-stream-string out) :to-equal "hello"))
  (let ((buf (make-string 3)))
    (with-input-from-string (in "abc")
      (cl-cc/runtime::rt-read-sequence buf in))
    (expect buf :to-equal "abc")))

;;; ------------------------------------------------------------
;;; LOAD
;;; ------------------------------------------------------------
(it-sequential
  "rt-load evaluates the forms in a source file."
  (let ((path (%pn-temp "clcc-pn-load.lisp")))
    (with-open-file (s path :direction :output :if-exists :supersede :if-does-not-exist :create)
      (write-string "(in-package :cl-cc-runtime/test)" s)
      (terpri s)
      (write-string "(setf *pathnames-load-flag* t)" s))
    (setf *pathnames-load-flag* nil)
    (cl-cc/runtime::rt-load path)
    (expect *pathnames-load-flag* :to-be-truthy)
    (ignore-errors (delete-file path))))
