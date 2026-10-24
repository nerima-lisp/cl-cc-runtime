;;;; Structured logging — cl-log-kit's Handler protocol, used directly.
;;;;
;;;; LOG-DEBUG/INFO/WARN/ERROR/FATAL, WITH-LOG-CONTEXT, and friends are
;;;; cl-log-kit symbols imported and re-exported as-is (see package.lisp);
;;;; this file only wires up the runtime's default logger.
(in-package :cl-cc/runtime)

(defparameter *rt-logger* (make-logger :name "cl-cc.runtime" :handler (make-text-handler))
  "The runtime's default cl-log-kit logger. LOG-DEFAULT-* / LOG-* convenience
macros write through *DEFAULT-LOGGER*, which this sets at load time.")

(set-default-logger *rt-logger*)
