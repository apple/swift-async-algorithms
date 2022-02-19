//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

extension AsyncSequence {

  @inlinable
  public func chunks<Collected: RangeReplaceableCollection>(ofCount count: Int, collectedInto: Collected.Type) -> AsyncChunksOfCountSequence<Self, [Element]> where Collected.Element == Element {
    AsyncChunksOfCountSequence(self, count: count)
  }

  @inlinable
  public func chunks(ofCount count: Int) -> AsyncChunksOfCountSequence<Self, [Element]> {
    chunks(ofCount: count, collectedInto: [Element].self)
  }

  public func chunks<Trigger, Collected: RangeReplaceableCollection>(ofCount count: Int? = nil, delimitedBy trigger: Trigger, collectedInto: Collected.Type) -> AsyncChunksOfCountAndTriggerSequence<Self, Collected, Trigger> where Collected.Element == Element {
    AsyncChunksOfCountAndTriggerSequence(self, count: count, trigger: trigger)
  }

  public func chunks<Trigger>(ofCount count: Int? = nil, delimitedBy trigger: Trigger) -> AsyncChunksOfCountAndTriggerSequence<Self, [Element], Trigger> {
    chunks(ofCount: count, delimitedBy: trigger, collectedInto: [Element].self)
  }

#if false
  @inlinable
  public func chunks<C: Clock, Collected: RangeReplaceableCollection>(ofCount count: Int? = nil, delimitedBy timer: AsyncTimerSequence<C>, collectedInto: Collected.Type) -> AsyncChunksOfCountAndTriggerSequence<Self, Collected, AsyncTimerSequence<C>> where Collected.Element == Element {
    AsyncChunksOfCountAndTriggerSequence(self, count: count, trigger: timer)
  }

  @inlinable
  public func chunks<C: Clock>(ofCount count: Int? = nil, delimitedBy timer: AsyncTimerSequence<C>) -> AsyncChunksOfCountAndTriggerSequence<Self, [Element], AsyncTimerSequence<C>> {
    chunks(ofCount: count, delimitedBy: timer, collectedInto: [Element].self)
  }
#endif

  @inlinable
  public func chunked<Collected: RangeReplaceableCollection>(by belongInSameGroup: @escaping @Sendable (Element, Element) -> Bool, collectedInto: Collected.Type) -> AsyncChunkedByGroupSequence<Self, Collected> where Collected.Element == Element {
    AsyncChunkedByGroupSequence(self, grouping: belongInSameGroup)
  }

  @inlinable
  public func chunked(by belongInSameGroup: @escaping @Sendable (Element, Element) -> Bool) -> AsyncChunkedByGroupSequence<Self, [Element]> {
    chunked(by: belongInSameGroup, collectedInto: [Element].self)
  }

  @inlinable
  public func chunked<Subject : Equatable, Collected: RangeReplaceableCollection>(on projection: @escaping @Sendable (Element) -> Subject, collectedInto: Collected.Type) -> AsyncChunkedOnProjectionSequence<Self, Subject, Collected> {
    AsyncChunkedOnProjectionSequence(self, projection: projection)
  }

  @inlinable
  public func chunked<Subject : Equatable>(on projection: @escaping @Sendable (Element) -> Subject) -> AsyncChunkedOnProjectionSequence<Self, Subject, [Element]> {
    chunked(on: projection, collectedInto: [Element].self)
  }
}

public struct AsyncChunksOfCountAndTriggerSequence<Base: AsyncSequence, Collected: RangeReplaceableCollection, Trigger: AsyncSequence>: AsyncSequence where Collected.Element == Base.Element {
  public typealias Element = Collected

  enum ChunkEvent<Element> {
      case element(Element)
      case marker(Bool)
  }

  enum Intermediate<Collected: RangeReplaceableCollection> {
    case building(Collected)
    case built(Collected)
  }

