;;;; gc-binding-scan.lisp — Dynamic binding-stack and global-variable root
;;;; scanning, split out of gc-roots-objects.lisp
(in-package :cl-cc/runtime)

(defun %rt-gc-thread-binding-stack (thread)
  "Return THREAD's dynamic binding stack, if any."
  (cond
    ((and (consp thread) (getf thread :bindings)) (getf thread :bindings))
    ((boundp '*rt-dynamic-binding-stacks*)
     (gethash (%rt-gc-thread-id thread) *rt-dynamic-binding-stacks*))
    (t nil)))

(defun %rt-gc-binding-symbol (binding)
  (cond
    ((and (consp binding) (getf binding :symbol)) (getf binding :symbol))
    ((consp binding) (car binding))
    (t nil)))

(defun %rt-gc-binding-value (binding)
  (cond
    ((and (consp binding) (getf binding :value)) (getf binding :value))
    ((consp binding) (cdr binding))
    (t nil)))

(defun %rt-gc-set-binding-value (binding value)
  (cond
    ((and (consp binding) (getf binding :value))
     (setf (getf binding :value) value))
    ((consp binding)
     (setf (cdr binding) value)))
  binding)

(defun rt-gc-scan-binding-stack (heap thread)
  "Return heap pointer addresses found in THREAD's dynamic binding stack.

Bindings are treated as additional GC roots.  Bindings for global-only special
variables are skipped because those symbols never use thread-local dynamic
storage and are traced via the global/runtime registries instead."
  (check-type heap rt-heap)
  (remove-duplicates
   (loop for binding in (%rt-gc-thread-binding-stack thread)
         for sym = (%rt-gc-binding-symbol binding)
         for skip = (and sym
                         (fboundp 'rt-special-variable-global-only-p)
                         (rt-special-variable-global-only-p sym))
         for addr = (and (not skip)
                         (%rt-gc-pointer-address heap (%rt-gc-binding-value binding)))
         when addr collect addr)
   :test #'eql))

(defun %rt-gc-scan-binding-stacks (heap)
  "Return heap pointer addresses from all registered dynamic binding stacks."
  (remove-duplicates
   (loop for thread-state in *gc-threads*
         append (rt-gc-scan-binding-stack heap thread-state))
   :test #'eql))

(defun %rt-gc-global-variable-bindings ()
  "Return (SYMBOL . VALUE) bindings from the runtime global special registry."
  (when (boundp '*rt-global-var-registry*)
    (let (bindings)
      (maphash (lambda (sym value) (push (cons sym value) bindings))
               *rt-global-var-registry*)
      bindings)))

(defun %rt-gc-scan-global-variables (heap)
  "Return heap pointer addresses held by global-only special variables."
  (remove-duplicates
   (loop for binding in (%rt-gc-global-variable-bindings)
          for addr = (%rt-gc-pointer-address heap (cdr binding))
         when addr collect addr)
   :test #'eql))

(defun %rt-gc-conservative-root-addresses (heap)
  "Return stack words that conservatively look like valid heap object pointers."
  (when *gc-conservative-roots*
    (remove-duplicates
     (loop for thread-state in *gc-threads*
           append (loop for word in (%rt-gc-thread-words thread-state)
                         for addr = (%rt-gc-pointer-address heap word)
                        when addr collect addr))
     :test #'eql)))
