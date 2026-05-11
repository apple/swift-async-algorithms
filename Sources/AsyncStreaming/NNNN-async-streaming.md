# Generalized asynchronous streaming

* Proposal: [SE-NNNN](NNNN-async-streaming.md)
* Authors: [Franz Busch](https://github.com/FranzBusch), [Karoy
  Lorentey](https://github.com/lorentey), [David
  Smith](https://github.com/Catfish-Man)
* Review Manager: TBD
* Status: **Awaiting implementation**
* Implementation: …
* Review: ([pitch](https://forums.swift.org/...))

## Summary of changes

Introduces four protocols for asynchronous streaming with caller- and
callee-managed buffer ownership for both reading and writing. Supports
noncopyable types, bulk/chunked access, and bidirectional streaming while
maintaining structured concurrency. Provides bridging extensions between
`AsyncReader` and `AsyncSequence`.

## Motivation

`AsyncSequence` (SE-0298) gave Swift a concurrency-compatible model for streams
of values arriving over time. It has served us well but has a number of
important limitations that become apparent when building high-performance,
bidirectional I/O systems.

### Values arrive one at a time

When each value is computationally "large", the overhead of calling `next()` is
negligible. But for simple types like bytes, that per-element overhead can dwarf
the actual work. This forces library authors into tricky, not-fully-general
workarounds with inline functions (as seen in `AsyncBufferedByteIterator`) or
into giving up on the `AsyncSequence` abstraction entirely.

The standard solution is buffering: read or write many elements at once. But
buffering introduces its own set of challenges — more on that below.

### Noncopyable types cannot be streamed

`AsyncSequence` was introduced before noncopyable types existed and requires its
`Element` to be `Copyable`. Streaming types are conceptually about moving values
from one place to another, and many important types such as move-only buffers
are noncopyable by nature.

### The iterator pattern is a poor fit for asynchronous streams

`AsyncSequence` followed the design of its synchronous counterpart `Sequence` by
using an iterator pattern. While iterators work well for synchronous
collections, they are a poor fit for asynchronous streams for two reasons:

 * **Most asynchronous sequences do not support multiple iterators.** Unlike an
   `Array`, which can be iterated multiple times independently, a network socket
   or file stream produces each value exactly once.
 * **Most asynchronous sequences are not replayable.** The iterator pattern
   suggests that calling `makeAsyncIterator()` again would restart iteration
   from the beginning, but this is almost never true for asynchronous sources.

### There is no protocol for the write side of a stream

During the design of APIs supporting bidirectional streaming — such as HTTP or
gRPC — it became apparent that `AsyncSequence`'s pull-based model only works for
one side. Trying to express both sides as an `AsyncSequence` forces the
introduction of unstructured tasks, breaking structured concurrency guarantees:

```swift
func bidirectionalStreaming(
    input: some AsyncSequence<UInt8, Never>
) async throws -> some AsyncSequence<UInt8, Never> {
    // The output sequence can produce values before input is fully consumed.
    // This forces an unstructured task to continue iterating the input
    // after this method returns.
    Task {
        for await byte in input {
            // Send byte
        }
    }
    return SomeOutputSequence()
}
```

A dedicated write protocol eliminates this problem by giving the output side a
push-based interface that can be driven within the same structured scope as the
input side.

### Buffer management has no single optimal strategy

Given the limitations above, we need new streaming protocols. Addressing the
per-element overhead requires buffering, but someone must be responsible for
creating and managing each buffer. There are two fundamental choices:

 * **The caller provides the buffer.** The stream fills (for reads) or drains
   (for writes) the caller's buffer.
 * **The callee provides the buffer.** The stream lends a filled buffer (for
   reads) or an empty buffer (for writes) to the caller via a scoped closure.

Each strategy is optimal in different situations, and neither can be eliminated
without imposing unnecessary overhead on important use cases:

**Callee-owned read is optimal when data arrives from an external source.** When
doing interprocess communication, the kernel's virtual memory system can re-map
a buffer from one process to another with zero copying. If the read stream takes
a buffer from its caller, this zero-copy transfer still incurs a copy to move
data from the remapped buffer to the client's buffer. With callee-owned read,
the data can be used in-place. The same applies to kernel-managed buffer schemes
where the operating system shares buffers directly with userspace.

**Caller-owned read is optimal when reading into an existing buffer.** If the
caller wants to initialize a subrange of an existing allocation by reading into
it, having the stream produce its own buffer — even a pre-allocated one — forces
at least a copy from the stream's buffer into the target region. With
caller-owned read, the stream fills the target region directly.

**Caller-owned write is optimal when the data already exists in a buffer.**
Writing the contents of an `Array` to disk via a stream that uses the `write()`
syscall internally requires no intermediate buffer if the caller hands the
array's storage directly to the stream. If the stream (callee) provided its own
buffer, the caller would have to copy the array's elements into it first.

**Callee-owned write is optimal when the destination already has storage.** In
many situations the writer already owns a buffer — a kernel-shared memory
region, a pre-registered I/O buffer, or the backing storage of a collection
being initialized. With callee-owned write, the writer exposes that existing
storage directly, letting the producer write into it in-place with no
intermediate buffer and no copy.

Caller-owned read and write are also important for Embedded Swift and other
resource-constrained environments, where the caller provides one buffer up front
and nothing else in the system ever needs to allocate.

If buffers cannot be reused, memory management overhead often dominates
performance. This motivates a design where the compiler enforces that buffers
are not stored after the operation completes, enabling safe reuse.

## Proposed solution

We propose a family of four protocols representing the possible combinations of
the 2×2 possibility matrix:

{ Caller Buffers, Callee Buffers } × { Read, Write }

These protocols use Swift's `InputSpan` and `OutputSpan` types to enforce that
buffers are not stored after the operation completes, enabling safe reuse. For
the callee-owned variants, a closure-scoped API ensures the compiler prevents
buffer escape.

The bite-sized pseudocode:

```
protocol AsyncReader {
    // Callee provides a full buffer; caller drains it
    func read(body: (buffer) throws -> R) throws -> R
}

protocol CallerAsyncReader {
    // Caller provides an empty buffer; callee fills it
    func read(into buffer: buffer) throws
}

protocol AsyncWriter {
    // Caller provides a full buffer; callee drains it
    func write(span: buffer) throws
}

protocol CalleeAsyncWriter {
    // Callee provides an empty buffer; caller fills it
    func write(body: (buffer) throws -> R) throws -> R
}
```

### Progressive disclosure

Four protocols is a little daunting to newcomers, and immediately raises the
question "which one(s) should my type conform to?". We believe that applying
"streams flow downhill" as a rule of thumb gets the best results in the majority
of situations:

> If you are not sure, pick callee-owned (`AsyncReader`) for read streams and
> caller-owned (`AsyncWriter`) for write streams.

The intuition: data produced by the callee flows toward the caller on the read
side, so the callee is the natural owner of the buffer. On the write side, data
produced by the caller flows toward the callee, so the caller is the natural
owner. The "other" pair exists for cases where the default imposes unnecessary
overhead.

By documenting this rule and following it in our own types, we expect developers
to naturally reach for `AsyncReader` and `AsyncWriter`, leaving
`CallerAsyncReader` and `CalleeAsyncWriter` for the specialized situations that
truly need them.

### Bridging with `AsyncSequence`

Rather than reparenting `AsyncSequence`, we provide bidirectional bridging
extensions that allow converting freely between the two abstractions:

```swift
// AsyncReader → AsyncSequence
let sequence = someReader.asyncSequence

// AsyncSequence → AsyncReader
let reader = someSequence.asyncReader
```

This approach avoids requiring the protocol reparenting language feature while
giving developers a clear migration path. Existing `AsyncSequence`-based APIs
can be consumed by code expecting an `AsyncReader`, and new `AsyncReader`-based
APIs can interoperate with the existing `AsyncSequence` ecosystem.

## Detailed design

### Support types

```swift
/// A type-safe wrapper around one of two distinct error types.
///
/// Use ``EitherError`` when an operation can fail with errors from two
/// different sources, such as a read failure and a body closure failure.
@frozen
public enum EitherError<First: Error, Second: Error>: Error {
  /// An error of the first type.
  ///
  /// The associated value contains the specific error instance of type `First`.
  case first(First)

  /// An error of the second type.
  ///
  /// The associated value contains the specific error instance of type `Second`.
  case second(Second)

  /// Throws the underlying error, unwrapping this either error.
  ///
  /// This method extracts and throws the error in the either error,
  /// whether it's the first or second type. Use this when you need to propagate
  /// the original error without the either error wrapper.
  ///
  /// - Throws: The underlying error, either of type `First` or `Second`.
  ///
  /// ## Example
  ///
  /// ```swift
  /// do {
  ///     // Some operation that returns EitherError
  ///     let result = try await operation()
  /// } catch let eitherError as EitherError<NetworkError, ParseError> {
  ///     try eitherError.unwrap() // Throws the original error
  /// }
  /// ```
  public func unwrap() throws {
    switch self {
    case .first(let first):
      throw first
    case .second(let second):
      throw second
    }
  }
}

extension EitherError where Second == Never {
    public func unwrap() throws(First) { ... }
}

extension EitherError where First == Never {
    public func unwrap() throws(Second) { ... }
}
```

The `EitherError` type exists because the callee-owned protocols have two
distinct failure domains: the underlying stream operation can fail, and the
caller's body closure can also fail. These are logically independent error
types, and conflating them would lose information. The `Never`-constrained
extensions allow ergonomic use when one side cannot fail.

### Callee-owned async reader (preferred read type)

The callee-owned reader controls the buffer and passes a span of elements to the
caller through a scoped closure. This is the preferred protocol for read
streams.

```swift
public protocol AsyncReader<Element, Failure>: ~Copyable, ~Escapable {
    /// The type of elements that can be read.
    associatedtype Element: ~Copyable

    /// The type of error thrown during reading.
    associatedtype Failure: Error

    /// Reads elements from the source and passes them to the body closure.
    ///
    /// The reader fills an internal buffer from its source and passes a span
    /// of the read elements to `body`. When the span is empty, the stream
    /// has ended.
    ///
    /// - Parameter maximumCount: The maximum number of elements the caller is
    ///   ready to process. Must be greater than zero.
    /// - Parameter body: A closure that processes the read elements.
    /// - Returns: The value returned by the body closure.
    /// - Throws: An `EitherError` containing either a `Failure` from the read
    ///   operation or a `ConsumerFailure` from the body closure.
    mutating func read<Return, ConsumerFailure: Error>(
        maximumCount: Int,
        body: (inout InputSpan<Element>) async throws(ConsumerFailure) -> Return
    ) async throws(EitherError<Failure, ConsumerFailure>) -> Return
}

extension AsyncReader {
    /// Reads elements with no upper bound on span size.
    ///
    /// This convenience calls `read(maximumCount: .max, body:)`.
    mutating func read<Return, ConsumerFailure: Error>(
        body: (inout InputSpan<Element>) async throws(ConsumerFailure) -> Return
    ) async throws(EitherError<Failure, ConsumerFailure>) -> Return {
        try await read(maximumCount: .max, body: body)
    }
}
```

### Caller-owned async reader

The caller provides a buffer that the reader fills with elements from the
source.

```swift
public protocol CallerAsyncReader<Element, Failure>: ~Copyable, ~Escapable {
    /// The type of elements that can be read.
    associatedtype Element: ~Copyable

    /// The type of error thrown during reading.
    associatedtype Failure: Error

    /// Reads elements from the source into the provided buffer.
    ///
    /// Appends elements into `buffer`. When the read operation reaches the
    /// end of the source, no elements are appended.
    ///
    /// - Parameter buffer: The output span to fill with read elements.
    /// - Throws: A `Failure` from the underlying read operation.
    mutating func read(
        into buffer: inout OutputSpan<Element>
    ) async throws(Failure)
}
```

### Caller-owned async writer (preferred write type)

The caller provides a span of elements for the writer to consume. This is the
preferred protocol for write streams.

```swift
public protocol AsyncWriter<WriteElement, WriteFailure>: ~Copyable, ~Escapable {
    /// The type of elements that can be written.
    associatedtype WriteElement: ~Copyable

    /// The type of error thrown during writing.
    associatedtype WriteFailure: Error

    /// Writes a span of elements to the destination.
    ///
    /// Asynchronously writes all elements from the provided span. If the
    /// writer cannot accept all elements at once, `span` will be non-empty
    /// after `write` returns.
    ///
    /// - Parameter span: The span of elements to write.
    /// - Throws: A `WriteFailure` from the underlying write operation.
    mutating func write(
        span: borrowing InputSpan<WriteElement>
    ) async throws(WriteFailure)
}
```

### Callee-owned async writer

The writer provides a buffer that the caller fills with elements to write.

```swift
public protocol CalleeAsyncWriter<WriteElement, WriteFailure>: ~Copyable, ~Escapable {
    /// The type of elements that can be written.
    associatedtype WriteElement: ~Copyable

    /// The type of error thrown during writing.
    associatedtype WriteFailure: Error

    /// Provides a buffer for writing elements to the destination.
    ///
    /// The writer supplies an output span that the `body` closure fills with
    /// elements. After the closure returns, the writer handles the actual
    /// write operation.
    ///
    /// - Parameter body: A closure that receives an `OutputSpan` to fill.
    /// - Returns: The value returned by the body closure.
    /// - Throws: An `EitherError` containing either a `WriteFailure` from the
    ///   write operation or a `ProducerFailure` from the body closure.
    mutating func write<Return, ProducerFailure: Error>(
        _ body: (inout OutputSpan<WriteElement>) async throws(ProducerFailure) -> Return
    ) async throws(EitherError<WriteFailure, ProducerFailure>) -> Return
}
```

### Bridging between `AsyncReader` and `AsyncSequence`

We provide extensions for converting between `AsyncReader` and `AsyncSequence`
in both directions. These require `Element: Copyable` since `AsyncSequence` does
not support noncopyable elements.

#### `AsyncReader` to `AsyncSequence`

```swift
extension AsyncReader where Self: ~Copyable, Self: ~Escapable, Element: Copyable {
    /// Returns an `AsyncSequence` that yields the elements of this reader
    /// one at a time.
    ///
    /// The returned sequence calls `read` on the underlying reader and
    /// yields the elements from each span individually.
    public var asyncSequence: AsyncReaderSequence<Self> { get }
}

/// An `AsyncSequence` adapter over an `AsyncReader`.
public struct AsyncReaderSequence<
    Reader: AsyncReader & ~Copyable & ~Escapable
>: AsyncSequence where Reader.Element: Copyable {
    public typealias Element = Reader.Element
    public typealias Failure = Reader.Failure

    public struct AsyncIterator: AsyncIteratorProtocol {
        public mutating func next() async throws(Failure) -> Element?
    }

    public func makeAsyncIterator() -> AsyncIterator
}
```

#### `AsyncSequence` to `AsyncReader`

```swift
extension AsyncSequence {
    /// Returns an `AsyncReader` that reads elements from this sequence.
    ///
    /// Each call to `read` on the returned reader advances the sequence's
    /// iterator and passes available elements to the body closure as a span.
    public var asyncReader: AsyncSequenceReader<Self> { get }
}

/// An `AsyncReader` adapter over an `AsyncSequence`.
public struct AsyncSequenceReader<
    Base: AsyncSequence
>: AsyncReader {
    public typealias Element = Base.Element
    public typealias Failure = Base.Failure

    public mutating func read<Return, ConsumerFailure: Error>(
        maximumCount: Int?,
        body: (inout InputSpan<Element>) async throws(ConsumerFailure) -> Return
    ) async throws(EitherError<Failure, ConsumerFailure>) -> Return
}
```

These bridging types allow incremental adoption: existing `AsyncSequence`-based
APIs can be consumed by code expecting an `AsyncReader`, and new
`AsyncReader`-based APIs remain accessible to code that expects an
`AsyncSequence`.

## Source compatibility

This proposal is purely additive. It introduces new protocols, types, and
extensions without modifying any existing declarations.

## ABI compatibility

This proposal is purely an extension of the ABI of the standard library and does
not change any existing features.

## Implications on adoption

Like almost all new types, these protocols do not support back deployment.

Library authors adopting these protocols can do so additively. Conforming a type
to one of the new protocols does not affect existing API or ABI. The conformance
can be removed later without breaking source or ABI compatibility, subject to
normal API evolution considerations.

## Future directions

### Convenience extensions

The core protocol signatures are general but unwieldy for types that have no
interest in bulk access. Convenience extensions would simplify common usage
patterns, for example:

 * Simplified error handling when one side cannot fail (`Failure == Never` or a
   non-throwing body closure).
 * Single-element access via a `next()` method for callee-owned readers.
 * Adapting a callee-owned reader to a caller-owned buffer (at the cost of a
   copy) for interoperability between the two buffer ownership strategies.

These extensions are straightforward to add in a follow-up proposal once the
core protocols are established.

### Owned buffer transfer protocols

The four protocols in this proposal all use `InputSpan` and `OutputSpan` to
provide scoped, non-escaping access to buffers. This is optimal for
high-throughput streaming where buffer reuse matters — the compiler enforces
that the buffer cannot be stored after the closure returns, enabling safe reuse
without copies.

However, there are important message-oriented I/O patterns where the caller
needs to take ownership of the data with an independent lifetime. Consider an
HTTP/2 proxy: the proxy decodes a DATA frame, which internally allocates a
buffer to hold the frame payload. With span-based protocols, the proxy receives
a borrowed view and must copy the data if it needs to store it for retry or
fan-out to multiple downstream connections.

An owned buffer transfer protocol would let the decoder hand over its
internally-allocated buffer by value. The proxy can store it, retry a failed
send, or pass it to multiple consumers — all without copying:

```swift
// Conceptual sketch — not part of this proposal
protocol OwnedAsyncReader<Buffer, Failure>: ~Copyable, ~Escapable {
    associatedtype Buffer: ~Copyable
    associatedtype Failure: Error

    mutating func read() async throws(Failure) -> Buffer?
}
```

This differs fundamentally from the caller/callee distinction in this proposal.
The span-based protocols are about **who manages a reusable buffer during a
streaming operation**. Owned buffer transfer is about **transferring
independently-allocated data with a lifecycle decoupled from the stream**. This
is the distinction between stream-oriented I/O (TCP byte streams, file reads)
and message-oriented I/O (HTTP frames, protocol messages).

Several open design questions remain for owned buffer transfer:

 * **What type should the buffer be?** An associated type bounded by a protocol
   (similar to how the `http-body` crate in other ecosystems uses an associated
   `Data` type bounded by a `Buf` trait) provides maximum flexibility — each
   conforming type can yield its own buffer type (`Array`, `UniqueArray`,
   `Data`, or a custom reference-counted immutable buffer). The protocol bound
   would provide basic operations: count, access to underlying bytes, and
   possibly zero-copy slicing.
 * **Copyable or noncopyable?** For message-oriented patterns where cheap
   sharing matters (proxy retry, fan-out, logging), a copy-on-write `Copyable`
   type like `Array` is the natural default. For kernel-shared or DMA-mapped
   buffers where copying is meaningless or dangerous, a `~Copyable` type
   enforces single-ownership. The associated type should be bounded as
   `~Copyable` to allow both.

Because owned buffer transfer has fundamentally different semantics — it returns
owned values rather than providing scoped access — it requires its own
protocols. The four protocols proposed here are stable and orthogonal to this
future addition.

### Vectored I/O protocols (scatter/gather)

Operating systems provide scatter/gather I/O operations (`readv`/`writev` on
POSIX, `WSARecv`/`WSASend` on Windows) that read into or write from multiple
non-contiguous buffers in a single system call. This is important for network
interfaces that may have many separately allocated packets ready to deliver, or
for protocols that produce headers and payloads in separate buffers.

A vectored variant would operate on a collection of spans rather than a single
contiguous span. The central design challenge is **sizing**: how many span
entries can the collection hold?

 * A fixed-size inline array (e.g., `InlineArray<N, InputSpan<Element>>`) avoids
   heap allocation but requires choosing N at compile time. Too small limits
   flexibility; too large wastes stack space.
 * A dynamically-sized array heap-allocates on every I/O operation, which is
   unacceptable on hot paths.
 * A small-vector optimization (inline N, then spill to heap) adds branching and
   complexity.

The callee-owned pattern from this proposal suggests a solution: the entity
closest to the system call knows the right sizing. A file writer wrapping
`writev` knows it needs at most `IOV_MAX` (typically 1024) entries. A TLS writer
knows it produces at most 2 segments. A UDP socket sends one segment per
datagram. By having the callee manage the vectored span's backing storage —
using inline arrays, pooled allocations, or `withUnsafeTemporaryAllocation` as
appropriate — the sizing problem is delegated to the entity with the most
information.

Because vectored I/O operates on a fundamentally different data structure (a
collection of non-contiguous spans rather than a single contiguous span),
grafting it onto the existing protocols would complicate the common
single-buffer case for all users. It is best served by its own protocols. The
four protocols proposed here are stable and orthogonal to this future addition.

### Synchronous versions of the protocols

The engineers working on the ["future of
serialization"](https://forums.swift.org/t/the-future-of-serialization-deserialization-apis/78585)
project have indicated that async-only is unpalatable for uses like theirs.
Synchronous equivalents of these protocols would be valuable, but the design for
synchronous noncopyable iteration and container types is still in flux. We
should wait to see how best to integrate with that work.

### Structured algorithms with scoped lifetime

Some algorithms in `swift-async-algorithms` — such as `merge`, `zip`, and
`buffer` — currently require unstructured tasks because reading from an upstream
sequence must outlive a single call to the iterator's `next()` method. For
example, `merge` races multiple base sequences on each call to `next`; when one
base produces a value, iteration of the other bases must continue independently.

The use of unstructured tasks means cancellation, priority escalation, task
executor preference, and task locals must all be propagated manually — a fragile
and error-prone pattern.

These algorithms could instead be redesigned as scoped, `with`-style operations
or types with an explicit `run` method that manages the concurrent iteration
within a structured child task:

```swift
await merge(first, second) { merged in
    for await element in merged {
        // process element
    }
}
```

This is an independent concern from the streaming protocols proposed here, but
the new protocols provide a better foundation for such redesigns.

## Alternatives considered

### Only supporting a subset of the buffer ownership options

For simplicity, it would be nice to have fewer protocols. We could support only
callee-owned read and caller-owned write (the "preferred" pair), or only
caller-owned for both directions.

We decided that since no single buffer ownership strategy is optimal for all
cases (as demonstrated in the Motivation section), the full 2×2 matrix is
necessary. With clear signposting of which protocols are "preferred," the
developer experience remains approachable for the majority while not tying the
hands of those with specialized requirements.

### Not using closures to provide temporary access to buffers

The callee-owned read and write APIs use closures that receive a span, which
introduces the complexity of `EitherError` (since both the stream operation and
the closure can throw independent error types). It would be simpler to return a
span directly.

However, without closures (or equivalent coroutine support like generators),
there would be no way for the callee to perform cleanup work when the caller is
done with the buffer. This makes the design incompatible with buffer pools,
where the callee must reclaim the buffer after use. The closure-scoped pattern
ensures the callee maintains control over buffer lifecycle.

### Just extending `AsyncSequence` with bulk transfer support

This was the original plan. However, recent developments on `Sequence` have
shown that supporting noncopyable types requires a new protocol regardless.
Given that a new protocol is needed anyway, designing the full streaming family
from scratch allows us to address all the limitations at once.

### Reparenting `AsyncSequence`

Instead of bridging extensions, we could use protocol reparenting to
retroactively make `AsyncSequence` a subtype of `AsyncReader`. This would give
every existing `AsyncSequence` conformance automatic participation in the new
streaming ecosystem without any code changes.

However, would also force an `AsyncReader`/`AsyncReaderIterator` split to match
`AsyncSequence`'s existing `makeAsyncIterator()` pattern, complicating the
`AsyncReader` protocol for all users. The bridging approach achieves the same
interoperability with explicit, discoverable conversions and a simpler protocol
definition.

### Using a concrete type rather than protocols

We could define concrete streaming types instead of protocols. This would
simplify some aspects of the design but would prevent adapting existing types to
the new abstraction. Protocols give library authors the flexibility to implement
streaming over their own storage and I/O backends.

### Using `throws` rather than typed throws

Embedded Swift environments do not support allocating boxes for existential
errors. Using typed throws (`throws(Failure)`) allows these protocols to be used
in resource-constrained environments, which is an explicit goal of this design.

### Having split stream/iterator types

For symmetry with `AsyncSequence`'s `makeAsyncIterator()` pattern, we considered
adding an iterator split to some or all of the streaming protocols. This would
be necessary if we chose to reparent `AsyncSequence` (see above). Since we use
bridging extensions instead, none of the four protocols need an iterator split,
resulting in a simpler and more uniform design.

### Async generators

Asynchronous generators could provide an alternative to `AsyncSequence` and
`AsyncReader` by allowing a function to `yield` values over time. However,
generators would require significant compiler work and would primarily address
only the read side. The write side — which is essential for bidirectional
streaming — would still need a separate push-based protocol. Generators may
complement this proposal in the future, but they do not replace the need for the
protocols proposed here.

### Approaches in other ecosystems

Other language ecosystems have explored the same problem space of async I/O
buffer management.

#### Go

Go's I/O model is built on two minimal interfaces: `io.Reader` with `Read(p
[]byte) (n int, err error)` and `io.Writer` with `Write(p []byte) (n int, err
error)`. **Buffer ownership is strictly caller-owned in both directions.** The
documentation states "implementations must not retain p" but this is enforced
only by convention — Go has no lifetime or borrowing annotations.

Go has no general-purpose callee-owned buffer interface. The `bufio.Reader` type
provides `Peek()` and `ReadSlice()` methods that return views into an internal
buffer, but only as concrete methods on a specific type, not as an interface
abstraction. When data arrives from the kernel or IPC in an existing buffer, the
caller-only model forces a copy into the caller's `[]byte` — there is no
standard way for the reader to say "here is data I already have."

Go's goroutine model — where blocking I/O suspends a goroutine rather than an OS
thread — means there is less pressure to model async operations at the type
level. The `io.Reader`/`io.Writer` interfaces are synchronous, and concurrency
comes from running readers and writers in separate goroutines. This simplifies
interface signatures but means cancellation is handled separately via
`context.Context`, outside the I/O interfaces themselves.

For scatter/gather I/O, `net.Buffers` (a `[][]byte`) dispatches to `writev` on
supported connections, but only for writes — there is no equivalent for vectored
reads.

#### .NET

.NET's classic `System.IO.Stream` uses caller-owned buffers, like Go:
`ReadAsync(Memory<byte> buffer)` and `WriteAsync(ReadOnlyMemory<byte> buffer)`.
Limitations observed in high-performance server code (ASP.NET Core's Kestrel)
motivated a redesign.

`System.IO.Pipelines` (2018) introduces `PipeReader` and `PipeWriter` as
separate types with distinct buffer ownership strategies:

 * **`PipeReader` is callee-owned read.** `ReadAsync()` returns a `ReadResult`
   containing a `ReadOnlySequence<byte>` — a linked list of memory segments
   owned by the pipe. The caller examines the data in-place, then calls
   `AdvanceTo(consumed, examined)` to signal how much was processed. This
   enables partial consumption without copying and provides .NET's answer to
   non-contiguous buffers: segments from multiple network reads are chained
   together without coalescing into a single contiguous buffer.

 * **`PipeWriter` is callee-owned write.** The writer exposes its internal
   buffer via `GetMemory()`/`GetSpan()`, the caller fills it, then calls
   `Advance()` to commit. This is formalized as the `IBufferWriter<T>`
   interface. `PipeWriter` also offers `WriteAsync(ReadOnlyMemory<byte>)` as a
   caller-owned convenience that internally copies into the pipe's buffer.

Pipelines includes built-in backpressure: when unconsumed data exceeds a
configurable threshold, `FlushAsync()` suspends the writer until the reader
catches up. Buffer pooling is integrated via `MemoryPool<T>`.

The lifetime safety of buffer access in Pipelines is enforced at runtime — using
a `ReadOnlySequence<byte>` after calling `AdvanceTo` is undefined behavior.
.NET's `Span<T>` (a stack-only ref struct that cannot survive across `await`
points) provides some compile-time safety, but `Memory<T>` (the heap-storable
counterpart needed for async code) does not.

#### Rust

In the Rust ecosystem, the `AsyncRead` and `AsyncWrite` traits use borrowed
buffers (`&mut [u8]`), which works for readiness-based I/O but is fundamentally
incompatible with completion-based I/O where the kernel holds the buffer for an
indeterminate period. This led to a fragmented ecosystem: readiness-based
runtimes (tokio, async-std) use one set of traits, while completion-based
runtimes (tokio-uring, monoio, compio) use a different set of ownership-transfer
traits (`IoBuf`/`IoBufMut`).

A major contributor to this fragmentation is the interaction between Rust's
`Future` trait (where futures can be dropped at any suspension point) and
completion-based I/O (where the kernel may still hold a buffer when a future is
cancelled). This creates potential use-after-free scenarios that require complex
workarounds: ownership transfer, buffer graveyards, or the still-unresolved
async destructor RFC.

#### What Swift's design learns from these ecosystems

Swift's structured concurrency model avoids the cancellation and buffer lifetime
problems that fragment Rust's ecosystem: structured concurrency guarantees that
child tasks complete before the parent scope exits, and cancellation is
cooperative. The closure-scoped design of the callee-owned protocols provides
compiler-enforced safety — `InputSpan` and `OutputSpan` are `~Escapable`, so the
compiler guarantees at the type level that buffers cannot outlive their scope.
This is stronger than Go's convention-based "must not retain p" and .NET's
runtime-only enforcement after `AdvanceTo`.

The proposal's 2×2 matrix of {caller, callee} × {read, write} is unique among
these ecosystems. Go provides only caller-owned for both directions. .NET
Pipelines provides callee-owned for both directions (with a caller-owned write
convenience) but not caller-owned read as a first-class abstraction. The Swift
proposal provides all four combinations, informed by the observation that each
is optimal in distinct situations.

We studied these ecosystems' experiences to validate the design space
decomposition, and to confirm that owned buffer transfer and vectored I/O (both
listed as future directions) are genuinely separate concerns that warrant their
own protocols rather than being forced into the caller/callee framework.