  typealias InternalSequence = AsyncCompactMapSequence<
    AsyncExclusiveReductionsSequence<
      AsyncPrefixWhileSequence<
        AsyncMerge2Sequence<
          AsyncChain2Sequence<
            AsyncMapSequence<
              Base,
              ChunkEvent<Base.Element>>,
            AsyncLazySequence<[ChunkEvent<Base.Element>]>>,
          AsyncMapSequence<
            Trigger,
            ChunkEvent<Base.Element>>>>,
      Intermediate<Collected>>,
    Collected>

  public struct Iterator: AsyncIteratorProtocol {

    var _internal: InternalSequence.AsyncIterator

    init(_ iterator: InternalSequence.AsyncIterator) {
      self._internal = iterator
    }

    public mutating func next() async rethrows -> Collected? {
      try await _internal.next()
    }
  }

  let _internal : InternalSequence

  init(_ base: Base, count: Int?, trigger: Trigger) {
    if let count = count {
      precondition(count > 0)
    }

    let baseEvents = chain(base.map { ChunkEvent<Base.Element>.element($0) }, [ChunkEvent<Base.Element>.marker(false), ChunkEvent<Base.Element>.marker(true)].async)
    let triggerEvents = trigger.map { _ in ChunkEvent<Base.Element>.marker(false) }

    _internal = try! merge(baseEvents, triggerEvents).prefix(while: {
      switch $0 {
        case .marker(let terminal):
          return !terminal
        default:
          return true
      }
    }).reductions(into: Intermediate.building(Collected.init())) { result, either in
      switch either {
        case .element(let value):
          switch result {
            case .building(var elements):
              elements.append(value)
              if elements.count == count {
                result = .built(elements)
              } else {
                result = .building(elements)
              }
            case .built(_):
              var coll = Collected.init()
              coll.append(value)
              result = .building(coll)
          }
        case .marker:
          switch result {
            case .building(let elements):
              if (elements.count > 0) {
                result = .built(elements)
              }
            case .built(_):
              result = .building(Collected.init())
          }
      }
      print(result)
    }.compactMap { intermediate -> Collected? in
      switch intermediate {
        case .built(let elements):
          return elements
        default: return nil
      }
    }

  }

  public func makeAsyncIterator() -> Iterator {
    return Iterator(_internal.makeAsyncIterator())
  }
}

extension AsyncChunksOfCountAndTriggerSequence : Sendable where Base : Sendable, Base.Element : Sendable, Trigger : Sendable { }
extension AsyncChunksOfCountAndTriggerSequence.Iterator : Sendable where Base.AsyncIterator : Sendable, Trigger.AsyncIterator : Sendable { }
extension AsyncChunksOfCountAndTriggerSequence.ChunkEvent : Sendable where Element : Sendable { }
extension AsyncChunksOfCountAndTriggerSequence.Intermediate : Sendable where Collected : Sendable { }

public struct AsyncChunksOfCountSequence<Base: AsyncSequence, Collected: RangeReplaceableCollection>: AsyncSequence where Collected.Element == Base.Element {
  public typealias Element = Collected

  @frozen
  public struct Iterator: AsyncIteratorProtocol {

    @usableFromInline
    var base: Base.AsyncIterator

    @usableFromInline
    let count: Int

    @usableFromInline
    init(base: Base.AsyncIterator, count: Int) {
      self.base = base
      self.count = count
    }

    @inlinable
    public mutating func next() async rethrows -> Collected? {
      guard let first = try await base.next() else {
        return nil
      }

      var result: Collected = .init()
      result.append(first)

      while let next = try await base.next() {
        result.append(next)
        if result.count == count {
          break
        }
      }
      return result
    }
  }

  @usableFromInline
  let base : Base

  @usableFromInline
  let count : Int

  @inlinable
  init(_ base: Base, count: Int) {
    precondition(count > 0)
    self.base = base
    self.count = count
  }

  @inlinable
  public func makeAsyncIterator() -> Iterator {
    Iterator(base: base.makeAsyncIterator(), count: count)
  }
}

extension AsyncChunksOfCountSequence : Sendable where Base : Sendable, Base.Element : Sendable { }
extension AsyncChunksOfCountSequence.Iterator : Sendable where Base.AsyncIterator : Sendable, Base.Element : Sendable { }

