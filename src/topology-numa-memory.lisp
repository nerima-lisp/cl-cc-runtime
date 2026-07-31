;;;; topology-numa-memory.lisp — NUMA node topology, CPU affinity masks, and
;;;; memory tier (NVMe/HBM) detection, split out of topology.lisp
(in-package :cl-cc/runtime)

;; SB-ALIEN is part of the SBCL core (not a loadable contrib), so no
;; (require :sb-alien) — requiring it fails on SBCL builds without a
;; module provider for it, e.g. the Nix sandbox on Linux.

#+(and sbcl linux)
(sb-alien:define-alien-routine ("sched_getaffinity" %rt-sched-getaffinity) sb-alien:int
  (pid sb-alien:int)
  (cpusetsize sb-alien:unsigned-long)
  (mask (* sb-alien:unsigned-char)))

#+(and sbcl linux)
(sb-alien:define-alien-routine ("sched_setaffinity" %rt-sched-setaffinity) sb-alien:int
  (pid sb-alien:int)
  (cpusetsize sb-alien:unsigned-long)
  (mask (* sb-alien:unsigned-char)))

(defconstant +rt-affinity-mask-bytes+ 128
  "Bytes reserved for Linux cpu_set_t-compatible affinity masks.")

#+(and sbcl linux)
(defun %rt-affinity-vector->cpus (mask)
  (loop for byte-index below (length mask)
        append (loop with byte = (aref mask byte-index)
                     for bit below 8
                     for cpu = (+ (* byte-index 8) bit)
                     when (not (zerop (logand byte (ash 1 bit))))
                       collect cpu)))

#+(and sbcl linux)
(defun %rt-cpus->affinity-vector (cpus)
  (let ((mask (make-array +rt-affinity-mask-bytes+
                          :element-type '(unsigned-byte 8)
                          :initial-element 0)))
    (dolist (cpu cpus mask)
      (when (and (integerp cpu) (<= 0 cpu) (< cpu (* +rt-affinity-mask-bytes+ 8)))
        (multiple-value-bind (byte-index bit) (floor cpu 8)
          (setf (aref mask byte-index)
                (logior (aref mask byte-index) (ash 1 bit))))))))

