;;;; gc-stackmaps.lisp — Register/lookup and scan compiler-emitted stackmaps
;;;; for precise stack-frame root scanning, split out of gc-roots-objects.lisp
(in-package :cl-cc/runtime)

(defun %rt-gc-thread-words (thread-state)
  "Return a list of conservative stack words described by THREAD-STATE."
  (cond
    ((null thread-state) nil)
    ((vm-frame-p thread-state)
     (loop for value across (vm-frame-registers thread-state) collect value))
    ((vectorp thread-state)
     (loop for value across thread-state collect value))
    ((and (consp thread-state)
          (or (getf thread-state :stack) (getf thread-state :frames)))
     (append (copy-list (getf thread-state :stack))
             (loop for frame in (getf thread-state :frames)
                   append (%rt-gc-thread-words frame))))
    ((listp thread-state) thread-state)
    (t nil)))

(defun rt-gc-register-stackmap (frame-id slots &key (source :compiler-stub))
  "Register precise stack map SLOTS for FRAME-ID.

SLOTS has the compiler-facing shape ((FRAME-OFFSET . :OBJECT) ...).  Non-object
slot kinds are accepted but ignored by root scanning."
  (let ((stackmap (make-rt-stackmap :frame-id frame-id
                                    :slots (copy-list slots)
                                    :source source)))
    (setf (gethash frame-id *rt-gc-stackmap-table*) stackmap)
    stackmap))

(defun rt-gc-stackmap-for-frame (frame)
  "Return stack-map metadata for FRAME, if any."
  (let ((frame-id (cond
                    ((and (consp frame) (getf frame :stackmap-id)) (getf frame :stackmap-id))
                    ((and (consp frame) (getf frame :frame-id)) (getf frame :frame-id))
                    ((vm-frame-p frame) (vm-frame-closure frame))
                    (t nil))))
    (and frame-id (gethash frame-id *rt-gc-stackmap-table*))))

(defun rt-gc-generate-stackmap (frame-id live-object-offsets)
  "FR-541: Generate and register a precise GC stack map for FRAME-ID.
LIVE-OBJECT-OFFSETS is a list of frame offsets containing live object pointers.
The stack map is registered into *rt-gc-stackmap-table* for use by the
precise garbage collector. Source tag distinguishes compiler-generated
maps from manually registered ones."
  (rt-gc-register-stackmap
   frame-id
   (mapcar (lambda (offset) (cons offset :object)) live-object-offsets)
   :source :compiler))

(defun %rt-gc-frame-slot-value (frame offset)
  "Read OFFSET from FRAME for precise stack-map scanning."
  (cond
    ((vm-frame-p frame) (aref (vm-frame-registers frame) offset))
    ((vectorp frame) (aref frame offset))
    ((and (consp frame) (getf frame :slots)) (cdr (assoc offset (getf frame :slots))))
    ((and (consp frame) (getf frame :registers)) (cdr (assoc offset (getf frame :registers))))
    ((listp frame) (nth offset frame))
    (t nil)))

(defun (setf %rt-gc-frame-slot-value) (value frame offset)
  "Write VALUE to OFFSET in FRAME when FRAME supports precise updates."
  (cond
    ((vm-frame-p frame) (setf (aref (vm-frame-registers frame) offset) value))
    ((vectorp frame) (setf (aref frame offset) value))
    ((and (consp frame) (getf frame :slots))
     (let ((cell (assoc offset (getf frame :slots))))
       (if cell (setf (cdr cell) value) (push (cons offset value) (getf frame :slots)))))
    ((and (consp frame) (getf frame :registers))
     (let ((cell (assoc offset (getf frame :registers))))
       (if cell (setf (cdr cell) value) (push (cons offset value) (getf frame :registers))))))
  value)

(defun rt-gc-scan-stackmap-frame (heap frame)
  "Return heap object addresses in FRAME described by its precise stack map."
  (let ((stackmap (rt-gc-stackmap-for-frame frame)))
    (remove-duplicates
     (loop for (offset . kind) in (and stackmap (rt-stackmap-slots stackmap))
           when (eq kind :object)
             append (let ((addr (%rt-gc-pointer-address
                                 heap (%rt-gc-frame-slot-value frame offset))))
                      (and addr (list addr))))
     :test #'eql)))

(defun rt-gc-scan-stackmaps (heap)
  "Return precise stack-map roots for all registered thread frames."
  (remove-duplicates
   (loop for thread-state in *gc-threads*
         for frames = (and (consp thread-state) (getf thread-state :frames))
         append (loop for frame in frames append (rt-gc-scan-stackmap-frame heap frame)))
   :test #'eql))

(defun rt-gc-update-stackmap-frame (heap frame address-mapper)
  "Update object slots in FRAME using ADDRESS-MAPPER for moving GC integration." 
  (declare (ignore heap))
  (let ((stackmap (rt-gc-stackmap-for-frame frame)))
    (dolist (slot (and stackmap (rt-stackmap-slots stackmap)) frame)
      (destructuring-bind (offset . kind) slot
        (when (eq kind :object)
          (let* ((old (%rt-gc-frame-slot-value frame offset))
                 (new (funcall address-mapper old)))
            (when new
              (setf (%rt-gc-frame-slot-value frame offset) new))))))))
