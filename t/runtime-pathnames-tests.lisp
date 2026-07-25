;;;; t/runtime-pathnames-tests.lisp — Coverage for src/runtime-pathnames.lisp
;;;;
;;;; Native bignum slow-path arithmetic, pathname constructors/accessors,
;;;; filesystem operations, compound streams, sequence I/O, and LOAD.

(in-package :cl-cc-runtime/test)

(in-suite cl-cc-unit-suite)

(defvar *pathnames-load-flag* nil)

(defun %pn-temp (name)
  (merge-pathnames name (uiop:temporary-directory)))

;;; ------------------------------------------------------------
;;; Native bignum slow path
;;; ------------------------------------------------------------

(deftest pathnames-bignum-allocate-and-classify
  "rt-native-bignum-allocate boxes a CL integer; rt-native-bignum-p recognises it."
  (let ((big (cl-cc/runtime::rt-native-bignum-allocate (expt 2 60))))
    (assert-true (cl-cc/runtime::rt-native-bignum-p big))
    (assert-= (expt 2 60) (cl-cc/runtime::rt-native-bignum-to-integer big))
    (assert-false (cl-cc/runtime::rt-native-bignum-p 5))))

(deftest pathnames-integer-to-value-boxing
  "rt-native-integer->value keeps small integers as fixnums, boxes large ones."
  (assert-false (cl-cc/runtime::rt-native-bignum-p
                 (cl-cc/runtime::rt-native-integer->value 100)))
  (assert-true (cl-cc/runtime::rt-native-bignum-p
                (cl-cc/runtime::rt-native-integer->value (expt 2 60)))))

(deftest pathnames-bignum-arithmetic
  "Bignum add/sub/mul round-trip through the runtime value representation."
  (let ((a (cl-cc/runtime::rt-native-integer->value 10))
        (b (cl-cc/runtime::rt-native-integer->value 20)))
    (assert-= 30 (cl-cc/runtime::rt-native-bignum-to-integer
                  (cl-cc/runtime::rt-native-bignum-add a b)))
    (assert-= -10 (cl-cc/runtime::rt-native-bignum-to-integer
                   (cl-cc/runtime::rt-native-bignum-sub a b)))
    (assert-= 200 (cl-cc/runtime::rt-native-bignum-to-integer
                   (cl-cc/runtime::rt-native-bignum-mul a b)))))

(deftest pathnames-bignum-add-overflow-to-bignum
  "Adding two near-fixnum-max values promotes the result to a bignum."
  (let* ((half (cl-cc/runtime::rt-native-integer->value (expt 2 49)))
         (sum (cl-cc/runtime::rt-native-bignum-add half half)))
    (assert-true (cl-cc/runtime::rt-native-bignum-p sum))
    (assert-= (expt 2 50) (cl-cc/runtime::rt-native-bignum-to-integer sum))))

;;; ------------------------------------------------------------
;;; Pathname constructors and accessors
;;; ------------------------------------------------------------

(deftest pathnames-make-and-accessors
  "rt-make-pathname builds a pathname whose parts are readable back."
  (let ((p (cl-cc/runtime::rt-make-pathname :name "foo" :type "lisp")))
    (assert-true (pathnamep p))
    (assert-true (cl-cc/runtime::rt-pathnamep p))
    (assert-string= "foo" (cl-cc/runtime::rt-pathname-name p))
    (assert-string= "lisp" (cl-cc/runtime::rt-pathname-type p))
    (assert-true (stringp (cl-cc/runtime::rt-namestring p)))))

