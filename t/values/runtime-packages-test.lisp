(in-package :cl-cc/runtime/values/test)

(it-sequential "rt-bootstrap-common-lisp-canonical-name"
  (let ((cl-cc/runtime::*rt-package-registry* (make-hash-table :test #'equal)))
    (cl-cc/runtime::%rt-bootstrap-package-registry)
    (let ((package (cl-cc/runtime::rt-find-package "CL")))
      (expect (cl-cc/runtime::rt-package-name package) :to-equal "COMMON-LISP")
      (expect (cl-cc/runtime::rt-find-package "COMMON-LISP") :to-be package)
      (expect (cl-cc/runtime::rt-package-nicknames package) :to-equal '("CL")))))

(it-sequential "rt-package-name-custom-nickname"
  (let* ((cl-cc/runtime::*rt-package-registry* (make-hash-table :test #'equal))
         (package (cl-cc/runtime::rt-make-package "RUNTIME-CANONICAL"
                                                :nicknames '("RUNTIME-ALIAS"))))
    (expect (cl-cc/runtime::rt-package-name "RUNTIME-ALIAS")
            :to-equal "RUNTIME-CANONICAL")
    (expect (cl-cc/runtime::rt-find-package "RUNTIME-ALIAS") :to-be package)))

(it-sequential "rt-intern-resolves-late-host-package"
  (let* ((cl-cc/runtime::*rt-package-registry* (make-hash-table :test #'equal))
         (name (symbol-name (gensym "RUNTIME-LATE-HOST-")))
         (descriptor (cl-cc/runtime::rt-make-package name))
         (host nil))
    (unwind-protect
         (progn
           (expect (gethash :host-package descriptor) :to-be nil)
           (setf host (make-package name :use nil))
           (let ((symbol (intern "REGISTER-SMT-SOLVER" host)))
             (expect (cl-cc/runtime::rt-intern "REGISTER-SMT-SOLVER" descriptor) :to-be symbol)
             (expect (cl-cc/runtime::rt-intern "REGISTER-SMT-SOLVER" name) :to-be symbol)
             (expect (gethash :host-package descriptor) :to-be host)))
      (when host (delete-package host)))))

(it-sequential "rt-intern-runtime-symbol-statuses"
  (let* ((cl-cc/runtime::*rt-package-registry* (make-hash-table :test (function equal)))
         (package (cl-cc/runtime::rt-make-package (symbol-name (gensym "RT-STATUS-"))))
         (created (multiple-value-list (cl-cc/runtime::rt-intern "ITEM" package)))
         (symbol (first created)))
    (expect created :to-equal (list symbol nil))
    (expect (multiple-value-list (cl-cc/runtime::rt-intern "ITEM" package))
            :to-equal (list symbol :internal))
    (cl-cc/runtime::rt-export symbol package)
    (expect (multiple-value-list (cl-cc/runtime::rt-intern "ITEM" package))
            :to-equal (list symbol :external))
    (cl-cc/runtime::rt-unexport symbol package)
    (expect (multiple-value-list (cl-cc/runtime::rt-intern "ITEM" package))
            :to-equal (list symbol :internal))
    (%assert-facade-export-surface)))

(it-sequential "rt-intern-present-and-inherited-nil-symbol"
  (let* ((cl-cc/runtime::*rt-package-registry* (make-hash-table :test #'equal))
         (source (cl-cc/runtime::rt-make-package (symbol-name (gensym "RT-NIL-SOURCE-"))))
         (target (cl-cc/runtime::rt-make-package (symbol-name (gensym "RT-NIL-TARGET-")))))
    (cl-cc/runtime::rt-import (list nil) source)
    (expect (multiple-value-list (cl-cc/runtime::rt-intern "NIL" source))
            :to-equal '(nil :internal))
    (expect (multiple-value-list (cl-cc/runtime::rt-find-symbol "NIL" source))
            :to-equal '(nil :internal))
    (cl-cc/runtime::rt-export (list nil) source)
    (expect (multiple-value-list (cl-cc/runtime::rt-intern "NIL" source))
            :to-equal '(nil :external))
    (expect (multiple-value-list (cl-cc/runtime::rt-find-symbol "NIL" source))
            :to-equal '(nil :external))
    (cl-cc/runtime::rt-use-package source target)
    (expect (multiple-value-list (cl-cc/runtime::rt-intern "NIL" target))
            :to-equal '(nil :inherited))
    (expect (multiple-value-list (cl-cc/runtime::rt-find-symbol "NIL" target))
            :to-equal '(nil :inherited))
    (expect (multiple-value-list (cl-cc/runtime::rt-find-symbol "MISSING" target))
            :to-equal '(nil nil))
    (expect (multiple-value-list (cl-cc/runtime::rt-intern "NIL" target))
            :to-equal '(nil :inherited))
    (expect (nth-value 1 (gethash "NIL" (gethash :symbols target))) :to-be nil)))

(it-sequential "rt-intern-runtime-inherited-identity"
  (let* ((cl-cc/runtime::*rt-package-registry* (make-hash-table :test #'equal))
         (source (cl-cc/runtime::rt-make-package (symbol-name (gensym "RT-USE-SOURCE-"))))
         (symbol (cl-cc/runtime::rt-intern "ITEM" source))
         (target (cl-cc/runtime::rt-make-package (symbol-name (gensym "RT-USE-TARGET-")))))
    (cl-cc/runtime::rt-export symbol source)
    (cl-cc/runtime::rt-use-package source target)
    (expect (multiple-value-list (cl-cc/runtime::rt-intern "ITEM" target))
            :to-equal (list symbol :inherited))
    (expect (multiple-value-list (cl-cc/runtime::rt-intern "ITEM" target))
            :to-equal (list symbol :inherited))
    (expect (nth-value 1 (gethash "ITEM" (gethash :symbols target))) :to-be nil)
    (cl-cc/runtime::rt-import symbol target)
    (expect (multiple-value-list (cl-cc/runtime::rt-intern "ITEM" target))
            :to-equal (list symbol :internal))))

(it-sequential "rt-intern-host-symbol-statuses"
  (let* ((cl-cc/runtime::*rt-package-registry* (make-hash-table :test #'equal))
         (host (make-package (symbol-name (gensym "RT-HOST-STATUS-")) :use nil)))
    (unwind-protect
         (let* ((descriptor (cl-cc/runtime::rt-make-package (package-name host)))
                (created (multiple-value-list (cl-cc/runtime::rt-intern "ITEM" descriptor)))
                (symbol (first created)))
           (expect created :to-equal (list (find-symbol "ITEM" host) nil))
           (expect (multiple-value-list (cl-cc/runtime::rt-intern "ITEM" descriptor))
                   :to-equal (list symbol :internal))
           (export symbol host)
           (expect (multiple-value-list (cl-cc/runtime::rt-intern "ITEM" descriptor))
                   :to-equal (list symbol :external))
           (unexport symbol host)
           (expect (multiple-value-list (cl-cc/runtime::rt-intern "ITEM" descriptor))
                   :to-equal (list symbol :internal)))
      (delete-package host))))

(it-sequential "rt-intern-host-inherited-identity"
  (let* ((cl-cc/runtime::*rt-package-registry* (make-hash-table :test #'equal))
         (host (make-package (symbol-name (gensym "RT-HOST-USE-")) :use '("COMMON-LISP"))))
    (unwind-protect
         (let ((descriptor (cl-cc/runtime::rt-make-package (package-name host))))
           (expect (multiple-value-list (cl-cc/runtime::rt-intern "CAR" descriptor))
                   :to-equal '(cl:car :inherited))
           (expect (multiple-value-list (cl-cc/runtime::rt-intern "CAR" descriptor))
                   :to-equal '(cl:car :inherited))
           (expect (multiple-value-list (cl-cc/runtime::rt-intern "NIL" descriptor))
                   :to-equal '(nil :inherited))
           (expect (nth-value 1 (gethash "CAR" (gethash :symbols descriptor))) :to-be nil))
      (delete-package host))))

(it-sequential "rt-intern-late-host-promotion-statuses"
  (let* ((cl-cc/runtime::*rt-package-registry* (make-hash-table :test #'equal))
         (name (symbol-name (gensym "RT-LATE-STATUS-")))
         (descriptor (cl-cc/runtime::rt-make-package name))
         (before (cl-cc/runtime::rt-intern "ITEM" descriptor))
         (host nil))
    (unwind-protect
         (progn
           (expect (multiple-value-list (cl-cc/runtime::rt-intern "ITEM" descriptor))
                   :to-equal (list before :internal))
           (setf host (make-package name :use nil))
           (let ((symbol (intern "ITEM" host)))
             (export symbol host)
             (expect (multiple-value-list (cl-cc/runtime::rt-intern "ITEM" descriptor))
                     :to-equal (list symbol :external))
             (expect (multiple-value-list (cl-cc/runtime::rt-intern "ITEM" name))
                     :to-equal (list symbol :external))
             (expect (gethash "ITEM" (gethash :symbols descriptor)) :to-be symbol)))
      (when host (delete-package host)))))

(it-sequential "rt-intern-late-host-new-symbol-status"
  (let* ((cl-cc/runtime::*rt-package-registry* (make-hash-table :test #'equal))
         (name (symbol-name (gensym "RT-LATE-NEW-")))
         (descriptor (cl-cc/runtime::rt-make-package name))
         (before (cl-cc/runtime::rt-intern "ITEM" descriptor))
         (host nil))
    (unwind-protect
         (progn
           (setf host (make-package name :use nil))
           (let* ((created (multiple-value-list (cl-cc/runtime::rt-intern "ITEM" descriptor)))
                  (symbol (first created)))
             (expect created :to-equal (list (find-symbol "ITEM" host) nil))
             (expect (eq before symbol) :to-be nil)
             (expect (multiple-value-list (cl-cc/runtime::rt-intern "ITEM" descriptor))
                     :to-equal (list symbol :internal))))
      (when host (delete-package host)))))

(it-sequential "rt-intern-imported-symbol-status-precedence"
  (let* ((cl-cc/runtime::*rt-package-registry* (make-hash-table :test #'equal))
         (name (symbol-name (gensym "RT-IMPORT-STATUS-")))
         (descriptor (cl-cc/runtime::rt-make-package name))
         (host nil))
    (unwind-protect
         (progn
           (cl-cc/runtime::rt-import 'cl:car descriptor)
           (setf host (make-package name :use nil))
           (export (intern "CAR" host) host)
           (expect (multiple-value-list (cl-cc/runtime::rt-intern "CAR" descriptor))
                   :to-equal '(cl:car :internal))
           (cl-cc/runtime::rt-export 'cl:car descriptor)
           (expect (multiple-value-list (cl-cc/runtime::rt-intern "CAR" descriptor))
                   :to-equal '(cl:car :external)))
      (when host (delete-package host)))))

(it-sequential "rt-intern-preserves-imported-host-symbol"
  (let* ((cl-cc/runtime::*rt-package-registry* (make-hash-table :test #'equal))
         (name (symbol-name (gensym "RUNTIME-IMPORTED-HOST-")))
         (descriptor (cl-cc/runtime::rt-make-package name))
         (symbol 'cl:car)
         (host nil))
    (unwind-protect
         (progn
           (cl-cc/runtime::rt-import symbol descriptor)
           (expect (cl-cc/runtime::rt-intern "CAR" descriptor) :to-be symbol)
           (setf host (make-package name :use nil))
           (intern "CAR" host)
           (expect (cl-cc/runtime::rt-intern "CAR" descriptor) :to-be symbol)
           (expect (gethash :host-package descriptor) :to-be host))
      (when host (delete-package host)))))

(it-sequential "rt-intern-promotes-cached-uninterned-symbol"
  (let* ((cl-cc/runtime::*rt-package-registry* (make-hash-table :test #'equal))
         (name (symbol-name (gensym "RUNTIME-CACHED-HOST-")))
         (descriptor (cl-cc/runtime::rt-make-package name))
         (before (cl-cc/runtime::rt-intern "REGISTER-SMT-SOLVER" descriptor))
         (host nil))
    (unwind-protect
         (progn
           (expect (symbol-package before) :to-be nil)
           (expect (cl-cc/runtime::rt-intern "REGISTER-SMT-SOLVER" descriptor) :to-be before)
           (setf host (make-package name :use nil))
           (let ((symbol (intern "REGISTER-SMT-SOLVER" host)))
             (expect (cl-cc/runtime::rt-intern "REGISTER-SMT-SOLVER" descriptor) :to-be symbol)
             (expect (gethash "REGISTER-SMT-SOLVER" (gethash :symbols descriptor))
                     :to-be symbol)))
      (when host (delete-package host)))))