#+(and sbcl linux)
(defun %rt-with-affinity-alien-mask (mask function)
  (sb-alien:with-alien ((alien-mask (array sb-alien:unsigned-char #.+rt-affinity-mask-bytes+)))
    (loop for i below +rt-affinity-mask-bytes+
          do (setf (sb-alien:deref alien-mask i) (aref mask i)))
    (funcall function mask (sb-alien:addr alien-mask))))

#+(and sbcl linux)
(defun %rt-copy-affinity-mask-from-alien (mask alien-mask)
  (loop for i below +rt-affinity-mask-bytes+
        do (setf (aref mask i) (sb-alien:deref alien-mask i)))
  mask)

#+(and sbcl linux)
(defun %rt-get-affinity-with-alien-mask (mask alien-mask)
  (when (zerop (%rt-sched-getaffinity 0 +rt-affinity-mask-bytes+ alien-mask))
    (%rt-affinity-vector->cpus
     (%rt-copy-affinity-mask-from-alien mask alien-mask))))

#+(and sbcl linux)
(defun %rt-set-affinity-with-alien-mask (mask alien-mask)
  (declare (ignore mask))
  (when (zerop (%rt-sched-setaffinity 0 +rt-affinity-mask-bytes+ alien-mask))
    (get-cpu-affinity-mask)))

(defun %rt-linux-node-id-from-path (pathname)
  (let* ((directory (pathname-directory pathname))
         (node-name (car (last directory))))
    (when (and node-name
               (>= (length node-name) 5)
               (string= node-name "node" :end1 4))
      (parse-integer node-name :start 4 :junk-allowed t))))

(defun %rt-linux-node-memory-bytes (node-id)
  (let ((path (format nil "/sys/devices/system/node/node~d/meminfo" node-id)))
    (loop for line in (%rt-file-lines path)
          for marker = "MemTotal:"
          when (search marker line)
            do (let* ((after (subseq line (+ (search marker line) (length marker))))
                      (kb (parse-integer after :junk-allowed t)))
                 (return (and kb (* kb 1024)))))))

(defun %rt-topology-node-id (node)
  (getf node :node-id))

(defun %rt-node-memory-bytes-or-zero (node)
  (or (getf node :memory-bytes) 0))

(defun %rt-sort-topology-nodes (nodes)
  (sort nodes #'< :key #'%rt-topology-node-id))

(defun %rt-topology-memory-bytes (nodes)
  (reduce #'+ nodes :key #'%rt-node-memory-bytes-or-zero :initial-value 0))

(defun %rt-linux-numa-from-sysfs ()
  (let ((nodes
          (loop for cpulist-path in (directory "/sys/devices/system/node/node*/cpulist")
                for node-id = (%rt-linux-node-id-from-path cpulist-path)
                for cpus = (%rt-parse-cpulist (%rt-file-string cpulist-path))
                when (and node-id cpus)
                  collect (list :node-id node-id
                                :cpus (sort cpus #'<)
                                :memory-bytes (%rt-linux-node-memory-bytes node-id)
                                :kind :dram))))
    (when nodes (%rt-sort-topology-nodes nodes))))

(defun %rt-linux-numa-from-numactl ()
  (let ((output (%rt-run-program-output "numactl" '("--hardware"))))
    (when output
      (let ((nodes nil))
        (dolist (line (%rt-split-string output #\Newline))
          (when (and (search "node " line) (search " cpus:" line))
            (let* ((tokens (remove "" (%rt-split-string (%rt-trim line) #\Space) :test #'string=))
                   (node-id (parse-integer (second tokens) :junk-allowed t))
                   (cpus (mapcan #'%rt-parse-cpu-token (cdddr tokens))))
              (when (and node-id cpus)
                (push (list :node-id node-id :cpus cpus :memory-bytes nil :kind :dram)
                      nodes)))))
        (when nodes (%rt-sort-topology-nodes nodes))))))

(defun %rt-default-numa-topology ()
  (list (list :node-id 0
              :cpus (%rt-default-cpu-list)
              :memory-bytes nil
              :kind :dram)))

(defun %rt-detect-numa-topology-uncached ()
  (or #+linux (or (%rt-linux-numa-from-sysfs)
                  (%rt-linux-numa-from-numactl))
      (%rt-default-numa-topology)))

(defun detect-numa-topology ()
  "Detect NUMA topology as a list of node property lists.

Each node contains :NODE-ID, :CPUS, :MEMORY-BYTES, and :KIND. Linux reads
/sys/devices/system/node/node*/cpulist and falls back to numactl --hardware.
macOS reports one DRAM node because Darwin exposes no NUMA topology. Unsupported
hosts return a single default node covering all detected CPUs. The detected
topology is cached and returned as a fresh tree so callers cannot mutate the
process cache."
  (copy-tree
   (or *rt-detected-numa-topology*
       (setf *rt-detected-numa-topology*
             (%rt-detect-numa-topology-uncached)))))

(defun %rt-linux-affinity-from-status ()
  (loop for line in (%rt-file-lines "/proc/self/status")
        when (search "Cpus_allowed_list:" line)
          do (let ((colon (position #\: line)))
               (return (and colon (%rt-parse-cpulist (subseq line (1+ colon))))))))

(defun get-cpu-affinity-mask ()
  "Return the current thread/process CPU affinity as a list of CPU indexes.

On SBCL/Linux this calls sched_getaffinity(2). If that is unavailable, Linux
parses /proc/self/status. macOS and unsupported hosts return NIL and issue a
warning because portable thread affinity is not exposed by the host runtime."
  #+(and sbcl linux)
  (let ((mask (make-array +rt-affinity-mask-bytes+
                          :element-type '(unsigned-byte 8)
                          :initial-element 0)))
    (or (ignore-errors
          (%rt-with-affinity-alien-mask
           mask
           #'%rt-get-affinity-with-alien-mask))
        (%rt-linux-affinity-from-status)))
  #-(and sbcl linux)
  (progn
    (warn "CPU affinity query is not supported on this host; returning NIL.")
    nil))

(defun set-cpu-affinity-mask (cpus)
  "Set the current process CPU affinity to CPUS and return the effective mask.

CPUS is a list of zero-based CPU indexes. SBCL/Linux uses sched_setaffinity(2)
without requiring project C code. macOS and unsupported hosts return NIL and
warn because Darwin thread_policy_set affinity tags do not expose a portable
CPU bitmask compatible with this runtime API."
  (check-type cpus list)
  #+(and sbcl linux)
  (let ((mask (%rt-cpus->affinity-vector cpus)))
    (or (ignore-errors
          (%rt-with-affinity-alien-mask
           mask
           #'%rt-set-affinity-with-alien-mask))
        (progn
          (warn "sched_setaffinity failed; CPU affinity was not changed.")
          nil)))
  #-(and sbcl linux)
  (progn
    (warn "CPU affinity changes are not supported on this host; returning NIL.")
    nil))

(defun %rt-linux-memory-total-bytes ()
  (loop for line in (%rt-file-lines "/proc/meminfo")
        when (search "MemTotal:" line)
          do (let ((kb (parse-integer (subseq line (length "MemTotal:")) :junk-allowed t)))
               (return (and kb (* kb 1024))))))

(defun %rt-linux-nvme-tier-info ()
  (loop for size-path in (directory "/sys/block/nvme*/size")
        for sectors = (%rt-parse-positive-integer (%rt-file-string size-path))
        when sectors
          collect (list :tier :nvme
                        :device (let* ((dirs (pathname-directory size-path))
                                       (name (car (last dirs))))
                                  (and name (string name)))
                        :bytes (* sectors 512)
                        :source :sysfs)))

(defun %rt-hbm-line-p (line)
  (search "hbm" line :test #'char-equal))

(defun %rt-linux-hbm-present-p ()
  (or (directory "/sys/devices/system/node/node*/memory_side_cache/index*")
      (some #'%rt-hbm-line-p
            (append (%rt-file-lines "/proc/meminfo") nil))))

(defun memory-tier-info ()
  "Return detected memory/storage tiers as property lists.

The result always includes a DRAM tier when no richer information is available.
Linux reports DRAM from /proc/meminfo or NUMA node meminfo, adds an HBM marker
when HMAT/memory-side-cache hints are visible in sysfs, and reports NVMe block
devices as storage-backed tiers. macOS reports unified DRAM using sysctl-derived
host information when possible."
  (let ((tiers nil))
    #+linux
    (progn
      (push (list :tier :dram
                  :bytes (or (%rt-linux-memory-total-bytes)
                             (%rt-topology-memory-bytes (detect-numa-topology)))
                  :nodes (detect-numa-topology)
                  :source :linux)
            tiers)
      (when (%rt-linux-hbm-present-p)
        (push (list :tier :hbm :bytes nil :source :linux-hmat) tiers))
      (setf tiers (nconc (%rt-linux-nvme-tier-info) tiers)))
    #+darwin
    (push (list :tier :dram
                :bytes (%rt-parse-positive-integer
                        (or (%rt-run-program-output "/usr/sbin/sysctl" '("-n" "hw.memsize"))
                            (%rt-run-program-output "sysctl" '("-n" "hw.memsize"))))
                :nodes (detect-numa-topology)
                :source :darwin)
          tiers)
    (or tiers
        (list (list :tier :dram
                    :bytes nil
                    :nodes (detect-numa-topology)
                    :source :fallback)))))

(defun rt-cpu-topology ()
  "Return runtime CPU and NUMA topology information as a property list."
  (list :cores (detect-cpu-cores)
        :numa-nodes (detect-numa-topology)
        :memory-tiers (memory-tier-info)))

(defun rt-thread-set-affinity (core)
  "Restrict execution to CORE and return the effective CPU mask, or NIL if unsupported."
  (set-cpu-affinity-mask (list core)))

(defun rt-thread-get-affinity ()
  "Return the current CPU affinity list, or NIL if unsupported."
  (get-cpu-affinity-mask))