(deftest pathnames-make-native-positional
  "rt-make-pathname-native accepts positional args and drops NILs."
  (let ((p (cl-cc/runtime::rt-make-pathname-native
            nil nil '(:relative "d") "b" "c" nil nil)))
    (assert-string= "b" (cl-cc/runtime::rt-pathname-name p))
    (assert-string= "c" (cl-cc/runtime::rt-pathname-type p))
    (assert-equal '(:relative "d") (cl-cc/runtime::rt-pathname-directory p))))

(deftest pathnames-merge
  "rt-merge-pathnames fills defaults from the second argument."
  (let ((merged (cl-cc/runtime::rt-merge-pathnames
                 (make-pathname :name "only")
                 (make-pathname :type "txt"))))
    (assert-string= "only" (pathname-name merged))
    (assert-string= "txt" (pathname-type merged))))

;;; ------------------------------------------------------------
;;; Filesystem operations
;;; ------------------------------------------------------------

(deftest pathnames-file-lifecycle
  "probe / write-date / truename / rename / delete operate on a real file."
  (let ((path (%pn-temp "clcc-pn-file.txt"))
        (renamed (%pn-temp "clcc-pn-file-2.txt")))
    (ignore-errors (delete-file path))
    (ignore-errors (delete-file renamed))
    (with-open-file (s path :direction :output :if-exists :supersede
                            :if-does-not-exist :create)
      (write-string "hi" s))
    (assert-true (cl-cc/runtime::rt-probe-file path))
    (assert-true (integerp (cl-cc/runtime::rt-file-write-date path)))
    (assert-true (pathnamep (cl-cc/runtime::rt-truename path)))
    (cl-cc/runtime::rt-rename-file path renamed)
    (assert-false (cl-cc/runtime::rt-probe-file path))
    (assert-true (cl-cc/runtime::rt-probe-file renamed))
    (cl-cc/runtime::rt-delete-file renamed)
    (assert-false (cl-cc/runtime::rt-probe-file renamed))))

(deftest pathnames-ensure-directories-and-directory-list
  "rt-ensure-directories-exist creates a directory that rt-directory can list."
  (let* ((dir (merge-pathnames "clcc-pn-dir/" (uiop:temporary-directory)))
         (file (merge-pathnames "member.txt" dir)))
    (cl-cc/runtime::rt-ensure-directories-exist dir)
    (assert-true (cl-cc/runtime::rt-probe-file dir))
    (with-open-file (s file :direction :output :if-exists :supersede
                            :if-does-not-exist :create)
      (write-string "x" s))
    (let ((entries (cl-cc/runtime::rt-directory
                    (merge-pathnames "*.txt" dir))))
      (assert-true (member "member" entries
                           :key #'pathname-name :test #'equal)))
    (ignore-errors (delete-file file))))

;;; ------------------------------------------------------------
;;; Compound streams
;;; ------------------------------------------------------------

(deftest pathnames-broadcast-stream
  "rt-make-broadcast-stream forwards writes to each target stream."
  (let* ((out (make-string-output-stream))
         (bc (cl-cc/runtime::rt-make-broadcast-stream out)))
    (write-string "hello" bc)
    (assert-string= "hello" (get-output-stream-string out))))

(deftest pathnames-concatenated-stream
  "rt-make-concatenated-stream reads through its component streams in order."
  (let ((cc (cl-cc/runtime::rt-make-concatenated-stream
             (make-string-input-stream "ab")
             (make-string-input-stream "cd"))))
    (assert-string= "abcd"
                    (coerce (loop for ch = (read-char cc nil nil)
                                  while ch collect ch)
                            'string))))

(deftest pathnames-echo-two-way-synonym-stream-types
  "Compound stream constructors return the corresponding stream types."
  (let ((in (make-string-input-stream "z"))
        (out (make-string-output-stream)))
    (assert-type echo-stream (cl-cc/runtime::rt-make-echo-stream in out))
    (assert-type two-way-stream (cl-cc/runtime::rt-make-two-way-stream
                                 (make-string-input-stream "q") out))
    (assert-type synonym-stream (cl-cc/runtime::rt-make-synonym-stream
                                 '*standard-output*))))

;;; ------------------------------------------------------------
;;; Sequence I/O
;;; ------------------------------------------------------------

(deftest pathnames-write-and-read-sequence
  "rt-write-sequence and rt-read-sequence move characters through streams."
  (let ((out (make-string-output-stream)))
    (cl-cc/runtime::rt-write-sequence "hello" out)
    (assert-string= "hello" (get-output-stream-string out)))
  (let ((buf (make-string 3)))
    (with-input-from-string (in "abc")
      (cl-cc/runtime::rt-read-sequence buf in))
    (assert-string= "abc" buf)))

;;; ------------------------------------------------------------
;;; LOAD
;;; ------------------------------------------------------------

(deftest pathnames-load-executes-file
  "rt-load evaluates the forms in a source file."
  (let ((path (%pn-temp "clcc-pn-load.lisp")))
    (with-open-file (s path :direction :output :if-exists :supersede
                            :if-does-not-exist :create)
      (write-string "(in-package :cl-cc-runtime/test)" s)
      (terpri s)
      (write-string "(setf *pathnames-load-flag* t)" s))
    (setf *pathnames-load-flag* nil)
    (cl-cc/runtime::rt-load path)
    (assert-true *pathnames-load-flag*)
    (ignore-errors (delete-file path))))
