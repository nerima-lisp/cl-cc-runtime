;;;; tests/async-generators-tests.lisp — async iterators + async generators (src/async-generators.lisp).
;;;;
;;;; The async-iterator combinators operate over already-resolved futures
;;;; (rt-aiter-from-list produces resolved futures, and rt-await returns
;;;; immediately for a resolved future), so these run deterministically
;;;; without a live scheduler.
(in-package :cl-cc-runtime/test)

(describe "async iterators (async-generators.lisp)"
  (it "rt-aiter-from-list + rt-aiter-collect round-trips the items"
    (expect (cl-cc/runtime::rt-future-await
             (cl-cc/runtime::rt-aiter-collect
              (cl-cc/runtime::rt-aiter-from-list '(1 2 3))))
            :to-equal '(1 2 3)))

  (it "collect over an empty iterator yields nil"
    (expect (cl-cc/runtime::rt-future-await
             (cl-cc/runtime::rt-aiter-collect
              (cl-cc/runtime::rt-aiter-from-list '())))
            :to-be-null))

  (it "rt-aiter-next reports the item with done-p nil, then nil with done-p t at the end"
    (let ((it (cl-cc/runtime::rt-aiter-from-list '(:only))))
      (multiple-value-bind (item done)
          (cl-cc/runtime::rt-future-await (cl-cc/runtime::rt-aiter-next it))
        (expect item :to-be :only)
        (expect done :to-be-null))
      (multiple-value-bind (item done)
          (cl-cc/runtime::rt-future-await (cl-cc/runtime::rt-aiter-next it))
        (expect item :to-be-null)
        (expect done :to-be-truthy))))

  (it "rt-aiter-map transforms every item"
    (expect (cl-cc/runtime::rt-future-await
             (cl-cc/runtime::rt-aiter-collect
              (cl-cc/runtime::rt-aiter-map
               (cl-cc/runtime::rt-aiter-from-list '(1 2 3))
               (lambda (x) (* x 10)))))
            :to-equal '(10 20 30)))

  (it "rt-aiter-filter keeps only matching items"
    (expect (cl-cc/runtime::rt-future-await
             (cl-cc/runtime::rt-aiter-collect
              (cl-cc/runtime::rt-aiter-filter
               (cl-cc/runtime::rt-aiter-from-list '(1 2 3 4 5 6))
               #'evenp)))
            :to-equal '(2 4 6)))

  (it "rt-aiter-take limits to the first n items"
    (expect (cl-cc/runtime::rt-future-await
             (cl-cc/runtime::rt-aiter-collect
              (cl-cc/runtime::rt-aiter-take
               (cl-cc/runtime::rt-aiter-from-list '(1 2 3 4 5))
               2)))
            :to-equal '(1 2)))

  (it "rt-aiter-take of more than exists stops at the source's end"
    (expect (cl-cc/runtime::rt-future-await
             (cl-cc/runtime::rt-aiter-collect
              (cl-cc/runtime::rt-aiter-take
               (cl-cc/runtime::rt-aiter-from-list '(1 2))
               10)))
            :to-equal '(1 2)))

  (it "rt-async-for walks every item in order"
    (let ((acc nil))
      (cl-cc/runtime::rt-async-for (x (cl-cc/runtime::rt-aiter-from-list '(:a :b :c)))
        (push x acc))
      (expect (nreverse acc) :to-equal '(:a :b :c)))))

(describe "async generators (async-generators.lisp)"
  (it "a fresh generator is not done"
    (let ((g (cl-cc/runtime::rt-make-async-generator)))
      (expect (cl-cc/runtime::rt-async-generator-state-done-p g) :to-be-null)))

  (it "yield-then-next resolves immediately with the queued item"
    (let ((g (cl-cc/runtime::rt-make-async-generator)))
      (cl-cc/runtime::rt-async-yield g :a)
      (let ((f (cl-cc/runtime::rt-async-generator-next g)))
        (expect (cl-cc/runtime::rt-future-done-p f) :to-be-truthy)
        (multiple-value-bind (item done) (cl-cc/runtime::rt-future-await f)
          (expect item :to-be :a)
          (expect done :to-be-null)))))

  (it "next-then-yield registers a waiter that a later yield resolves"
    (let* ((g (cl-cc/runtime::rt-make-async-generator))
           (f (cl-cc/runtime::rt-async-generator-next g)))
      (expect (cl-cc/runtime::rt-future-done-p f) :to-be-null)
      (cl-cc/runtime::rt-async-yield g :b)
      (expect (cl-cc/runtime::rt-future-done-p f) :to-be-truthy)
      (multiple-value-bind (item done) (cl-cc/runtime::rt-future-await f)
        (expect item :to-be :b)
        (expect done :to-be-null))))

  (it "queued items are delivered in FIFO order"
    (let ((g (cl-cc/runtime::rt-make-async-generator)))
      (cl-cc/runtime::rt-async-yield g 1)
      (cl-cc/runtime::rt-async-yield g 2)
      (expect (cl-cc/runtime::rt-future-await (cl-cc/runtime::rt-async-generator-next g))
              :to-be 1)
      (expect (cl-cc/runtime::rt-future-await (cl-cc/runtime::rt-async-generator-next g))
              :to-be 2)))

  (it "close marks the generator done; next then reports done-p"
    (let ((g (cl-cc/runtime::rt-make-async-generator)))
      (expect (cl-cc/runtime::rt-async-generator-close g) :to-be-truthy)
      (multiple-value-bind (item done)
          (cl-cc/runtime::rt-future-await (cl-cc/runtime::rt-async-generator-next g))
        (expect item :to-be-null)
        (expect done :to-be-truthy))))

  (it "close resolves any pending waiter with done-p true"
    (let* ((g (cl-cc/runtime::rt-make-async-generator))
           (f (cl-cc/runtime::rt-async-generator-next g)))
      (expect (cl-cc/runtime::rt-future-done-p f) :to-be-null)
      (cl-cc/runtime::rt-async-generator-close g)
      (expect (cl-cc/runtime::rt-future-done-p f) :to-be-truthy)
      (multiple-value-bind (item done) (cl-cc/runtime::rt-future-await f)
        (expect item :to-be-null)
        (expect done :to-be-truthy))))

  (it "yield after close signals an error"
    (let ((g (cl-cc/runtime::rt-make-async-generator)))
      (cl-cc/runtime::rt-async-generator-close g)
      (expect (handler-case (progn (cl-cc/runtime::rt-async-yield g :x) nil)
                (error () t))
              :to-be-truthy)))

  (it "a failed generator raises the recorded condition on next"
    (let ((g (cl-cc/runtime::rt-make-async-generator)))
      (cl-cc/runtime::rt-async-generator-fail
       g (make-condition 'simple-error :format-control "boom"))
      (expect (cl-cc/runtime::rt-async-generator-state-done-p g) :to-be-truthy)
      (expect (handler-case (progn (cl-cc/runtime::rt-async-generator-next g) nil)
                (error () t))
              :to-be-truthy))))
