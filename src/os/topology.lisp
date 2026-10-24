;;;; topology.lisp — CPU core count detection and rt-cpu-topology/affinity
;;;; entry points. NUMA node detection and memory tier info are in
;;;; topology-numa-memory.lisp.
(in-package :cl-cc/runtime)

(defvar *rt-detected-cpu-cores* nil
  "Cached runtime-visible CPU core count for this process.")

(defvar *rt-detected-numa-topology* nil
  "Cached NUMA topology for this process.")

(defun %rt-file-lines (path)
  (ignore-errors
    (with-open-file (stream path :direction :input :if-does-not-exist nil)
      (when stream
        (loop for line = (read-line stream nil nil)
              while line
              collect line)))))

(defun %rt-file-string (path)
  (let ((lines (%rt-file-lines path)))
    (when lines
      (format nil "~{~a~^~%~}" lines))))

(defun %rt-trim (string)
  (string-trim '(#\Space #\Tab #\Newline #\Return) string))

(defun %rt-split-string (string delimiter)
  (loop with start = 0
        for pos = (position delimiter string :start start)
        collect (subseq string start pos)
        while pos
        do (setf start (1+ pos))))

(defun %rt-parse-positive-integer (string)
  (ignore-errors
    (let ((value (parse-integer (%rt-trim string) :junk-allowed t)))
      (when (and value (plusp value)) value))))

#+darwin
(defun %rt-darwin-run-program-environment ()
  (list (format nil "PATH=~a"
                (or (sb-ext:posix-getenv "PATH")
                    "/usr/bin:/bin:/usr/sbin:/sbin"))))

(defparameter *rt-topology-probe-timeout-seconds* 2
  "Timeout in seconds for external CPU/NUMA topology probe commands
(numactl, getconf, nproc, sysctl).  These run at heap/GC configuration time,
so a hung probe must never stall the runtime; on timeout the probe is treated
as unavailable (NIL), exactly like a command failure.")

(defun %rt-run-program-output (program args)
  (handler-case
      (sb-ext:with-timeout *rt-topology-probe-timeout-seconds*
        (ignore-errors
          (let ((out (make-string-output-stream)))
            (let ((process (sb-ext:run-program program args
                                               :search t
                                               :output out
                                               :error nil
                                               :wait t
                                               #+darwin :environment
                                               #+darwin (%rt-darwin-run-program-environment))))
              (when (and process (zerop (sb-ext:process-exit-code process)))
                (%rt-trim (get-output-stream-string out)))))))
    (sb-ext:timeout () nil)))

(defun %rt-parse-non-negative-integer (string &key start end)
  (ignore-errors
    (let ((value (parse-integer string
                                :start (or start 0)
                                :end end
                                :junk-allowed t)))
      (when (and value (<= 0 value)) value))))

(defun %rt-parse-cpu-token (token)
  (let ((cpu (%rt-parse-non-negative-integer (%rt-trim token))))
    (when cpu (list cpu))))

(defun %rt-parse-cpu-range-token (token dash)
  (let ((start (%rt-parse-non-negative-integer token :end dash))
        (end (%rt-parse-non-negative-integer token :start (1+ dash))))
    (when (and start end (<= start end))
      (loop for cpu from start to end collect cpu))))

(defun %rt-parse-cpulist-token (token)
  (let* ((piece (%rt-trim token))
         (dash (position #\- piece)))
    (cond
      ((zerop (length piece)) nil)
      (dash (%rt-parse-cpu-range-token piece dash))
      (t (%rt-parse-cpu-token piece)))))

(defun %rt-parse-cpulist (text)
  (when text
    (remove-duplicates
     (loop for part in (%rt-split-string (%rt-trim text) #\,)
           append (%rt-parse-cpulist-token part))
     :test #'eql)))

(defun %rt-default-cpu-list ()
  (loop for cpu below (detect-cpu-cores) collect cpu))

(defun %rt-linux-cpu-count-from-proc ()
  (let ((processors 0)
        (max-id -1))
    (dolist (line (%rt-file-lines "/proc/cpuinfo"))
      (let ((colon (position #\: line)))
        (when colon
          (let ((key (%rt-trim (subseq line 0 colon)))
                (value (%rt-trim (subseq line (1+ colon)))))
            (when (string= key "processor")
              (incf processors)
              (let ((id (parse-integer value :junk-allowed t)))
                (when id (setf max-id (max max-id id)))))))))
    (cond ((plusp processors) processors)
          ((>= max-id 0) (1+ max-id))
          (t nil))))

(defun %rt-linux-cpu-count-from-getconf ()
  (%rt-parse-positive-integer
   (or (%rt-run-program-output "getconf" '("_NPROCESSORS_ONLN"))
       (%rt-run-program-output "nproc" '()))))

(defun %rt-darwin-cpu-count ()
  (%rt-parse-positive-integer
   (or (%rt-run-program-output "/usr/sbin/sysctl" '("-n" "hw.ncpu"))
       (%rt-run-program-output "sysctl" '("-n" "hw.ncpu")))))

(defun %rt-detect-cpu-cores-uncached ()
  (or #+linux (or (%rt-linux-cpu-count-from-proc)
                  (%rt-linux-cpu-count-from-getconf))
      #+darwin (%rt-darwin-cpu-count)
      1))

(defun detect-cpu-cores ()
  "Detect the number of online CPU cores visible to the runtime.

Linux hosts prefer /proc/cpuinfo and fall back to getconf/nproc. macOS hosts
query sysctl hw.ncpu. Unsupported hosts return 1. The return value is always a
positive integer. The result is cached because host topology is stable during a
compiler process and external detection can be expensive under Nix wrappers."
  (or *rt-detected-cpu-cores*
      (setf *rt-detected-cpu-cores*
            (%rt-detect-cpu-cores-uncached))))
