;;;; tests/effects-tests.lisp
;;;;
;;;; Tests for src/effects.lisp — the algebraic effect handler runtime built on
;;;; CL restarts.  These exercise the resume protocol, the dynamic handler-stack
;;;; lookup order (innermost wins, per-name before catch-all), and the derived
;;;; state/error/read/write effect helpers.

(in-package :cl-cc-runtime/test)

(in-suite cl-cc-unit-suite)

;;; ─── rt-perform / rt-resume round-trip ──────────────────────────────────────

(deftest effects-perform-resume-returns-handler-value
  "A handler that calls rt-resume makes rt-perform return the resumed value."
  (assert-eql 42
              (cl-cc/runtime::rt-with-handler (:ping (lambda (e)
                                                       (declare (ignore e))
                                                       (cl-cc/runtime::rt-resume 42)))
                (cl-cc/runtime::rt-perform :ping))))

(deftest effects-perform-handler-return-without-resume
  "When a handler returns normally without resuming, its return value is the
result of rt-perform (funcall handler effect)."
  (assert-eq :handled
             (cl-cc/runtime::rt-with-handler (:ping (lambda (e)
                                                      (declare (ignore e))
                                                      :handled))
               (cl-cc/runtime::rt-perform :ping))))

(deftest effects-perform-receives-effect-with-name-and-payload
  "The handler receives an rt-effect whose name and payload reflect the call."
  (cl-cc/runtime::rt-with-handler
      (:calc (lambda (e)
               (assert-eq :calc (cl-cc/runtime::rt-effect-name e))
               (assert-equal '(2 3) (cl-cc/runtime::rt-effect-payload e))
               (cl-cc/runtime::rt-resume (apply #'+ (cl-cc/runtime::rt-effect-payload e)))))
    (assert-= 5 (cl-cc/runtime::rt-perform :calc 2 3))))

(deftest effects-perform-non-keyword-name-signals
  "rt-perform requires a keyword effect name (check-type)."
  (assert-signals type-error (cl-cc/runtime::rt-perform "not-a-keyword")))

;;; ─── Unhandled effects ──────────────────────────────────────────────────────

(deftest effects-unhandled-signals-effect-condition
  "Performing an effect with no matching handler signals rt-effect-condition."
  (let ((cl-cc/runtime::*rt-handler-stack* nil))
    (assert-signals cl-cc/runtime::rt-effect-condition
      (cl-cc/runtime::rt-perform :nobody-home))))

(deftest effects-unhandled-condition-carries-effect
  "rt-effect-condition exposes the offending effect via its reader."
  (let ((cl-cc/runtime::*rt-handler-stack* nil))
    (handler-case (cl-cc/runtime::rt-perform :orphan 1 2)
      (cl-cc/runtime::rt-effect-condition (c)
        (let ((eff (cl-cc/runtime::rt-effect-condition-effect c)))
          (assert-eq :orphan (cl-cc/runtime::rt-effect-name eff))
          (assert-equal '(1 2) (cl-cc/runtime::rt-effect-payload eff)))))))

;;; ─── Handler stack ordering ─────────────────────────────────────────────────

(deftest effects-innermost-handler-wins
  "With two handlers for the same effect, the innermost (most recently
installed) handler services the perform."
  (assert-eq :inner
             (cl-cc/runtime::rt-with-handler (:foo (lambda (e) (declare (ignore e))
                                                     (cl-cc/runtime::rt-resume :outer)))
               (cl-cc/runtime::rt-with-handler (:foo (lambda (e) (declare (ignore e))
                                                       (cl-cc/runtime::rt-resume :inner)))
                 (cl-cc/runtime::rt-perform :foo)))))

(deftest effects-falls-through-to-outer-handler
  "An inner handler for an unrelated effect is skipped; the outer handler for
the performed effect services it."
  (assert-eq :outer-foo
             (cl-cc/runtime::rt-with-handler (:foo (lambda (e) (declare (ignore e))
                                                     (cl-cc/runtime::rt-resume :outer-foo)))
               (cl-cc/runtime::rt-with-handler (:bar (lambda (e) (declare (ignore e))
                                                       (cl-cc/runtime::rt-resume :inner-bar)))
                 (cl-cc/runtime::rt-perform :foo)))))

(deftest effects-catch-all-handler-via-rt-handle
  "rt-handle installs a catch-all (t) handler that services any effect name."
  (assert-eq :pong
             (cl-cc/runtime::rt-handle
              (lambda (e) (cl-cc/runtime::rt-resume
                           (if (eq (cl-cc/runtime::rt-effect-name e) :ping) :pong :other)))
              (lambda () (cl-cc/runtime::rt-perform :ping)))))

(deftest effects-named-handler-shadows-catch-all-in-same-frame
  "Within one frame a named entry is consulted; a later frame's catch-all is
used only when no nearer frame matches."
  ;; Outer catch-all, inner named for :a.  Perform :b should reach the catch-all.
  (assert-eq :caught-all
             (cl-cc/runtime::rt-handle
              (lambda (e) (declare (ignore e)) (cl-cc/runtime::rt-resume :caught-all))
              (lambda ()
                (cl-cc/runtime::rt-with-handler (:a (lambda (e) (declare (ignore e))
                                                      (cl-cc/runtime::rt-resume :named-a)))
                  (cl-cc/runtime::rt-perform :b))))))

(deftest effects-current-handler-nil-without-effect
  "rt-current-handler returns NIL when no effect is being dispatched."
  (let ((cl-cc/runtime::*rt-current-effect* nil))
    (assert-null (cl-cc/runtime::rt-current-handler))))

;;; ─── Derived effect helpers ─────────────────────────────────────────────────

(deftest effects-state-get-and-put
  "rt-effect-state routes :GET and :PUT through the :state effect."
  (cl-cc/runtime::rt-with-handler
      (:state (lambda (e)
                (cl-cc/runtime::rt-resume
                 (ecase (first (cl-cc/runtime::rt-effect-payload e))
                   (:get 99)
                   (:put (second (cl-cc/runtime::rt-effect-payload e)))))))
    (assert-= 99 (cl-cc/runtime::rt-effect-state :get))
    (assert-eq :new (cl-cc/runtime::rt-effect-state :put :new))))

(deftest effects-state-rejects-unknown-operation
  "rt-effect-state uses ECASE and rejects operations other than :GET/:PUT."
  (assert-signals type-error (cl-cc/runtime::rt-effect-state :delete)))

(deftest effects-error-read-write-helpers
  "rt-effect-error/read/write perform :error/:read/:write and thread the
resumed value back."
  (cl-cc/runtime::rt-with-handler
      (:error (lambda (e) (cl-cc/runtime::rt-resume
                           (list :err (first (cl-cc/runtime::rt-effect-payload e))))))
    (assert-equal '(:err :boom) (cl-cc/runtime::rt-effect-error :boom)))
  (cl-cc/runtime::rt-with-handler
      (:read (lambda (e) (cl-cc/runtime::rt-resume
                          (format nil "answer-to-~A" (first (cl-cc/runtime::rt-effect-payload e))))))
    (assert-string= "answer-to-name?" (cl-cc/runtime::rt-effect-read "name?")))
  (let ((sink nil))
    (cl-cc/runtime::rt-with-handler
        (:write (lambda (e) (setf sink (first (cl-cc/runtime::rt-effect-payload e)))
                  (cl-cc/runtime::rt-resume :ok)))
      (assert-eq :ok (cl-cc/runtime::rt-effect-write 123)))
    (assert-= 123 sink)))

;;; ─── Sequential performs share one handler frame ────────────────────────────

(deftest effects-multiple-performs-same-frame
  "A single handler frame services repeated performs, each resuming
independently."
  (let ((seen nil))
    (cl-cc/runtime::rt-with-handler
        (:acc (lambda (e) (push (first (cl-cc/runtime::rt-effect-payload e)) seen)
                (cl-cc/runtime::rt-resume (first (cl-cc/runtime::rt-effect-payload e)))))
      (assert-= 1 (cl-cc/runtime::rt-perform :acc 1))
      (assert-= 2 (cl-cc/runtime::rt-perform :acc 2))
      (assert-= 3 (cl-cc/runtime::rt-perform :acc 3)))
    (assert-equal '(1 2 3) (nreverse seen))))
