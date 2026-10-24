;;;; scheduler-native-thread.lisp — Native OS thread wrapper (FR-1097), split
;;;; out of scheduler.lisp
(in-package :cl-cc/runtime)

;;; Native OS threads (FR-1097)

(defstruct rt-native-thread
  "Runtime wrapper around an implementation-native OS thread."
  (host-thread nil)
  (name nil :type (or null string))
  (return-value nil)
  (error nil)
  (state :new)
  (gc-state nil))

(defvar *rt-native-thread-registry* (make-hash-table :test #'eq))

(defun %rt-register-native-thread (wrapper host-thread)
  (setf (rt-native-thread-host-thread wrapper) host-thread
        (gethash host-thread *rt-native-thread-registry*) wrapper)
  wrapper)

(defun %rt-current-native-wrapper ()
  (or (gethash sb-thread:*current-thread* *rt-native-thread-registry*)
      (let* ((name (ignore-errors (sb-thread:thread-name sb-thread:*current-thread*)))
             (wrapper (make-rt-native-thread :host-thread sb-thread:*current-thread*
                                             :name name
                                             :state :running)))
        (%rt-register-native-thread wrapper sb-thread:*current-thread*)
        wrapper)))

(defun rt-make-thread (function &key name)
  "Create an actual native OS thread and return an RT-NATIVE-THREAD wrapper."
  (check-type function function)
  (let ((wrapper (make-rt-native-thread :name name :state :starting)))
    (flet ((run-thread ()
             (let ((*rt-current-green-thread* nil))
               (%rt-register-native-thread wrapper sb-thread:*current-thread*)
               (setf (rt-native-thread-state wrapper) :running
                     (rt-native-thread-gc-state wrapper) :active)
               (rt-gc-register-thread :id sb-thread:*current-thread*
                                      :state (list :id sb-thread:*current-thread*
                                                   :name (or name "rt-native-thread")
                                                   :native-thread wrapper))
               (unwind-protect
                    (handler-case
                        (setf (rt-native-thread-return-value wrapper) (funcall function)
                              (rt-native-thread-state wrapper) :finished)
                      ;; Record the failure on WRAPPER for RT-THREAD-JOIN et al. to
                      ;; inspect; do NOT re-signal here. A condition raised in this
                      ;; thread cannot be caught by any handler in another thread's
                      ;; dynamic extent, so re-signaling only ever reaches SBCL's
                      ;; top-level debugger hook -- which, under --disable-debugger
                      ;; (as in batch/CI runs), terminates the entire process instead
                      ;; of just this thread.
                      (error (c)
                        (setf (rt-native-thread-error wrapper) c
                              (rt-native-thread-state wrapper) :failed)))
                 (rt-gc-unregister-thread sb-thread:*current-thread*)))))
      (%rt-register-native-thread
       wrapper
       (sb-thread:make-thread #'run-thread :name (or name "rt-native-thread"))))
    wrapper))

(defun rt-thread-join (thread &optional timeout)
  "Join THREAD and return its function return value."
  (check-type thread rt-native-thread)
  (if timeout
      (sb-thread:join-thread (rt-native-thread-host-thread thread) :timeout timeout :default nil)
      (sb-thread:join-thread (rt-native-thread-host-thread thread)))
  (when (rt-native-thread-error thread)
    (error (rt-native-thread-error thread)))
  (rt-native-thread-return-value thread))

(defun rt-thread-name (thread)
  (etypecase thread
    (rt-native-thread
     (or (rt-native-thread-name thread)
         (ignore-errors
          (sb-thread:thread-name (rt-native-thread-host-thread thread)))))
    (sb-thread:thread (sb-thread:thread-name thread))))

(defun rt-current-thread ()
  (%rt-current-native-wrapper))

(defun rt-thread-alive-p (thread)
  (check-type thread rt-native-thread)
  (sb-thread:thread-alive-p (rt-native-thread-host-thread thread)))

(defun rt-all-threads ()
  (mapcar (lambda (host-thread)
            (or (gethash host-thread *rt-native-thread-registry*)
                (%rt-register-native-thread
                 (make-rt-native-thread :host-thread host-thread
                                        :name (ignore-errors (sb-thread:thread-name host-thread))
                                        :state (if (sb-thread:thread-alive-p host-thread)
                                                   :running
                                                   :finished))
                 host-thread)))
          (sb-thread:list-all-threads)))

(defun rt-interrupt-thread (thread function)
  "Interrupt THREAD and run FUNCTION in that thread when supported."
  (check-type thread rt-native-thread)
  (check-type function function)
  (sb-thread:interrupt-thread (rt-native-thread-host-thread thread) function))

(defun rt-destroy-thread (thread)
  "Forcefully terminate THREAD. Discouraged; prefer cooperative cancellation."
  (check-type thread rt-native-thread)
  (setf (rt-native-thread-state thread) :destroyed)
  (sb-thread:terminate-thread (rt-native-thread-host-thread thread)))

(defun rt-thread-yield ()
  "Yield the current native thread's CPU time slice."
  (sb-thread:thread-yield)
  t)
