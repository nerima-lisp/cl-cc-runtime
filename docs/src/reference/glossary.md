# Glossary

Key types and functions are representative public symbols, not a complete API
list. `None` means no representative is listed for that entry.

## memory

- Definition: The managed heap, allocation, garbage collection, and runtime roots that keep live objects reachable.
- Package: `cl-cc/runtime/memory`, `cl-cc/runtime/memory/infra`
- Key types: `rt-heap`
- Key functions: `rt-gc-alloc`, `rt-gc-minor-collect`, `rt-gc-major-collect`
- Other contexts: `values` owns weak-hash APIs and entry representation. An ephemeron is a key-value pair whose value is considered live only while its key is live; `memory` creates and processes them during garbage collection.

## values

- Definition: Represents runtime Lisp values and provides their type, list, array, string, numeric, symbol, and package operations.
- Package: `cl-cc/runtime/values`
- Key types: None.
- Key functions: `rt-tag-fixnum`, `rt-cons`, `rt-values-count`, `rt-type-of`
- Other contexts: `memory` owns GC processing and ephemeron creation for weak tables; `values` owns their API and entries. `dynamic-binding` scopes variable lookup.

## images

- Definition: Saves and restores runtime image and core state, including registered globals.
- Package: `cl-cc/runtime/images`
- Key types: None.
- Key functions: `rt-save-image`, `rt-load-image`, `rt-save-core`, `rt-load-core`
- Other contexts: `serialization` encodes individual runtime values; `images` captures and restores runtime state.

## concurrency

- Definition: Schedules runtime work and provides fibers, channels, synchronization, software transactional memory (STM), and lock-free coordination.
- Package: `cl-cc/runtime/concurrency`
- Key types: `rt-fiber`, `rt-tvar`
- Key functions: `rt-spawn`, `rt-fiber-spawn`, `rt-channel-send`, `rt-atomically`
- Other contexts: `conditions` models runtime conditions and restarts; condition variables here coordinate waiting threads.

## clos

- Definition: Implements runtime classes, slots, generic functions, and method dispatch.
- Package: `cl-cc/runtime/clos`
- Key types: None.
- Key functions: `rt-defclass`, `rt-make-instance`, `rt-call-generic`, `rt-call-next-method`
- Other contexts: `execution` invokes closures; `clos` resolves generic functions and next methods. `conditions` owns condition types and signaling.

## conditions

- Definition: Defines runtime condition types, handlers, restarts, and signaling.
- Package: `cl-cc/runtime/conditions`
- Key types: `rt-runtime-condition`, `rt-handler`, `rt-restart`
- Key functions: `rt-signal`, `rt-establish-handler`, `rt-invoke-restart`
- Other contexts: `concurrency` condition variables are synchronization primitives, not runtime condition objects.

## dynamic-binding

- Definition: Maintains dynamically scoped variable bindings and their runtime lookup environment.
- Package: `cl-cc/runtime/dynamic-binding`
- Key types: None.
- Key functions: `rt-with-dynamic-binding`
- Other contexts: `values` owns runtime values and symbol/package operations; this context owns scoped dynamic bindings.

## execution

- Definition: Represents callable runtime closures and provides function invocation, registration, and code-cache operations.
- Package: `cl-cc/runtime/execution`
- Key types: None.
- Key functions: `rt-make-closure`, `rt-call-fn`, `rt-apply-fn`, `rt-code-cache-lookup`
- Other contexts: `concurrency` schedules fibers and tasks; `execution` invokes runtime functions. `clos` owns generic-function dispatch.

## os

- Definition: Provides host process, clock, file, network, signal, foreign-function interface (FFI), and virtual-machine (VM) bridge operations.
- Package: `cl-cc/runtime/os`, `cl-cc/runtime/os/infra`
- Key types: `rt-process`, `rt-socket-address`
- Key functions: `rt-open`, `rt-gettime-monotonic`, `rt-socket-send`, `rt-ffi-load-library`
- Other contexts: OS infrastructure registers selected runtime functions by name for the VM to call. `dynamic-binding` supplies runtime symbol value lookup and updates used by the VM bridge registry.

## profiling

- Definition: Collects performance counters and sampled runtime profiles, then exports profile data.
- Package: `cl-cc/runtime/profiling`, `cl-cc/runtime/profiling/infra`
- Key types: `rt-continuous-profile-session`, `rt-profile-sample`
- Key functions: `rt-start-continuous-profile`, `rt-stop-continuous-profile`, `rt-export-continuous-profile`
- Other contexts: `observability` owns logs, metrics, and spans; profiling samples execution and exports profile data through that context.

## observability

- Definition: Records runtime logs, metrics, events, and spans and formats them for consumers.
- Package: `cl-cc/runtime/observability`
- Key types: `rt-otel-event`, `rt-otel-span`
- Key functions: `rt-register-metric`, `rt-otel-start-span`, `rt-otel-end-span`
- Other contexts: `profiling` samples execution stacks and time; observability records logs, metrics, and trace events.

## serialization

- Definition: Encodes supported runtime values into bytes and reconstructs values from that representation.
- Package: `cl-cc/runtime/serialization`
- Key types: None.
- Key functions: `serialize`, `deserialize`
- Other contexts: `images` captures runtime state; serialization encodes individual supported values.

## cryptography

- Definition: Computes SHA digests and HMAC values and encodes or decodes base64 octets.
- Package: `cl-cc/runtime/cryptography`
- Key types: None.
- Key functions: `rt-sha256`, `rt-sha512`, `rt-hmac-sha256`, `rt-base64-encode`, `rt-base64-decode`
- Other contexts: `serialization` encodes runtime object structure; cryptography operates on byte sequences.

## compression

- Definition: Provides byte compression and decompression operations for the runtime.
- Package: `cl-cc/runtime/compression`
- Key types: None.
- Key functions: `gzip-compress`, `gzip-decompress`, `zlib-compress`, `zlib-decompress`
- Other contexts: `serialization` encodes runtime values; compression transforms byte sequences.

## resilience

- Definition: Limits operation admission with a token bucket that refills over elapsed time.
- Package: `cl-cc/runtime/resilience`
- Key types: None.
- Key functions: `rt-make-token-bucket`, `rt-token-bucket-acquire`, `rt-token-bucket-wait`
- Other contexts: `cl-resilience-kit` tracks elapsed time for token refill; `concurrency` schedules work while resilience controls admission rate.

