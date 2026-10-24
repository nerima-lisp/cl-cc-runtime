(in-package :cl-cc/runtime/conditions/test)

(it-sequential
  "rt-make-hash-table rejects an unsupported weakness mode."
  (signals error (cl-cc/runtime::rt-make-hash-table :weakness :bogus)))
