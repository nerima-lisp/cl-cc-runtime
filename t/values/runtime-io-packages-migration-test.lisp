(in-package :cl-cc/runtime/values/test)

(it-sequential "rt-make-package-creates-package"
  (let* ((pkg-name (gensym "RT-PKG-"))
         (pkg (cl-cc/runtime/values:rt-make-package pkg-name :use '(:cl))))
    (expect (stringp (cl-cc/runtime/values:rt-package-name pkg)) :to-be-truthy)
    (expect (cl-cc/runtime/values:rt-package-name pkg) :to-equal (string pkg-name))
    (expect (member pkg (cl-cc/runtime/values:rt-list-all-packages) :test #'eq) :to-be-truthy)))

(it-sequential "rt-find-package-locates-created-package"
  (let* ((pkg-name (gensym "RT-PKG-"))
         (pkg (cl-cc/runtime/values:rt-make-package pkg-name :use '(:cl))))
    (expect (cl-cc/runtime/values:rt-find-package pkg-name) :to-be pkg)))

(it-sequential "rt-find-package-prefers-runtime-registry"
  (let* ((pkg-name (gensym "RT-PKG-"))
         (pkg (cl-cc/runtime/values:rt-make-package pkg-name :use '(:cl))))
    (expect (member pkg (cl-cc/runtime/values:rt-list-all-packages) :test #'eq) :to-be-truthy)
    (expect (cl-cc/runtime/values:rt-find-package pkg-name) :to-be pkg)))

(it-sequential "rt-export-records-symbol"
  (let* ((pkg-name (gensym "RT-PKG-"))
         (pkg (cl-cc/runtime/values:rt-make-package pkg-name :use '(:cl)))
         (sym (cl-cc/runtime/values:rt-intern "FOO" pkg)))
    (cl-cc/runtime/values:rt-export sym pkg)
    (expect (multiple-value-bind (found status) (cl-cc/runtime/values:rt-find-symbol "FOO" pkg) (and (eq found sym) (eq status :external))) :to-be-truthy)))

(it-sequential "rt-use-unuse-package-maintains-inherited-symbols"
  (let ((cl-cc/runtime/values:*rt-package-registry* (make-hash-table :test #'equal)))
    (let* ((lib (cl-cc/runtime/values:rt-make-package "RT-USE-LIB"))
           (user (cl-cc/runtime/values:rt-make-package "RT-USE-USER"))
           (sym (cl-cc/runtime/values:rt-intern "EXPORTED" lib)))
      (cl-cc/runtime/values:rt-export sym lib)
      (expect (cl-cc/runtime/values:rt-use-package lib user) :to-be-truthy)
      (multiple-value-bind (found status)
          (cl-cc/runtime/values:rt-find-symbol "EXPORTED" user)
        (expect found :to-be sym)
        (expect status :to-be :inherited))
      (expect (cl-cc/runtime/values:rt-use-package lib user) :to-be-truthy)
      (expect (multiple-value-bind (found status) (cl-cc/runtime/values:rt-find-symbol "EXPORTED" user) (and found (eq status :inherited))) :to-be-truthy)
      (cl-cc/runtime/values:rt-unuse-package lib user)
      (multiple-value-bind (found status)
          (cl-cc/runtime/values:rt-find-symbol "EXPORTED" user)
        (expect found :to-be nil)
        (expect status :to-be nil)))))