public struct AsyncChunkedByGroupSequence<Base: AsyncSequence, Collected: RangeReplaceableCollection>: AsyncSequence where Collected.Element == Base.Element {
  public typealias Element = Collected

  @frozen
  public struct Iterator: AsyncIteratorProtocol {

    @usableFromInline
    var base: Base.AsyncIterator

    @usableFromInline
    let grouping: @Sendable (Base.Element, Base.Element) -> Bool

    @usableFromInline
    init(base: Base.AsyncIterator, grouping: @escaping @Sendable (Base.Element, Base.Element) -> Bool) {
      self.base = base
      self.grouping = grouping
    }

    @usableFromInline
    var hangingNext: Base.Element?

    @inlinable
    public mutating func next() async rethrows -> Collected? {
      var firstOpt = hangingNext
      if firstOpt == nil {
        firstOpt = try await base.next()
      } else {
        hangingNext = nil
      }
      
      guard let first = firstOpt else {
        return nil
      }

      var result: Collected = .init()
      result.append(first)

      var prev = first
      while let next = try await base.next() {
        if grouping(prev, next) {
          result.append(next)
          prev = next
        } else {
          hangingNext = next
          break
        }
      }
      return result
    }
  }

  @usableFromInline
  let base : Base

  @usableFromInline
  let grouping : @Sendable (Base.Element, Base.Element) -> Bool

  @inlinable
  init(_ base: Base, grouping: @escaping @Sendable (Base.Element, Base.Element) -> Bool) {
    self.base = base
    self.grouping = grouping
  }

  @inlinable
  public func makeAsyncIterator() -> Iterator {
    Iterator(base: base.makeAsyncIterator(), grouping: grouping)
  }
}

extension AsyncChunkedByGroupSequence : Sendable where Base : Sendable, Base.Element : Sendable { }
extension AsyncChunkedByGroupSequence.Iterator : Sendable where Base.AsyncIterator : Sendable, Base.Element : Sendable { }

public struct AsyncChunkedOnProjectionSequence<Base: AsyncSequence, Subject: Equatable, Collected: RangeReplaceableCollection>: AsyncSequence where Collected.Element == Base.Element {
  public typealias Element = (Subject, Collected)

  @frozen
  public struct Iterator: AsyncIteratorProtocol {

    @usableFromInline
    var base: Base.AsyncIterator

    @usableFromInline
    let projection: @Sendable (Base.Element) -> Subject

    @usableFromInline
    init(base: Base.AsyncIterator, projection: @escaping @Sendable (Base.Element) -> Subject) {
      self.base = base
      self.projection = projection
    }

    @usableFromInline
    var hangingNext: (Subject, Base.Element)?

    @inlinable
    public mutating func next() async rethrows -> (Subject, Collected)? {
      var firstOpt = hangingNext
      if firstOpt == nil {
        let nextOpt = try await base.next()
        if let next = nextOpt {
          firstOpt = (projection(next), next)
        }
      } else {
        hangingNext = nil
      }

      guard let first = firstOpt else {
        return nil
      }

      var result: Collected = .init()
      result.append(first.1)

      while let next = try await base.next() {
        let subj = projection(next)
        if subj == first.0 {
          result.append(next)
        } else {
          hangingNext = (subj, next)
          break
        }
      }
      return (first.0, result)
    }
  }

  @usableFromInline
  let base : Base

  @usableFromInline
  let projection : @Sendable (Base.Element) -> Subject

  @inlinable
  init(_ base: Base, projection: @escaping @Sendable (Base.Element) -> Subject) {
    self.base = base
    self.projection = projection
  }

  @inlinable
  public func makeAsyncIterator() -> Iterator {
    Iterator(base: base.makeAsyncIterator(), projection: projection)
  }
}

extension AsyncChunkedOnProjectionSequence : Sendable where Base : Sendable, Base.Element : Sendable { }
extension AsyncChunkedOnProjectionSequence.Iterator : Sendable where Base.AsyncIterator : Sendable, Base.Element : Sendable, Subject : Sendable { }

