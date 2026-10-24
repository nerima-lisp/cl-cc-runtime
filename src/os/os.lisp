;;;; OS Abstraction Layer (FR-570, FR-571, FR-573)
(in-package :cl-cc/runtime)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

(defconstant +rt-o-rdonly+ 0)
(defconstant +rt-o-wronly+ 1)
(defconstant +rt-o-rdwr+ 2)
(defconstant +rt-o-creat+ #o100)
(defconstant +rt-o-trunc+ #o1000)
(defconstant +rt-o-append+ #o2000)
(defstruct rt-file-handle
  "Host-backed runtime file descriptor wrapper."
  (stream nil)
  (path nil)
  (mode :input)
  (fd nil))

(defstruct rt-process-status
  (pid -1 :type integer)
  (status 0 :type integer)
  (exited-p nil)
  (signal nil))

(defstruct rt-process
  "Runtime process object used by RT-RUN-PROGRAM.

PID is the operating-system process id when available.  STATUS tracks the
runtime lifecycle (:RUNNING, :EXITED, :SIGNALED, or :UNKNOWN).  EXIT-CODE is
filled by RT-PROCESS-WAIT or by an eager wait requested from RT-RUN-PROGRAM.
INPUT, OUTPUT, and ERROR are host streams corresponding to the child stdin,
stdout, and stderr pipes when :PIPE was requested.  HOST-PROCESS stores the
CL-PROCESS-KIT:PROCESS-HANDLE used for portable process management."
  (pid nil)
  (status :running)
  (exit-code nil)
  (input nil)
  (output nil)
  (error nil)
  (host-process nil))

(defvar *rt-saved-argv* nil)
(defvar *rt-open-files* (make-hash-table :test #'eq))
(defvar *rt-platform*
  #+darwin :darwin
  #+linux :linux
  #-(or darwin linux) :unknown)

(defun rt-platform () *rt-platform*)
(defun rt-platform-darwin-p () (eq *rt-platform* :darwin))
(defun rt-platform-linux-p () (eq *rt-platform* :linux))

(defun %rt-direction-for-mode (mode)
  (cond ((member mode '(:input :read +rt-o-rdonly+ 0) :test #'equal) :input)
        ((member mode '(:output :write +rt-o-wronly+ 1) :test #'equal) :output)
        ((member mode '(:io :read-write +rt-o-rdwr+ 2) :test #'equal) :io)
        ((and (integerp mode) (not (zerop (logand mode +rt-o-rdwr+)))) :io)
        ((and (integerp mode) (not (zerop (logand mode +rt-o-wronly+)))) :output)
        (t :input)))

(defun %rt-open-options (mode if-exists if-does-not-exist)
  (let ((direction (%rt-direction-for-mode mode)))
    (values direction
            (or if-exists
                (cond ((and (integerp mode) (not (zerop (logand mode +rt-o-append+)))) :append)
                      ((and (integerp mode) (not (zerop (logand mode +rt-o-trunc+)))) :supersede)
                      ((eq direction :output) :supersede)
                      (t nil)))
            (or if-does-not-exist
                (if (and (integerp mode) (not (zerop (logand mode +rt-o-creat+))))
                    :create
                    (if (eq direction :input) :error :create))))))

(defun rt-open (path mode &key if-exists if-does-not-exist (element-type 'character))
  "Open PATH and return an RT-FILE-HANDLE. MODE accepts keywords or POSIX-like flags."
  (multiple-value-bind (direction exists missing)
      (%rt-open-options mode if-exists if-does-not-exist)
    (let* ((stream (open path :direction direction
                             :if-exists exists
                             :if-does-not-exist missing
                             :element-type element-type))
           (handle (make-rt-file-handle :stream stream :path path :mode direction
                                        :fd (ignore-errors (sb-sys:fd-stream-fd stream)))))
      (setf (gethash handle *rt-open-files*) t)
      handle)))

(defun %rt-stream (handle)
  (etypecase handle
    (rt-file-handle (rt-file-handle-stream handle))
    (stream handle)))

(defun rt-read (handle buffer &key (start 0) end)
  "Read into BUFFER from HANDLE. Return byte/character count, 0 on EOF."
  (let* ((stream (%rt-stream handle))
         (limit (or end (length buffer))))
    (or (read-sequence buffer stream :start start :end limit) 0)))

(defun rt-write (handle buffer &key (start 0) end)
  "Write BUFFER to HANDLE and return the number of elements written."
  (let* ((stream (%rt-stream handle))
         (limit (or end (length buffer))))
    (write-sequence buffer stream :start start :end limit)
    (finish-output stream)
    (- limit start)))

(defun rt-close (handle)
  (let ((stream (%rt-stream handle)))
    (when (typep handle 'rt-file-handle) (remhash handle *rt-open-files*))
    (close stream)
    t))

(defun %rt-environment-variable-name-p (name)
  "True when NAME is a syntactically valid POSIX environment variable name: a
non-empty string containing neither `=' nor NUL, the two characters that
corrupt the process environment block if passed through to
setenv(3)/unsetenv(3). POSIX's environ(7) name grammar is a fixed spec, so
this check is duplicated from cl-host-kit's
HOST-KIT::%ENVIRONMENT-VARIABLE-NAME-P rather than taken as a dependency, per
DEPENDENCY_POLICY.md's rule to prefer a small duplication over a new org
dependency when the spec being duplicated will not change."
  (and (stringp name)
       (plusp (length name))
       (not (find #\= name))
       (not (find #\Null name))))

(defun %rt-check-environment-variable-name (name)
  (unless (%rt-environment-variable-name-p name)
    (error "invalid environment variable name: ~S" name))
  name)

(defun rt-getenv (name)
  (%rt-check-environment-variable-name name)
  (sb-ext:posix-getenv name))
(defun %rt-sb-posix-call (name &rest args)
  (let ((symbol (find-symbol (string name) :sb-posix)))
    (when (and symbol (fboundp symbol))
      (apply (symbol-function symbol) args))))

(defun rt-setenv (name value &key overwrite)
  (%rt-check-environment-variable-name name)
  (%rt-sb-posix-call :setenv name value (if overwrite 1 0)))

(defun rt-unsetenv (name)
  (%rt-check-environment-variable-name name)
  (%rt-sb-posix-call :unsetenv name))
(defun rt-argv () (or *rt-saved-argv* sb-ext:*posix-argv*))
(defun rt-exit (&optional (code 0)) (sb-ext:exit :code code))

(defun rt-getcwd () (namestring (truename ".")))
(defun rt-chdir (path)
  (%rt-sb-posix-call :chdir (namestring path))
  (setf *default-pathname-defaults* (truename path))
  (namestring *default-pathname-defaults*))

(defun rt-fork ()
  "Fork the current process on POSIX hosts. Returns child pid, 0 in child, or NIL if unsupported."
  (%rt-sb-posix-call :fork))

(defun rt-exec (path argv &key env)
  "Replace current process image with PATH. Stubbed through SB-POSIX on SBCL."
  (declare (ignore env))
  (%rt-sb-posix-call :execv path (coerce argv 'vector)))

(defun rt-waitpid (pid &key nohang)
  (let ((flags (if nohang
                   (or (ignore-errors
                        (symbol-value (find-symbol "WNOHANG" :sb-posix)))
                       0)
                   0)))
    (multiple-value-bind (wpid status)
        (%rt-sb-posix-call :waitpid pid flags)
      (make-rt-process-status :pid (or wpid -1) :status (or status 0)
                              :exited-p (and wpid (not (zerop wpid)))))))

(defun %rt-dyld-interposition-var-p (entry)
  "True when ENVIRON entry ENTRY is a macOS dyld interposition variable."
  (host-kit:string-prefix-p "DYLD_INSERT_LIBRARIES=" entry))

(defun %rt-child-environment ()
  "Return a child process environment with macOS dyld interposition removed,
or NIL when no scrubbing is needed (caller should then inherit the environment).

The SBCL image may be launched with DYLD_INSERT_LIBRARIES pointing at an arm64
shim (the dispatch-semaphore fix used by the test harness). Child processes
inherit it, but macOS system binaries such as /bin/sh are arm64e, and dyld
aborts them before exec when the shim's architecture does not match. Stripping
the interposition variable keeps spawned shells and programs runnable."
  (let ((env (sb-ext:posix-environ)))
    (when (some #'%rt-dyld-interposition-var-p env)
      (remove-if #'%rt-dyld-interposition-var-p env))))

(defparameter *rt-default-process-timeout-seconds* 30
  "Default deadline, in seconds, for RT-PROCESS-WAIT and RT-SHELL. A spawned
child that outlives it is SIGTERM'd, then SIGKILL'd after a grace period (see
CL-PROCESS-KIT:RUN / CL-PROCESS-KIT:PROCESS-WAIT). Callers that need a longer
or shorter deadline pass :TIMEOUT explicitly; this only guards against a
process hanging forever with no deadline at all.")

(defun rt-run-program (command args &key (input :inherit) (output :pipe) (error :inherit) (wait nil)
                                       (timeout *rt-default-process-timeout-seconds*))
  "Run COMMAND with ARGS and return an RT-PROCESS object.

INPUT, OUTPUT, and ERROR accept :PIPE, :NULL, :INHERIT, or an existing stream,
passed straight through to CL-PROCESS-KIT:MAKE-COMMAND. When WAIT is true,
wait up to TIMEOUT seconds for process termination before returning."
  (check-type command string)
  (let* ((spec (process-kit:make-command
                command (mapcar #'princ-to-string args)
                :stdin input :stdout output :stderr error
                :environment-policy (or (%rt-child-environment) :inherit)))
         (handle (process-kit:spawn-command spec))
         (process (make-rt-process
                   :pid (process-kit:process-id handle)
                   :host-process handle
                   :input (process-kit:process-stdin handle)
                   :output (process-kit:process-output handle)
                   :error (process-kit:process-stderr handle))))
    (when wait
      (rt-process-wait process :timeout timeout))
    process))

(defun rt-process-wait (process &key (timeout *rt-default-process-timeout-seconds*))
  "Wait up to TIMEOUT seconds for PROCESS and return its exit code, or NIL if
it is still running when the deadline passes."
  (check-type process rt-process)
  (let* ((handle (rt-process-host-process process))
         (result (process-kit:process-wait handle :timeout timeout)))
    (when result
      (setf (rt-process-exit-code process) (process-kit:process-result-exit-code result)
            (rt-process-status process) :exited))
    (rt-process-exit-code process)))

(defun rt-process-kill (process signal)
  "Send SIGNAL to PROCESS's whole process group. Returns true when sent."
  (check-type process rt-process)
  (check-type signal integer)
  (and (process-kit:process-terminate (rt-process-host-process process) signal) t))

(defun rt-process-alive-p (process)
  "Return true while PROCESS appears to still be running."
  (check-type process rt-process)
  (process-kit:process-alive-p (rt-process-host-process process)))

(defun rt-shell (command &key (timeout *rt-default-process-timeout-seconds*))
  "Run COMMAND through /bin/sh and return its stdout as a string. Raises
CL-PROCESS-KIT:PROCESS-TIMEOUT-ERROR if it runs longer than TIMEOUT seconds."
  (check-type command string)
  (process-kit:process-result-stdout
   (process-kit:run-shell command :timeout timeout
                                   :environment (%rt-child-environment))))

(defun rt-gettime (&optional (clock :monotonic))
  (ecase clock
    (:monotonic (/ (get-internal-real-time) (float internal-time-units-per-second)))
    (:realtime (get-universal-time))))

(defun rt-sleep (seconds)
  (check-type seconds (real 0 *))
  (sleep seconds)
  t)

(defun rt-gettime-monotonic () (rt-gettime :monotonic))
(defun rt-gettime-real () (rt-gettime :realtime))

(defun rt-os-init (&key argv)
  (setf *rt-saved-argv* argv)
  (clrhash *rt-open-files*)
  t)

(defun rt-bootstrap-standalone (&key argv entry)
  "Bootstrap hook used by standalone binary stubs before entering compiled code."
  (rt-os-init :argv argv)
  (when entry (funcall entry))
  t)
