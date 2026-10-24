(defpackage #:cl-cc/runtime/images
  (:use #:cl)
  (:import-from #:cl-cc/runtime/compression #:gzip-compress #:gzip-decompress #:zlib-compress #:zlib-decompress)
  (:import-from #:cl-cc/runtime/memory #:mmap-array #:mmap-file)
  (:intern
   #:*rt-code-version*
   #:*rt-image-globals*
   #:*rt-image-restore-hooks*
   #:make-rt-image
   #:make-rt-image-header
   #:rt-image-code-version
   #:rt-image-globals
   #:rt-image-p
   #:rt-validate-image
  )
  (:export
   #:*saved-core-pathname*
   #:rt-capture-image-state
   #:rt-hot-reload
   #:rt-image-init
   #:rt-image-register-global
   #:rt-image-register-restore-hook
   #:rt-load-core
   #:rt-load-image
   #:rt-restore-image-state
   #:rt-save-core
   #:rt-save-image))



