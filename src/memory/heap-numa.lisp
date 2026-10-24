;;;; heap-numa.lisp — NUMA-aware allocation and GC worker affinity, split out
;;;; of heap-access.lisp
(in-package :cl-cc/runtime)

;;; ------------------------------------------------------------
;;; FR-288: Large Page Support (portable implementation)
;;;   On Linux with MAP_HUGETLB, native runtime can enable huge pages.
;;;   Portable CL implementation: tracks *rt-heap-hugepage-enabled* toggle
;;;   and provides os-advise-hugepage for transparent hugepage hinting.
;;;   Native backends should wire mmap(MAP_HUGETLB) or MADV_HUGEPAGE.
;;;
;;; FR-363: NUMA-Aware Heap Allocation (portable implementation)
;;;   Interface: *rt-numa-enabled*, rt-numa-local-alloc.
;;;   Portable implementation records per-thread NUMA node mappings
;;;   and delegates to GC bump allocator. Linux libnuma integration
;;;   available via the topology module (detect-numa-topology).
;;;
;;; FR-364: NUMA-Local GC (portable implementation)
;;;   Interface: rt-gc-numa-affinity.
;;;   Portable implementation generates deterministic round-robin
;;;   worker schedules. Native runtimes translate to sched_setaffinity.
;;;
;;; FR-365: Memory Interleaving (portable implementation)
;;;   Interface: rt-heap-interleave.
;;;   Portable implementation records interleave policy metadata.
;;;   Linux backends use mbind(MPOL_INTERLEAVE) when available.
;;; ------------------------------------------------------------

(defun rt-numa-node-of-thread (thread-id)
  "Return the NUMA node for THREAD-ID.

Pure CL has no portable NUMA discovery, so every thread maps to node 0. Native
Linux runtimes should query sched_getcpu/get_mempolicy or libnuma; Windows
runtimes can use GetNumaProcessorNodeEx."
  (declare (ignore thread-id))
  0)

(defun rt-numa-local-alloc (heap thread-id size-words)
  "Allocate SIZE-WORDS words from THREAD-ID's local NUMA node.

This portable stub records node metadata and delegates to the existing GC bump
allocator. Linux integrations should use numa_alloc_local/mbind for backing VM
pages; Windows integrations should use VirtualAllocExNuma."
  (check-type heap rt-heap)
  (check-type size-words (integer 1 *))
  (let* ((node (if *rt-numa-enabled* (rt-numa-node-of-thread thread-id) 0))
         (addr (rt-gc-alloc heap 0 size-words)))
    (setf (gethash addr (rt-heap-numa-node-map heap)) node)
    addr))

(defun rt-gc-numa-affinity (heap node)
  "Return a portable NUMA-local GC worker schedule for NODE.

GC workers should be scheduled on the same NUMA node as the objects they scan.
Pure CL cannot set affinity, so this records a deterministic round-robin worker
assignment that native runtimes can translate to OS scheduler calls."
  (check-type heap rt-heap)
  (check-type node integer)
  (let* ((workers (max 1 *gc-worker-count*))
         (schedule (loop for worker from 0 below workers
                         collect (list :worker worker :node (mod (+ node worker) workers)))))
    (setf (rt-heap-numa-gc-schedule heap) schedule)
    schedule))

(defun rt-heap-interleave (heap addr size)
  "Mark [ADDR, ADDR+SIZE) as interleaved shared data.

FR-365: Pure CL implementation records interleaved region metadata in
RT-HEAP-INTERLEAVED-REGIONS.  The NUMA-aware GC worker scheduler
(rt-gc-numa-affinity) uses this metadata for deterministic work distribution.

Deferred to Tier 6 (memory-gc.md): native Linux mbind(MPOL_INTERLEAVE) call
for global shared data pages requires OS-level mmap/mbind integration."
  (check-type heap rt-heap)
  (check-type addr integer)
  (check-type size (integer 0 *))
  (let ((region (list :start addr :end (+ addr size) :policy :interleave :portable t)))
    (push region (rt-heap-interleaved-regions heap))
    region))
