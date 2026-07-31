;;;; t/effects-test.lisp
;;;;
;;;; Tests for src/effects.lisp — the algebraic effect handler runtime built on
;;;; CL restarts.  These exercise the resume protocol, the dynamic handler-stack
;;;; lookup order (innermost wins, per-name before catch-all), and the derived
;;;; state/error/read/write effect helpers.
(in-package :cl-cc-runtime/test)

;;; ─── rt-perform / rt-resume round-trip ──────────────────────────────────────
(it-sequential
  "A handler that calls rt-resume makes rt-perform return the resumed value."
  (expect
    (cl-cc/runtime::rt-with-handler
      (:ping
        (lambda (e)
          (declare (ignore e))
          (cl-cc/runtime::rt-resume 42)))
      (cl-cc/runtime::rt-perform :ping))
    :to-be
    42))

(it-sequential
  "When a handler returns normally without resuming, its return value is the
result of rt-perform (funcall handler effect)."
  (expect
    (cl-cc/runtime::rt-with-handler
      (:ping
        (lambda (e)
          (declare (ignore e))
          :handled))
      (cl-cc/runtime::rt-perform :ping))
    :to-be
    :handled))

(it-sequential
  "The handler receives an rt-effect whose name and payload reflect the call."
  (cl-cc/runtime::rt-with-handler
    (:calc
      (lambda (e)
        (expect (cl-cc/runtime::rt-effect-name e) :to-be :calc)
        (expect (cl-cc/runtime::rt-effect-payload e) :to-equal '(2 3))
        (cl-cc/runtime::rt-resume (apply #'+ (cl-cc/runtime::rt-effect-payload e)))))
    (expect (cl-cc/runtime::rt-perform :calc 2 3) :to-equal 5)))

(it-sequential
  "rt-perform requires a keyword effect name (check-type)."
  (signals type-error (cl-cc/runtime::rt-perform "not-a-keyword")))

;;; ─── Unhandled effects ──────────────────────────────────────────────────────
(it-sequential
  "Performing an effect with no matching handler signals rt-effect-condition."
  (let ((cl-cc/runtime::*rt-handler-stack* nil))
    (signals cl-cc/runtime::rt-effect-condition (cl-cc/runtime::rt-perform :nobody-home))))

(it-sequential
  "rt-effect-condition exposes the offending effect via its reader."
  (let ((cl-cc/runtime::*rt-handler-stack* nil))
    (handler-case (cl-cc/runtime::rt-perform :orphan 1 2)
      (cl-cc/runtime::rt-effect-condition (c)
        (let ((eff (cl-cc/runtime::rt-effect-condition-effect c)))
          (expect (cl-cc/runtime::rt-effect-name eff) :to-be :orphan)
          (expect (cl-cc/runtime::rt-effect-payload eff) :to-equal '(1 2)))))))

;;; ─── Handler stack ordering ─────────────────────────────────────────────────
(it-sequential
  "With two handlers for the same effect, the innermost (most recently
installed) handler services the perform."
  (expect
    (cl-cc/runtime::rt-with-handler
      (:foo
        (lambda (e)
          (declare (ignore e))
          (cl-cc/runtime::rt-resume :outer)))
      (cl-cc/runtime::rt-with-handler
        (:foo
          (lambda (e)
            (declare (ignore e))
            (cl-cc/runtime::rt-resume :inner)))
        (cl-cc/runtime::rt-perform :foo)))
    :to-be
    :inner))

(it-sequential
  "An inner handler for an unrelated effect is skipped; the outer handler for
the performed effect services it."
  (expect
    (cl-cc/runtime::rt-with-handler
      (:foo
        (lambda (e)
          (declare (ignore e))
          (cl-cc/runtime::rt-resume :outer-foo)))
      (cl-cc/runtime::rt-with-handler
        (:bar
          (lambda (e)
            (declare (ignore e))
            (cl-cc/runtime::rt-resume :inner-bar)))
        (cl-cc/runtime::rt-perform :foo)))
    :to-be
    :outer-foo))

(it-sequential
  "rt-handle installs a catch-all (t) handler that services any effect name."
  (expect
    (cl-cc/runtime::rt-handle
      (lambda (e)
        (cl-cc/runtime::rt-resume
          (if (eq (cl-cc/runtime::rt-effect-name e) :ping) :pong
            :other)))
      (lambda ()
        (cl-cc/runtime::rt-perform :ping)))
    :to-be
    :pong))

(it-sequential "Within one frame a named entry is consulted; a later frame's catch-all is
used only when no nearer frame matches."
  ;; Outer catch-all, inner named for :a.  Perform :b should reach the catch-all.
  (expect (cl-cc/runtime::rt-handle
              (lambda (e) (declare (ignore e)) (cl-cc/runtime::rt-resume :caught-all))
              (lambda ()
                (cl-cc/runtime::rt-with-handler (:a (lambda (e) (declare (ignore e))
                                                      (cl-cc/runtime::rt-resume :named-a)))
                  (cl-cc/runtime::rt-perform :b)))) :to-be :caught-all))

(it-sequential
  "rt-current-handler returns NIL when no effect is being dispatched."
  (let ((cl-cc/runtime::*rt-current-effect* nil))
    (expect (cl-cc/runtime::rt-current-handler) :to-be-null)))

;;; ─── Derived effect helpers ─────────────────────────────────────────────────
(it-sequential
  "rt-effect-state routes :GET and :PUT through the :state effect."
  (cl-cc/runtime::rt-with-handler
    (:state
      (lambda (e)
        (cl-cc/runtime::rt-resume
          (ecase (first (cl-cc/runtime::rt-effect-payload e))
            (:get 99)
            (:put (second (cl-cc/runtime::rt-effect-payload e)))))))
    (expect (cl-cc/runtime::rt-effect-state :get) :to-equal 99)
    (expect (cl-cc/runtime::rt-effect-state :put :new) :to-be :new)))

(it-sequential
  "rt-effect-state uses ECASE and rejects operations other than :GET/:PUT."
  (signals type-error (cl-cc/runtime::rt-effect-state :delete)))

(it-sequential
  "rt-effect-error/read/write perform :error/:read/:write and thread the
resumed value back."
  (cl-cc/runtime::rt-with-handler
    (:error
      (lambda (e)
        (cl-cc/runtime::rt-resume
          (list :err (first (cl-cc/runtime::rt-effect-payload e))))))
    (expect (cl-cc/runtime::rt-effect-error :boom) :to-equal '(:err :boom)))
  (cl-cc/runtime::rt-with-handler
    (:read
      (lambda (e)
        (cl-cc/runtime::rt-resume
          (format nil "answer-to-~A" (first (cl-cc/runtime::rt-effect-payload e))))))
    (expect (cl-cc/runtime::rt-effect-read "name?") :to-equal "answer-to-name?"))
  (let ((sink nil))
    (cl-cc/runtime::rt-with-handler
      (:write
        (lambda (e)
          (setf sink (first (cl-cc/runtime::rt-effect-payload e)))
          (cl-cc/runtime::rt-resume :ok)))
      (expect (cl-cc/runtime::rt-effect-write 123) :to-be :ok))
    (expect sink :to-equal 123)))

;;; ─── Sequential performs share one handler frame ────────────────────────────
(it-sequential
  "A single handler frame services repeated performs, each resuming
independently."
  (let ((seen nil))
    (cl-cc/runtime::rt-with-handler
      (:acc
        (lambda (e)
          (push (first (cl-cc/runtime::rt-effect-payload e)) seen)
          (cl-cc/runtime::rt-resume (first (cl-cc/runtime::rt-effect-payload e)))))
      (expect (cl-cc/runtime::rt-perform :acc 1) :to-equal 1)
      (expect (cl-cc/runtime::rt-perform :acc 2) :to-equal 2)
      (expect (cl-cc/runtime::rt-perform :acc 3) :to-equal 3))
    (expect (nreverse seen) :to-equal '(1 2 3))))
