;;;; t/profiling/continuous-profile-migration-test.lisp
(in-package :cl-cc/runtime/profiling/test)

(defun make-profile-test-session (name &key (max-samples 128))
  (cl-cc/runtime/profiling:make-rt-continuous-profile-session :name
                                                              name
                                                              :running-p
                                                              t
                                                              :max-samples
                                                              max-samples))

(defun profile-test-sample-for-thread (session thread-id)
  (find thread-id
        (coerce
         (cl-cc/runtime/profiling:rt-continuous-profile-session-sample-log
          session)
         'list)
        :key
        #'cl-cc/runtime/profiling:rt-profile-sample-thread-id
        :test
        #'equal))

(defun record-profile-frame-at-address (session address thread-id)
  (cl-cc/runtime/profiling:rt-record-profile-sample
   (list
    (cl-cc/runtime/profiling:make-rt-profile-frame :function
                                                   "mapped-frame"
                                                   :address
                                                   address))
   :thread-id
   thread-id
   :session
   session)
  (cl-cc/runtime/profiling:rt-profile-frame-perf-symbol
   (first
    (cl-cc/runtime/profiling:rt-profile-sample-stack
     (profile-test-sample-for-thread session thread-id)))))

(defun call-with-profile-test-perf-map (function)
  (let ((path
         (merge-pathnames
          (format nil
                  "cl-cc-profile-map-~D-~D.map"
                  (get-universal-time)
                  (random 1000000))
          (uiop:temporary-directory)))
        (session nil))
    (unwind-protect
        (progn
          (with-open-file
              (out path
                   :direction
                   :output
                   :if-exists
                   :error
                   :if-does-not-exist
                   :create)
            (write-line "64 64 entry-A" out)
            (write-line "12C 64 entry-B" out)
            (write-line "3E8 3E8 perf-symbol-name" out))
          (setf session (cl-cc/runtime/profiling:rt-start-continuous-profile
                         :name
                         "perf-map-test"
                         :sample-rate-hz
                         1
                         :max-samples
                         128
                         :output
                         nil
                         :perf-map-file
                         path))
          (funcall function session))
      (when session
        (cl-cc/runtime/profiling:rt-stop-continuous-profile session))
      (when (probe-file path)
        (delete-file path)))))

(it-sequential "fr-701-continuous-profiling-records-and-exports-otel"
               (let ((session
                      (cl-cc/runtime/profiling:rt-start-continuous-profile :name
                                                                           "fr701"
                                                                           :output
                                                                           nil
                                                                           :attributes
                                                                           '(("service.name"
                                                                              .
                                                                              "cl-cc-test")))))
                 (cl-cc/runtime/profiling:rt-record-profile-sample
                  '("main" "worker")
                  :count
                  3
                  :session
                  session)
                 (expect
                  (gethash "main;worker"
                           (cl-cc/runtime/profiling:rt-continuous-profile-session-samples
                            session))
                  :to-equal
                  3)
                 (cl-cc/runtime/profiling:rt-stop-continuous-profile session)
                 (let ((span
                        (cl-cc/runtime/profiling:rt-continuous-profile->otel-span
                         session)))
                   (expect
                    (search "fr701"
                            (cl-cc/runtime/observability:rt-otel-span-to-json
                             span))
                    :to-be-truthy))))

(it-sequential "continuous-profile-resolve-perf-symbol-hit"
               (call-with-profile-test-perf-map
                (lambda (session)
                  (expect
                   (record-profile-frame-at-address session
                                                    100
                                                    "resolve-hit-start")
                   :to-equal
                   "entry-A")
                  (expect
                   (record-profile-frame-at-address session
                                                    150
                                                    "resolve-hit-interior")
                   :to-equal
                   "entry-A")
                  (expect
                   (record-profile-frame-at-address session
                                                    350
                                                    "resolve-hit-second")
                   :to-equal
                   "entry-B"))))

(it-sequential "continuous-profile-resolve-perf-symbol-miss"
               (call-with-profile-test-perf-map
                (lambda (session)
                  (expect
                   (record-profile-frame-at-address session
                                                    50
                                                    "resolve-miss-before")
                   :to-equal
                   nil)
                  (expect
                   (record-profile-frame-at-address session
                                                    200
                                                    "resolve-miss-end")
                   :to-equal
                   nil)
                  (expect
                   (record-profile-frame-at-address session
                                                    999
                                                    "resolve-miss-past")
                   :to-equal
                   nil)
                  (expect
                   (record-profile-frame-at-address session
                                                    nil
                                                    "resolve-miss-nil")
                   :to-equal
                   nil))))

(it-sequential "continuous-profile-collapsed-stack-from-frames"
               (let ((session (make-profile-test-session "collapsed-frames")))
                 (cl-cc/runtime/profiling:rt-record-profile-sample
                  (list
                   (cl-cc/runtime/profiling:make-rt-profile-frame :function
                                                                  "top")
                   (cl-cc/runtime/profiling:make-rt-profile-frame :function
                                                                  "middle")
                   (cl-cc/runtime/profiling:make-rt-profile-frame :function
                                                                  "bottom"))
                  :thread-id
                  "collapsed-frames"
                  :session
                  session)
                 (expect
                  (gethash "top;middle;bottom"
                           (cl-cc/runtime/profiling:rt-continuous-profile-session-samples
                            session))
                  :to-equal
                  1)))

(it-sequential "continuous-profile-collapsed-stack-from-strings"
               (let ((session (make-profile-test-session "collapsed-strings")))
                 (cl-cc/runtime/profiling:rt-record-profile-sample
                  '("alpha" "beta" "gamma")
                  :thread-id
                  "collapsed-strings"
                  :session
                  session)
                 (expect
                  (gethash "alpha;beta;gamma"
                           (cl-cc/runtime/profiling:rt-continuous-profile-session-samples
                            session))
                  :to-equal
                  1)))

(it-sequential "continuous-profile-collapsed-stack-single-frame"
               (let ((session (make-profile-test-session "collapsed-single")))
                 (cl-cc/runtime/profiling:rt-record-profile-sample
                  (list
                   (cl-cc/runtime/profiling:make-rt-profile-frame :function
                                                                  "only"))
                  :thread-id
                  "collapsed-single"
                  :session
                  session)
                 (expect
                  (gethash "only"
                           (cl-cc/runtime/profiling:rt-continuous-profile-session-samples
                            session))
                  :to-equal
                  1)))

(it-sequential "continuous-profile-normalize-frame-string"
               (let* ((session (make-profile-test-session "normalize-string")))
                 (cl-cc/runtime/profiling:rt-record-profile-sample "my-fn"
                                                                   :thread-id
                                                                   "normalize-string"
                                                                   :session
                                                                   session)
                 (let ((frame
                        (first
                         (cl-cc/runtime/profiling:rt-profile-sample-stack
                          (profile-test-sample-for-thread session
                                                          "normalize-string")))))
                   (expect
                    (typep frame 'cl-cc/runtime/profiling:rt-profile-frame)
                    :to-be-truthy)
                   (expect
                    (cl-cc/runtime/profiling:rt-profile-frame-function frame)
                    :to-equal
                    "my-fn"))))

(it-sequential "continuous-profile-normalize-frame-passthrough"
               (let* ((session
                       (make-profile-test-session "normalize-passthrough")))
                 (cl-cc/runtime/profiling:rt-record-profile-sample
                  (list
                   (cl-cc/runtime/profiling:make-rt-profile-frame :function
                                                                  "existing"))
                  :thread-id
                  "normalize-passthrough"
                  :session
                  session)
                 (let ((frame
                        (first
                         (cl-cc/runtime/profiling:rt-profile-sample-stack
                          (profile-test-sample-for-thread session
                                                          "normalize-passthrough")))))
                   (expect
                    (cl-cc/runtime/profiling:rt-profile-frame-function frame)
                    :to-equal
                    "existing"))))

(it-sequential "continuous-profile-normalize-frame-perf-map-enrichment"
               (call-with-profile-test-perf-map
                (lambda (session)
                  (cl-cc/runtime/profiling:rt-record-profile-sample
                   (list
                    (cl-cc/runtime/profiling:make-rt-profile-frame :function
                                                                   "fn"
                                                                   :address
                                                                   1500))
                   :thread-id
                   "normalize-perf-map"
                   :session
                   session)
                  (let ((frame
                         (first
                          (cl-cc/runtime/profiling:rt-profile-sample-stack
                           (profile-test-sample-for-thread session
                                                           "normalize-perf-map")))))
                    (expect
                     (cl-cc/runtime/profiling:rt-profile-frame-function frame)
                     :to-equal
                     "fn")
                    (expect
                     (cl-cc/runtime/profiling:rt-profile-frame-perf-symbol
                      frame)
                     :to-equal
                     "perf-symbol-name")))))

(it-sequential "continuous-profile-trim-samples-under-limit"
               (let ((session
                      (make-profile-test-session "trim-under" :max-samples 10)))
                 (cl-cc/runtime/profiling:rt-record-profile-sample "a"
                                                                   :thread-id
                                                                   "trim-a"
                                                                   :session
                                                                   session)
                 (cl-cc/runtime/profiling:rt-record-profile-sample "b"
                                                                   :thread-id
                                                                   "trim-b"
                                                                   :session
                                                                   session)
                 (expect
                  (length
                   (cl-cc/runtime/profiling:rt-continuous-profile-session-sample-log
                    session))
                  :to-equal
                  2)))

(it-sequential "continuous-profile-trim-samples-at-limit"
               (let ((session
                      (make-profile-test-session "trim-at" :max-samples 3)))
                 (dolist (name '("a" "b" "c" "d" "e"))
                   (cl-cc/runtime/profiling:rt-record-profile-sample name
                                                                     :thread-id
                                                                     name
                                                                     :session
                                                                     session))
                 (let ((log
                        (cl-cc/runtime/profiling:rt-continuous-profile-session-sample-log
                         session)))
                   (expect (length log) :to-equal 3)
                   (expect
                    (cl-cc/runtime/profiling:rt-profile-frame-function
                     (first
                      (cl-cc/runtime/profiling:rt-profile-sample-stack
                       (aref log 0))))
                    :to-equal
                    "c")
                   (expect
                    (cl-cc/runtime/profiling:rt-profile-frame-function
                     (first
                      (cl-cc/runtime/profiling:rt-profile-sample-stack
                       (aref log 1))))
                    :to-equal
                    "d")
                   (expect
                    (cl-cc/runtime/profiling:rt-profile-frame-function
                     (first
                      (cl-cc/runtime/profiling:rt-profile-sample-stack
                       (aref log 2))))
                    :to-equal
                    "e"))))

(it-sequential "continuous-profile-export-nil-output-returns-string"
               (let ((session
                      (cl-cc/runtime/profiling:make-rt-continuous-profile-session
                       :name
                       "export-nil"
                       :output
                       nil
                       :format
                       :otel-json
                       :started-at-nanos
                       0
                       :stopped-at-nanos
                       1000000)))
                 (let ((result
                        (cl-cc/runtime/profiling:rt-export-continuous-profile
                         session
                         :output
                         nil)))
                   (expect (stringp result) :to-be-truthy)
                   (expect (search "resourceProfiles" result) :to-be-truthy))))

(it-sequential "continuous-profile-export-pprof-format"
               (let ((session
                      (cl-cc/runtime/profiling:make-rt-continuous-profile-session
                       :name
                       "export-pprof"
                       :output
                       nil
                       :format
                       :pprof-json
                       :started-at-nanos
                       0
                       :stopped-at-nanos
                       1000000)))
                 (let ((result
                        (cl-cc/runtime/profiling:rt-export-continuous-profile
                         session
                         :format
                         :pprof-json
                         :output
                         nil)))
                   (expect (stringp result) :to-be-truthy)
                   (expect (search "sampleType" result) :to-be-truthy)
                   (expect (search "periodType" result) :to-be-truthy))))

(it-sequential "continuous-profile-export-stdout-returns-payload"
               (let ((session
                      (cl-cc/runtime/profiling:make-rt-continuous-profile-session
                       :name
                       "export-stdout"
                       :output
                       :stdout
                       :format
                       :otel-json
                       :started-at-nanos
                       0
                       :stopped-at-nanos
                       1000000)))
                 (let ((captured
                        (with-output-to-string (*standard-output*)
                          (let ((result
                                 (cl-cc/runtime/profiling:rt-export-continuous-profile
                                  session
                                  :output
                                  :stdout)))
                            (expect (stringp result) :to-be-truthy)
                            (expect (search "cl-cc/runtime" result)
                                    :to-be-truthy)))))
                   (expect (search "cl-cc/runtime" captured) :to-be-truthy))))

(it-sequential "fr-701-continuous-profiler-background-sampler-and-json-exports"
               (let ((session
                      (cl-cc/runtime/profiling:rt-start-continuous-profile :name
                                                                           "fr701-sampler"
                                                                           :sample-rate-hz
                                                                           100
                                                                           :output
                                                                           nil
                                                                           :trace-id
                                                                           "0123456789abcdef0123456789abcdef"
                                                                           :span-id
                                                                           "0123456789abcdef")))
                 (expect
                  (cl-cc/runtime/profiling:rt-wait-for-continuous-profile-sample
                   session
                   :timeout
                   1)
                  :to-be-truthy)
                 (cl-cc/runtime/profiling:rt-record-profile-sample
                  (list
                   (cl-cc/runtime/profiling:make-rt-profile-frame :function
                                                                  "manual-worker"
                                                                  :source-file
                                                                  "continuous-profile-tests.lisp"
                                                                  :source-line
                                                                  42))
                  :thread-id
                  "test-thread"
                  :session
                  session)
                 (cl-cc/runtime/profiling:rt-stop-continuous-profile session)
                 (expect
                  (>
                   (length
                    (cl-cc/runtime/profiling:rt-continuous-profile-session-sample-log
                     session))
                   0)
                  :to-be-truthy)
                 (let ((otel
                        (cl-cc/runtime/profiling:rt-continuous-profile-to-otel-json
                         session))
                       (pprof
                        (cl-cc/runtime/profiling:rt-continuous-profile-to-pprof-json
                         session)))
                   (expect
                    (search "\"trace_id\":\"0123456789abcdef0123456789abcdef\""
                            otel)
                    :to-be-truthy)
                   (expect (search "\"stack\"" otel) :to-be-truthy)
                   (expect (search "\"sampleType\"" pprof) :to-be-truthy)
                   (expect (search "manual-worker" pprof) :to-be-truthy))))
