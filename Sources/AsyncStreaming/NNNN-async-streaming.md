# Generalized asynchronous streaming

* Proposal: [SE-NNNN](NNNN-async-streaming.md)
* Authors: [Franz Busch](https://github.com/FranzBusch), [Karoy
  Lorentey](https://github.com/lorentey), [David
  Smith](https://github.com/Catfish-Man)
* Review Manager: TBD
* Status: **Awaiting implementation**
* Implementation: …
* Related Proposals:
    - [SE-0298: Async/Await: Sequences][SE-0298]
    - [SE-0447: `Span`: Safe Access to Contiguous Storage][SE-0447]
    - [SE-0461: Run nonisolated async functions on the caller's actor by default][SE-0461]
    - [SE-0485: `OutputSpan`: delegate initialization of contiguous memory][SE-0485]
    - [Pitch: `InputSpan`][input-span]
    - [Pitch: Single-yield functions][single-yield]
    - [Pitch: Asynchronous access to pointers of spans][async-pointers]
* Review: ([pitch](https://forums.swift.org/...))

## Summary of changes

Introduces four protocols for asynchronous streaming with caller- and
callee-managed buffer ownership for both reading and writing. The protocols
exchange elements through `Span`, `OutputSpan` and `InputSpan`, so a conformer
never has to allocate or convert a container. Elements can be noncopyable, and
their ownership can move through a stream, e.g. buffers that are leased from a
pool and have to be returned to it. The protocols support bulk access, fused
end-of-stream signaling with an optional final-element payload, and
bidirectional streaming while maintaining structured concurrency.

Additionally, this proposal adds asynchronous variants of the span-providing
methods of `Array`, `UniqueArray` and `InlineArray`, so that adopters can read
into and write from these types until the standard library provides such
methods. Lastly, it provides bridging extensions between `AsyncReader` and
`AsyncSequence`.

## Motivation

`AsyncSequence` ([SE-0298]) gave Swift a concurrency-compatible model for
streams of values arriving over time. It has served us well but has a number of
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
such as the provided buffers of `io_uring`, where the kernel picks the buffer
when the read completes.

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

### Buffers sometimes have to change hands

Scoped access to a buffer covers most of streaming I/O, but not all of it. Some
I/O systems hand out buffers that the receiver owns until it gives them back.
For example, an I/O executor that uses the provided buffers of `io_uring` reads
into a buffer of a kernel-registered pool and hands the buffer to the reader,
which has to return it to the pool once it is done:

```swift
var buffer = try await connection.read()
parse(buffer.bytes)
buffer.return()
```

Owning the buffer lets the receiver keep it beyond a single read. An HTTP/2
server can split one read into the payloads of several streams and hand each
payload to the task that handles its stream. A proxy can forward a buffer that
it read from one connection to another connection without copying it, and keep
it for a retry until the peer acknowledged it. The write side has the same
need. A writer that uses zero-copy send has to keep the buffer until the kernel
is done with it, which is after the write call returned.

Streaming protocols that only lend scoped spans force a copy in all of these
cases. The protocols have to be able to transfer the ownership of elements in
both directions.

## Proposed solution

We propose a family of four protocols representing the possible combinations of
the 2×2 possibility matrix:

{ Caller Buffers, Callee Buffers } × { Read, Write }

The protocols exchange elements through span types. None of them owns its
memory, so a conformer never has to allocate or convert a container, and an I/O
type can read into or write from memory it already owns:

 * A `Span` is a borrowed, read-only view of initialized elements.
 * An `OutputSpan` is a view of uninitialized memory that the holder appends
   elements to. The elements are owned by whoever owns the memory.
 * An `InputSpan` is a view of initialized elements that the holder can remove
   and take ownership of. The elements that it leaves are destroyed.

For the callee-owned variants, a closure-scoped API ensures that the span can't
outlive the operation, enabling safe reuse of the underlying storage.

The bite-sized pseudocode:

```
protocol AsyncReader {
    // Callee lends the next elements; caller borrows or takes them
    func read(maxCount: Int, body: (inout InputSpan<Element>) throws -> R) throws -> R
}

protocol CallerAsyncReader {
    // Caller provides an output span; callee appends elements to it
    func read(into buffer: inout OutputSpan<Element>) throws
}

protocol CallerAsyncWriter {
    // Caller lends elements; callee writes them out
    func write(_ elements: Span<Element>) throws
    // Caller hands over elements; callee takes ownership of them
    func write(_ elements: inout InputSpan<Element>) throws
}

protocol AsyncWriter {
    // Callee lends an output span; caller appends elements to it
    func write(body: (inout OutputSpan<Element>) throws -> R) throws -> R
}
```

### Reading drains the stream

A stream produces each element exactly once. `AsyncReader` reflects this: each
read lends the next elements of the stream to the body as an `InputSpan`, and
the elements are gone from the stream afterwards. The body can borrow them
through the span's `span` property:

```swift
try await reader.read { elements, finalElement in
    checksum.update(elements.span)
}
```

The body can also remove elements from the span to take ownership of them. The
reader destroys the elements that the body leaves. The `maxCount` parameter
lets the body limit how many elements a read delivers, so it doesn't receive
elements that it can't handle:

```swift
// Takes exactly one frame header off the stream
let header = try await reader.read(maxCount: 1) { headers, _ in
    headers.popFirst()
}
```

This follows the draining iteration of the `Drain` protocol of the
[`ContainersPreview`][containers-preview] module, whose
`drainNext(maxCount:)` method returns the next elements of a container as an
`InputSpan`, and the `nextSpan(maxCount:)` method of the standard library's
`BorrowingIteratorProtocol`.

### Transferring ownership

Since the elements of a stream can be noncopyable, ownership transfer doesn't
need its own protocols. A buffer that has to be returned to its pool is a
noncopyable element, and the span types move it between the two sides of a
stream:

| Protocol            | Span                 | Ownership of the elements    |
| ------------------- | -------------------- | ---------------------------- |
| `AsyncReader`       | `inout InputSpan`    | moves from reader to caller  |
| `CallerAsyncReader` | `inout OutputSpan`   | moves from reader to caller  |
| `AsyncWriter`       | `inout OutputSpan`   | moves from caller to writer  |
| `CallerAsyncWriter` | `inout InputSpan`    | moves from caller to writer  |
| `CallerAsyncWriter` | `Span`               | stays with the caller        |

A reader that hands out leased buffers is an `AsyncReader` whose elements are
leases. A consumer takes the leases that it wants to keep and returns them once
it is done:

```swift
struct LeasedBuffer: ~Copyable {
    var bytes: RawSpan { get }
    consuming func `return`()
}

// connection.leasedBuffers is some AsyncReader<LeasedBuffer, IOError>
try await connection.leasedBuffers.read { buffers, _ in
    while let buffer = buffers.popFirst() {
        try await demultiplexer.route(buffer)
    }
}
```

A proxy can pipe the leases from one connection to another. The writer takes
ownership of each lease and returns it to its pool once the peer is done with
it, and no byte is copied:

```swift
try await upstream.leasedBuffers.pipe(into: downstream.leasedBufferWriter)
```

The caller-owned writer has two `write` methods. The `Span` overload lends the
elements, so the caller keeps them, e.g. to retry a request. The `InputSpan`
overload hands them over. Its default implementation calls the `Span` overload
and destroys the elements afterwards, so writers that copy the elements anyway
only implement the `Span` overload.

### Async span access for common containers

The standard library and the `BasicContainers` module only lend `OutputSpan`
and `InputSpan` to synchronous closures, since their owner has to run a
finalizer once the closure returns. These spans can't be used across a
suspension point today, so an array can't be the target of an asynchronous
read. We propose asynchronous variants of these methods for `Array`,
`UniqueArray` and `InlineArray`:

```swift
var bytes = [UInt8]()
let finalElement = try await bytes.append(addingCapacity: 4096) { output in
    try await reader.read(into: &output)
}

try await bytes.consumeAll { elements in
    try await writer.write(&elements)
}
```

These methods are a stopgap. We expect the standard library to provide
asynchronous span access, see [Yielding spans](#yielding-spans).

### Progressive disclosure

Four protocols is a little daunting to newcomers, and immediately raises the
question "which one(s) should my type conform to?". We believe that applying
"streams flow downhill" as a rule of thumb gets the best results in the majority
of situations:

> If you are not sure, pick callee-owned (`AsyncReader`) for read streams and
> caller-owned (`CallerAsyncWriter`) for write streams.

The intuition: data produced by the callee flows toward the caller on the read
side, so the callee is the natural owner of the buffer. On the write side, data
produced by the caller flows toward the callee, so the caller is the natural
owner. The "other" pair exists for cases where the default imposes unnecessary
overhead.

By documenting this rule and following it in our own types, we expect developers
to naturally reach for `AsyncReader` and `CallerAsyncWriter`, leaving
`CallerAsyncReader` and `AsyncWriter` for the specialized situations that
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
  case first(First)

  /// An error of the second type.
  case second(Second)

  /// Throws the underlying error, unwrapping this either error.
  public func unwrap() throws
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

### `InputSpan`

The protocols use the `InputSpan` type that the [`InputSpan` pitch][input-span]
proposes for the standard library. Until that pitch is accepted, the
implementation uses the `InputSpan` type of the `SpanPreview` module of
swift-collections, which has the same shape. An `InputSpan` holds initialized
elements at the end of its memory. Removing an element from its front transfers
the ownership of the element to the caller, and the elements that are left when
the span is destroyed are deinitialized.

### Callee-owned async reader (preferred read type)

The callee-owned reader controls the buffer and lends the next elements of the
stream through a scoped closure. This is the preferred protocol for read
streams.

```swift
public protocol AsyncReader<ReadElement, ReadFailure, FinalElement>: ~Copyable, ~Escapable {
  /// The type of elements this reader reads.
  associatedtype ReadElement: ~Copyable

  /// The error type that reading operations throw.
  associatedtype ReadFailure: Error

  /// The data the reader delivers alongside the end-of-stream signal.
  ///
  /// Defaults to `Void`. Use `Never` for streams that never end.
  associatedtype FinalElement: ~Copyable = Void

  /// Reads the next elements of the source and lends them to `body`.
  ///
  /// The reader suspends until it can deliver at least one element or the end
  /// of the stream. Calling this method after the reader delivered a non-`nil`
  /// `finalElement` is a programmer error.
  ///
  /// - Parameters:
  ///   - maxCount: The maximum number of elements that `body` receives. Must be
  ///     greater than zero.
  ///   - body: Receives the elements and, on the last read, the end-of-stream
  ///     payload. The reader destroys the elements that `body` leaves in the span.
  /// - Returns: The value that `body` returns.
  /// - Throws: A `ReadFailure` from the read, or the error of `body`.
  mutating func read<Return: ~Copyable, Failure: Error>(
    maxCount: Int,
    body: (inout InputSpan<ReadElement>, consuming FinalElement?) async throws(Failure) -> Return
  ) async throws(EitherError<ReadFailure, Failure>) -> Return
}

extension AsyncReader where Self: ~Copyable, Self: ~Escapable, ReadElement: ~Copyable, FinalElement: ~Copyable {
  /// Reads the next elements of the source, with no limit on their count, and
  /// lends them to `body`.
  public mutating func read<Return: ~Copyable, Failure: Error>(
    body: (inout InputSpan<ReadElement>, consuming FinalElement?) async throws(Failure) -> Return
  ) async throws(EitherError<ReadFailure, Failure>) -> Return
}
```

The reader destroys the elements that the body leaves, which runs their
`deinit`. A lease type that is used as the element of a stream should therefore
return itself to its pool when it is destroyed, instead of trapping.

### Caller-owned async reader

The caller provides an `OutputSpan` that the reader fills with elements from the
source. The `OutputSpan` can wrap memory the caller already owns, such as the
uninitialized tail of an array, so the reader initializes the target region
directly. The caller owns the elements that the reader appends.

```swift
public protocol CallerAsyncReader<ReadElement, ReadFailure, FinalElement>: ~Copyable, ~Escapable {
  associatedtype ReadElement: ~Copyable
  associatedtype ReadFailure: Error
  associatedtype FinalElement: ~Copyable = Void

  /// Reads elements from the source into the provided output span.
  ///
  /// This method appends elements into `buffer`'s free capacity. A reader
  /// that has nothing to deliver and is not at the end of the stream suspends
  /// until it can append at least one element. A buffer without free capacity
  /// is a programmer error. A non-`nil` return value signals end-of-stream and
  /// delivers the final payload. The call may also append a final batch of
  /// elements before signaling end.
  ///
  /// - Parameter buffer: The output span to append the read elements to.
  /// - Returns: A non-`nil` ``FinalElement`` if this call delivered the
  ///   end-of-stream signal; `nil` if more elements may follow.
  /// - Throws: A `ReadFailure` from the underlying read operation.
  mutating func read(
    into buffer: inout OutputSpan<ReadElement>
  ) async throws(ReadFailure) -> FinalElement?
}
```

### Caller-owned async writer (preferred write type)

The caller provides the elements for the writer to write. This is the preferred
protocol for write streams. The `Span` overloads lend the elements, so the
writer has written or copied all of them when the call returns. The `InputSpan`
overloads hand the elements over, and the writer can keep them after the call
returned.

```swift
public protocol CallerAsyncWriter<WriteElement, WriteFailure, FinalElement>: ~Copyable, ~Escapable {
  associatedtype WriteElement: ~Copyable
  associatedtype WriteFailure: Error
  associatedtype FinalElement: ~Copyable = Void

  /// Writes the given elements to the destination.
  ///
  /// - Parameter elements: The elements to write. The writer has written or
  ///   copied all of them when the call returns.
  mutating func write(
    _ elements: Span<WriteElement>
  ) async throws(WriteFailure)

  /// Writes the given elements to the destination and takes ownership of them.
  ///
  /// - Parameter elements: The elements to write. On return the span is empty.
  ///   If the call throws, the span keeps the elements that the writer did not take.
  mutating func write(
    _ elements: inout InputSpan<WriteElement>
  ) async throws(WriteFailure)

  /// Writes the last elements, delivers the ``FinalElement`` payload, and
  /// signals end-of-stream.
  consuming func finish(
    _ elements: Span<WriteElement>,
    finalElement: consuming FinalElement
  ) async throws(WriteFailure)

  /// Writes the last elements, takes ownership of them, delivers the
  /// ``FinalElement`` payload, and signals end-of-stream.
  consuming func finish(
    _ elements: inout InputSpan<WriteElement>,
    finalElement: consuming FinalElement
  ) async throws(WriteFailure)
}

extension CallerAsyncWriter where Self: ~Copyable, Self: ~Escapable, WriteElement: ~Copyable, FinalElement: ~Copyable {
  /// Writes `elements.span` and then destroys the elements.
  public mutating func write(
    _ elements: inout InputSpan<WriteElement>
  ) async throws(WriteFailure)

  /// Finishes with `elements.span` and then destroys the elements.
  public consuming func finish(
    _ elements: inout InputSpan<WriteElement>,
    finalElement: consuming FinalElement
  ) async throws(WriteFailure)
}
```

### Callee-owned async writer

The writer lends an `OutputSpan` that the caller fills with elements to write.
The writer decides where the span points, for example at a kernel-shared memory
region or a pre-registered I/O buffer. The writer owns the elements that the
caller appends.

```swift
public protocol AsyncWriter<WriteElement, WriteFailure, FinalElement>: ~Copyable, ~Escapable {
  associatedtype WriteElement: ~Copyable
  associatedtype WriteFailure: Error
  associatedtype FinalElement: ~Copyable = Void

  /// Provides a buffer for writing elements to the destination.
  ///
  /// The writer supplies an output span, sized by the implementation, that
  /// `body` uses to append elements. The writer manages the buffer
  /// allocation and handles the writing operation once `body` completes.
  /// Oversized payloads are split across multiple calls.
  mutating func write<Return: ~Copyable, Failure: Error>(
    _ body: (inout OutputSpan<WriteElement>) async throws(Failure) -> Return
  ) async throws(EitherError<WriteFailure, Failure>) -> Return

  /// Closes the writer, delivering a ``FinalElement`` payload alongside the
  /// end-of-stream signal.
  consuming func finish(
    finalElement: consuming FinalElement
  ) async throws(WriteFailure)
}
```

### Final-element payload

Every protocol carries a `FinalElement` associated type, the data, if any,
that the stream delivers alongside its end-of-stream signal. The default is
`Void`, which carries no extra payload; the signal itself is the only
information conveyed. Besides `Void` final elements there are two other
possibilities:

 * **`FinalElement == Never`** marks a stream as endless. For readers, the
   terminal signal can never fire (because `Never?` only inhabits `nil`), so
   callers can rely statically on the absence of termination — useful for
   clocks, log tails, and other endless sources. The same applies symmetrically
   to writers: with `FinalElement == Never`, `finish` cannot be called, so the
   writer can be written to indefinitely but never explicitly terminated.
   Examples include logging sinks, metrics emitters, and continuous output
   streams.
 * **A custom payload type** lets the stream attach structured data to the
   close: HTTP trailers, a checksum, a frame's status code. An example is HTTP,
   which specializes `FinalElement` to `HTTPFields?` so the last DATA frame and
   the trailers can be fused into a single transport operation.

For readers, the terminal `read` call may also carry a final chunk of payload
elements alongside the end signal; the caller must process both. For writers,
`finish` is a consuming operation that delivers the `FinalElement` payload and
signals end-of-stream. `CallerAsyncWriter.finish(_:finalElement:)` also
carries the last elements, so the last elements and the terminator can be fused
into a single transport operation. `AsyncWriter.finish(finalElement:)` carries
only the terminator; conformers that can fuse may defer flushing the most
recent `write(_:)` until `finish` is called, achieving the same coalescing.

Convenience extensions on the writer protocols expose a closure-less `finish()`
when `FinalElement == Void`, so callers that don't need a custom payload can
omit the explicit `()` argument.

### Async span access for `Array`, `UniqueArray` and `InlineArray`

The following methods keep an `OutputSpan` or an `InputSpan` alive across
suspension points. They are marked `@_disfavoredOverload`, so that calls with a
synchronous closure keep picking the existing synchronous methods.

```swift
extension OutputSpan where Element: Copyable {
  /// Appends copies of all elements of `source` in a single memory copy.
  public mutating func append(copying source: Span<Element>)
}

extension OutputSpan where Element: ~Copyable {
  /// Moves as many elements from the front of `source` as fit into the free
  /// capacity, and returns their number.
  @discardableResult
  public mutating func append(moving source: inout InputSpan<Element>) -> Int
}

extension Array {
  /// Appends up to `uninitializedCount` elements by lending the free capacity
  /// to an asynchronous closure as an output span.
  public mutating func append<Return: ~Copyable, Failure: Error>(
    addingCapacity uninitializedCount: Int,
    initializingWith initializer: (inout OutputSpan<Element>) async throws(Failure) -> Return
  ) async throws(Failure) -> Return
}

extension Array where Element: BitwiseCopyable {
  /// Removes all elements, keeps the capacity, and lends the elements to an
  /// asynchronous closure as an input span.
  public mutating func consumeAll<Return: ~Copyable, Failure: Error>(
    consumingWith consumer: (inout InputSpan<Element>) async throws(Failure) -> Return
  ) async throws(Failure) -> Return
}

extension UniqueArray where Element: ~Copyable {
  public mutating func append<Return: ~Copyable, Failure: Error>(
    addingCount newItemCount: Int,
    initializingWith initializer: (inout OutputSpan<Element>) async throws(Failure) -> Return
  ) async throws(Failure) -> Return

  public mutating func consumeAll<Return: ~Copyable, Failure: Error>(
    consumingWith consumer: (inout InputSpan<Element>) async throws(Failure) -> Return
  ) async throws(Failure) -> Return
}

extension InlineArray where Element: ~Copyable {
  /// Creates an array whose elements an asynchronous closure appends to an
  /// output span. The closure must append exactly `count` elements.
  public init<Failure: Error>(
    initializingWith initializer: (inout OutputSpan<Element>) async throws(Failure) -> Void
  ) async throws(Failure)

  /// Consumes the array and lends its elements to an asynchronous closure as
  /// an input span.
  public consuming func consumeAll<Return: ~Copyable, Failure: Error>(
    consumingWith consumer: (inout InputSpan<Element>) async throws(Failure) -> Return
  ) async throws(Failure) -> Return
}
```

`Array.consumeAll` is limited to `BitwiseCopyable` elements. `Array` has no
method to give up its elements without deinitializing them, so it can only skip
the deinitialization of elements that don't need any. `InlineArray` moves its
elements to a heap allocation while it lends a span, since an async function
can't form a stable pointer to a local value across a suspension point.

### Bridging between `AsyncReader` and `AsyncSequence`

We provide extensions for converting between `AsyncReader` and `AsyncSequence`
in both directions. These require `Element: Copyable` since `AsyncSequence` does
not support noncopyable elements.

#### `AsyncReader` to `AsyncSequence`

```swift
extension AsyncReader where Self: ~Copyable, Self: ~Escapable, ReadElement: Copyable {
    /// Returns an `AsyncSequence` that yields the elements of this reader
    /// one at a time.
    public var asyncSequence: AsyncReaderSequence<Self> { get }
}

/// An `AsyncSequence` adapter over an `AsyncReader`.
public struct AsyncReaderSequence<
    Reader: AsyncReader & ~Copyable & ~Escapable
>: AsyncSequence where Reader.ReadElement: Copyable {
    public typealias Element = Reader.ReadElement
    public typealias Failure = Reader.ReadFailure

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
    public var asyncReader: AsyncSequenceReader<Self> { get }
}

/// An `AsyncReader` adapter over an `AsyncSequence`.
public struct AsyncSequenceReader<
    Base: AsyncSequence
>: AsyncReader {
    public typealias ReadElement = Base.Element
    public typealias ReadFailure = Base.Failure

    public mutating func read<Return: ~Copyable, Failure: Error>(
        maxCount: Int,
        body: (inout InputSpan<ReadElement>, consuming FinalElement?) async throws(Failure) -> Return
    ) async throws(EitherError<ReadFailure, Failure>) -> Return
}
```

These bridging types allow incremental adoption: existing `AsyncSequence`-based
APIs can be consumed by code expecting an `AsyncReader`, and new
`AsyncReader`-based APIs remain accessible to code that expects an
`AsyncSequence`.

## Source compatibility

This proposal is purely additive. It introduces new protocols, types, and
extensions without modifying any existing declarations.

The asynchronous span methods of `Array`, `UniqueArray` and `InlineArray` are
overloads of existing synchronous methods. They are disfavored, so existing
calls with a synchronous closure keep calling the synchronous methods, even in
an async context.

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

### Iteration and collection helpers

Two common patterns emerge immediately when working with `AsyncReader`:
iterating over all chunks until the stream ends, and collecting elements into
a caller-provided container. We envision convenience extensions for both, and
both surface the `FinalElement` payload to the caller:

```swift
extension AsyncReader where Self: ~Copyable, Self: ~Escapable, ReadElement: ~Copyable, FinalElement: ~Copyable {
    /// Calls `body` for each chunk of the stream that is not empty, until the
    /// reader signals end-of-stream.
    public consuming func forEachSpan<Failure: Error>(
        body: (inout InputSpan<ReadElement>) async throws(Failure) -> Void
    ) async throws(EitherError<ReadFailure, Failure>) -> FinalElement?

    /// Moves the elements of the stream into `target`, up to its free capacity.
    public consuming func collect(
        into target: inout OutputSpan<ReadElement>
    ) async throws(EitherError<ReadFailure, AsyncReaderLeftOverElementsError>) -> FinalElement

    /// Moves the elements of the stream into `target`, which the reader must
    /// fill exactly.
    public consuming func collect(
        exactlyInto target: inout OutputSpan<ReadElement>
    ) async throws(
        EitherError<ReadFailure, EitherError<AsyncReaderLeftOverElementsError, AsyncReaderInsufficientElementsError>>
    ) -> FinalElement

    /// Moves the elements of the stream into `target`, which grows by at most
    /// `maximumSize` elements.
    public consuming func collect<Container: DynamicContainer<ReadElement> & ~Copyable>(
        into target: inout Container,
        maximumSize: Int
    ) async throws(EitherError<ReadFailure, AsyncReaderLeftOverElementsError>) -> FinalElement
}
```

`forEachSpan` consumes an entire stream without manually looping over `read`
calls and threading the end signal. The `collect` overloads cover the common
ways to gather a stream's elements into existing storage: `collect(into:)`
fills the free capacity of an `OutputSpan`, `collect(exactlyInto:)` requires
the reader to match the free capacity (useful when parsing a known-length
frame), and `collect(into:maximumSize:)` grows a dynamic container with an
upper bound. Since the reader lends an `InputSpan`, `collect` moves the
elements and works for noncopyable elements too.

These helpers are intentionally excluded from this proposal because their
error-handling shapes (particularly `collect`'s nested `EitherError` and the
`AsyncReaderLeftOverElementsError` overflow behavior) benefit from real-world
usage feedback before stabilization.

### Piping a reader into a writer

A common pattern when bridging streams is piping all elements from a reader to
a writer. We envision convenience extensions on each reader protocol that
consume both sides and forward the elements — including the `FinalElement`
payload, fused with the writer's `finish` where the protocols allow it. All
variants move the elements, so they work for noncopyable elements, such as
leased buffers.

When the buffer ownership of the reader and writer aligns, the elements flow
directly between the two without an intermediate buffer:

```swift
extension AsyncReader where Self: ~Copyable, Self: ~Escapable, ReadElement: ~Copyable, FinalElement: ~Copyable {
    /// Hands each chunk to the writer, which takes ownership of the elements.
    public consuming func pipe<Writer: CallerAsyncWriter & ~Copyable>(
        into writer: consuming Writer
    ) async throws(EitherError<ReadFailure, Writer.WriteFailure>)
    where Writer.WriteElement == ReadElement, Writer.FinalElement == FinalElement
}

extension CallerAsyncReader where Self: ~Copyable, Self: ~Escapable, ReadElement: ~Copyable, FinalElement: ~Copyable {
    /// Reads directly into the output spans of the writer.
    public consuming func pipe<Writer: AsyncWriter & ~Copyable>(
        into writer: consuming Writer
    ) async throws(EitherError<Writer.WriteFailure, ReadFailure>)
    where Writer.WriteElement == ReadElement, Writer.FinalElement == FinalElement
}
```

The remaining combinations transfer the elements between two buffers. We
distinguish them with explicit argument labels so that the cost is visible at
the call site:

```swift
extension AsyncReader where Self: ~Copyable, Self: ~Escapable, ReadElement: ~Copyable, FinalElement: ~Copyable {
    /// Moves the elements from the reader's spans into the writer's output spans.
    public consuming func pipe<Writer: AsyncWriter & ~Copyable>(
        movingInto writer: consuming Writer
    ) async throws(EitherError<ReadFailure, Writer.WriteFailure>)
    where Writer.WriteElement == ReadElement, Writer.FinalElement == FinalElement
}

extension CallerAsyncReader where Self: ~Copyable, Self: ~Escapable, ReadElement: ~Copyable, FinalElement: ~Copyable {
    /// Reads into an intermediate buffer of the requested capacity and hands
    /// its elements to the writer.
    public consuming func pipe<Writer: CallerAsyncWriter & ~Copyable>(
        bufferingInto writer: consuming Writer,
        intermediateCapacity: Int
    ) async throws(EitherError<ReadFailure, Writer.WriteFailure>)
    where Writer.WriteElement == ReadElement, Writer.FinalElement == FinalElement
}
```

Like the iteration and collection helpers above, these are intentionally
excluded from the initial proposal so that their error-handling and fused-close
semantics can mature through real-world use before stabilization.

### Yielding spans

The callee-owned protocols lend their spans through closures, since the owner of
the memory has to run code once the caller is done with it: the reader destroys
the elements that the caller left and recycles its buffer, and the writer writes
the elements that the caller appended. Closures have known costs. They don't
compose with control flow such as `break` and `return`, they need `EitherError`
to keep the failures of the stream and of the body apart, and every closure-taking
API has to be updated for each new language feature, e.g. typed throws,
noncopyable return values, and `nonisolated(nonsending)`.

[Single-yield functions][single-yield] allow a function to yield a value to its
caller and to run cleanup code after the caller is done with it. The pitch lists
`async` single-yield functions as a future direction. With them, the reader
could yield its next chunk:

```swift
// Strawman
public struct AsyncReadChunk<Element: ~Copyable, FinalElement: ~Copyable>: ~Copyable, ~Escapable {
    public var elements: InputSpan<Element>
    public var finalElement: FinalElement?
}

protocol AsyncReader {
    mutating func read(maxCount: Int) async throws(ReadFailure) -> yield inout AsyncReadChunk<ReadElement, FinalElement>
}

// The chunk is a value in the caller's scope, and the bottom half of `read`
// runs once the caller is done with it.
let isFinal = (try await reader.read(maxCount: 4096)).finalElement != nil
```

The read side fits this model well. The top half of the coroutine suspends until
the data arrived, and the bottom half destroys the elements that were left and
recycles the buffer, which is synchronous and can't fail. It requires three
things:

1. `async` single-yield functions.
2. Single-yield functions as protocol requirements.
3. A fix for a compiler limitation: today the witness of an async protocol
   requirement can't return a `~Escapable` value that depends on `self` when
   `NonisolatedNonsendingByDefault` is enabled. A yielded span has the same
   dependence.

The write side doesn't fit as well. A writer would yield an `OutputSpan`, and
the bottom half of the coroutine has to write the elements that the caller
appended:

```swift
// Strawman
protocol AsyncWriter {
    mutating func write() async throws(WriteFailure) -> yield inout OutputSpan<WriteElement>
}
```

This bottom half is asynchronous and can fail, and the model has no good answer
to either:

1. **The bottom half suspends.** The end of the access becomes a suspension
   point that isn't marked with `await` in the caller's code.
2. **The bottom half throws.** The pitch doesn't allow a single-yield function
   to throw after it yielded, and the caller's code has no place where the error
   could surface. It would need an implicit `try` at the end of the access.
3. **The caller can fail while it holds the span.** The bottom half must not
   write a partly filled buffer when the caller throws. It needs to know
   whether the caller completed or threw, which single-yield functions don't
   tell it today.

Until single-yield functions support these, the write side needs a closure, or
an explicit commit step. A commit step only works with owned buffers: a buffer
that borrows the writer can't be passed back to the writer, since the commit
needs exclusive access to the writer while the buffer still borrows it. An owned
lease works today. A writer could lease a buffer to the caller, and the caller
hands it back through the `InputSpan` overload of `CallerAsyncWriter.write`.

The asynchronous span methods of `Array`, `UniqueArray` and `InlineArray` would
also become unnecessary. Their synchronous counterparts could yield their spans
instead of lending them to closures, and the caller could hold the yielded span
across its own suspension points:

```swift
// Strawman
extension Array {
    mutating func append(addingCapacity: Int) -> yield inout OutputSpan<Element>
}
```

### A currency type for leased buffers

This proposal moves leases as opaque noncopyable elements, but it doesn't define
a lease type. A shared lease type, e.g. a buffer of bytes that knows how to
return itself to its pool, would let I/O libraries and protocol implementations
exchange leased buffers without converting between their own types. Such a type
belongs with the I/O currency types rather than with the streaming protocols.

### Buffered readers

A reader destroys the elements that the body leaves, and parsers often don't
know how many elements a message needs before they looked at them. Rust's
`BufRead` and .NET's `PipeReader` keep the elements that were not consumed, and
deliver them again with the next read. A concrete buffered reader type that
wraps a caller-owned reader could provide this, together with methods to wait
for a minimum number of elements and to consume a prefix of them.

### Vectored I/O protocols (scatter/gather)

Operating systems provide scatter/gather I/O operations (`readv`/`writev` on
POSIX, `WSARecv`/`WSASend` on Windows) that read into or write from multiple
non-contiguous buffers in a single system call. This is important for network
interfaces that may have many separately allocated packets ready to deliver, or
for protocols that produce headers and payloads in separate buffers.

A vectored variant would operate on a collection of spans rather than a single
contiguous span. The central design challenge is **sizing**: how many span
entries can the collection hold?

 * A fixed-size inline array (e.g., `InlineArray<N, Span<Element>>`) avoids
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

### Omitting the `FinalElement` associated type

An earlier shape of this proposal had no `FinalElement` concept at all: the
read side signaled end-of-stream by returning an empty buffer; the write side
signaled it implicitly by deinitializing or consuming the writer. That design
is simpler to teach but fails on two fronts.

**It cannot express transports that deliver structured data with the close.**
Many real protocols attach a payload to the end-of-stream signal:

 * **HTTP** sends trailing fields after the last DATA frame, these are arbitrary
   header-like key/value pairs (checksums, signed digests, gRPC status) that
   are only available once the body has been transmitted. Without
   `FinalElement`, an HTTP body reader has no way to surface the trailers to
   its caller alongside the last chunk; the application would need a separate
   out-of-band channel.
 * **gRPC** carries the call's terminal status (OK / error code + message) in
   the trailers of every server-streaming response. The body protocol *must*
   be able to deliver that status to the caller.

These are not exotic edge cases, they are two of the most common streaming
transports a Swift server library will need to support.

**It cannot fuse the last write with the close signal.** HTTP/2, HTTP/3, and
QUIC all let the sender attach an END_STREAM flag to the same frame that
carries the final body bytes. Without an explicit `finish` operation that
takes both the last chunk and the terminator, the writer would have to emit
two separate transport operations: one `write` for the final bytes, and a
later deinit-driven close. That doubles the syscall / framing cost on the hot
path of every request and forfeits the kernel-side coalescing these protocols
were specifically designed to enable.

Defaulting `FinalElement` to `Void` keeps the trivial case ergonomic, a plain
file or byte-stream conformer needn't think about the associated type, while
making the HTTP- and gRPC-shaped use cases expressible at all.

### Container-based buffers instead of spans

An earlier shape of this proposal took generic `RangeReplaceableContainer`
buffers through an associated `Buffer` type on the callee-owned protocols and a
generic parameter on the caller-owned ones. That has real costs. Conformers had
to allocate or convert containers even when they already held the elements in
memory they own, every call site was generic over the container, and the
associated type leaked into the protocol's identity. Moving to spans removes the
associated type and the generic parameters. The protocols become non-generic in
their buffers, and I/O types read into and write from memory they already own.

A container could be consumed from, which made it possible to move elements out
of a reader. `InputSpan` keeps this capability without a container: the reader
lends its elements as an `InputSpan`, and the caller-owned writer accepts one.

### Lending a `Span` from the callee-owned reader

The callee-owned reader could lend a `Span` instead of an `InputSpan`. A `Span`
can view memory that the reader can't mutate, e.g. a read-only memory mapping of
a file or an immutable buffer that is shared with other readers, which an
`InputSpan` can't, since it deinitializes the elements that it gives up.

However, a `Span` only borrows its elements. A consumer could copy them, but it
couldn't take ownership of noncopyable elements, so leased buffers and other
move-only values could only be consumed in place. A stream delivers each element
exactly once, so handing over the elements matches what a read does, and the
`span` property of `InputSpan` keeps borrowing as simple as it was. A reader over
read-only memory has to copy the elements into memory that it owns, or provide a
separate method that lends a `Span`.

### Keeping the elements that the body leaves

The reader could keep the elements that the body leaves in the span and deliver
them again at the start of the next read, like Rust's `BufRead` and .NET's
`PipeReader`. This makes it easy to parse messages that are split across reads.
However, every conformer would have to store the elements that were left,
including in buffers that it would otherwise recycle right away, and the
protocol would need rules for when a read that delivers the same elements again
has to wait for new ones. A reader that drains its stream matches the `Drain`
protocol, and `maxCount` lets the body limit what it receives. Keeping elements
is better served by a concrete buffered reader, see [Buffered
readers](#buffered-readers).

### Separate protocols for owned buffers

An earlier shape of this proposal listed protocols for owned buffer transfer as a
future direction, e.g. a reader whose `read()` returns a buffer that the caller
owns. Since the elements of all four protocols can be noncopyable, and since the
span types move elements in both directions, a stream of leased buffers is a
stream whose elements are leases. Separate protocols would split the generic
algorithms, e.g. `pipe`, into one set per protocol family, and adapting a
leased reader to an owned reader would copy every element.

### Returning spans instead of using closures

The callee-owned read and write APIs use closures that receive a span, which
introduces the complexity of `EitherError`, since both the stream operation and
the closure can throw independent error types. It would be simpler to return a
span directly, or a chunk that holds a span and the final element.

A returned value can't run cleanup code once the caller is done with it, unless
it owns its memory and returns it in its `deinit`. That works for owned buffers,
but most readers want to recycle their buffer for the next read. A returned span
that borrows the reader prevents the next read while it is alive, which the
compiler enforces. However, an async protocol requirement that returns such a
span doesn't compile today when `NonisolatedNonsendingByDefault` is enabled. On
the write side, a returned span can't be committed back to the writer, since the
commit needs exclusive access to the writer while the span still borrows it.
[Single-yield functions][single-yield] are the more promising path, see
[Yielding spans](#yielding-spans).

### Naming the protocols after the iteration protocols

The standard library's iteration protocols use `Iterable` for a type whose
elements can be visited many times, and `BorrowingIteratorProtocol`, whose
`nextSpan(maxCount:)` method lends the next elements of one pass as a `Span`.
`ContainersPreview` adds `Producer`, whose `generate(into:)` method appends
elements to an `OutputSpan`, and `Drain`, whose `drainNext(maxCount:)` method
returns the next elements as an `InputSpan`. The read protocols of this proposal
have the same shapes: `AsyncReader` is an asynchronous `Drain`, and
`CallerAsyncReader` is an asynchronous `Producer`. We considered naming them
`AsyncDrain` and `AsyncProducer`, or naming the callee-owned reader
`AsyncIterable`.

We decided to keep the reader and writer names, and to align the contracts and
the vocabulary with the iteration protocols instead. The callee-owned reader
lends an `InputSpan`, takes a `maxCount`, and drains its stream with no way to put
elements back, like `Drain`. The caller-owned reader appends at least one element
unless the stream ended, like `Producer`.

1. `AsyncIterable` would be misleading. `Iterable` is borrowing and multi-pass,
   and its `makeBorrowingIterator()` method borrows `self`. A stream can be
   read only once.
2. An iterable/iterator split doesn't fit I/O types, see [Having split
   stream/iterator types](#having-split-streamiterator-types).
3. Writing has no counterpart in the iteration protocols. Reader and writer give
   the four protocols one family of names, and they are the terms that other
   ecosystems use for streaming I/O.

Renaming the read protocols to `AsyncDrain` and `AsyncProducer` wouldn't change
their shape, so this decision can be revisited if the iteration protocols settle
on a vocabulary that also covers writing.

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
adding an iterator split to some or all of the streaming protocols, e.g. an
iterable stream with a consuming method that returns a draining iterator. This
would be necessary if we chose to reparent `AsyncSequence` (see above).

I/O types are often lent rather than owned. For example, a connection lends its
read and write halves `inout` to a closure, so that it can close itself
afterwards. A consuming `makeIterator()` can't consume a value that is lent
`inout`. Protocol switches such as STARTTLS or an HTTP upgrade also need the
reader back after a part of the stream was read. A `mutating` read on the reader
itself covers both. Since we use bridging extensions instead of reparenting,
none of the four protocols need an iterator split, resulting in a simpler and
more uniform design.

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
cooperative. A cancelled read either throws without having consumed data, or
returns the data, and it never returns while the platform can still write into
the buffer. The closure-scoped design of the callee-owned protocols provides
compiler-enforced safety — the span types are `~Escapable`, so the compiler
ensures the borrowed memory cannot be stored beyond the closure scope. This is
stronger than Go's convention-based "must not retain p" and .NET's runtime-only
enforcement after `AdvanceTo`.

Rust's completion-based runtimes transfer the ownership of buffers through
traits of their own. In Swift, noncopyable elements and the `InputSpan` and
`OutputSpan` types transfer ownership through the same four protocols, so
readiness-based and completion-based I/O don't need separate abstractions.

The proposal's 2×2 matrix of {caller, callee} × {read, write} is unique among
these ecosystems. Go provides only caller-owned for both directions. .NET
Pipelines provides callee-owned for both directions (with a caller-owned write
convenience) but not caller-owned read as a first-class abstraction. The Swift
proposal provides all four combinations, informed by the observation that each
is optimal in distinct situations.

[SE-0298]: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0298-asyncsequence.md
[SE-0447]: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0447-span-access-shared-contiguous-storage.md
[SE-0461]: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md
[SE-0485]: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0485-outputspan.md
[input-span]: https://forums.swift.org/t/pitch-inputspan/90942
[single-yield]: https://forums.swift.org/t/pitch-single-yield-functions/90319
[async-pointers]: https://forums.swift.org/t/pitch-asynchronous-access-to-pointers-of-spans/91016
[containers-preview]: https://github.com/apple/swift-collections
