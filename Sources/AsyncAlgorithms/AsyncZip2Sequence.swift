//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

/// Creates an asynchronous sequence that concurrently awaits values from two `AsyncSequence` types
/// and emits a tuple of the values.
public func zip<Base1: AsyncSequence, Base2: AsyncSequence>(_ base1: Base1, _ base2: Base2) -> AsyncZip2Sequence<Base1, Base2>
  where Base1: Sendable,
        Base2: Sendable,
        Base1.AsyncIterator: Sendable,
        Base2.AsyncIterator: Sendable,
        Base1.Element: Sendable,
        Base2.Element: Sendable {
  AsyncZip2Sequence(base1, base2)
}

/// An asynchronous sequence that concurrently awaits values from two `AsyncSequence` types
/// and emits a tuple of the values.
public struct AsyncZip2Sequence<Base1: AsyncSequence, Base2: AsyncSequence>: Sendable
  where Base1: Sendable,
        Base2: Sendable,
        Base1.AsyncIterator: Sendable,
        Base2.AsyncIterator: Sendable,
        Base1.Element: Sendable,
        Base2.Element: Sendable {
  let base1: Base1
  let base2: Base2
  
  init(_ base1: Base1, _ base2: Base2) {
    self.base1 = base1
    self.base2 = base2
  }
}

extension AsyncZip2Sequence: AsyncSequence {
  public typealias Element = (Base1.Element, Base2.Element)
  
  /// The iterator for an `AsyncZip2Sequence` instance.
  public struct Iterator: AsyncIteratorProtocol, Sendable {
    var base1: Base1.AsyncIterator?
    var base2: Base2.AsyncIterator?
    
    enum Partial: Sendable {
      case first(Result<Base1.Element?, Error>, Base1.AsyncIterator)
      case second(Result<Base2.Element?, Error>, Base2.AsyncIterator)
    }
    
    init(_ base1: Base1.AsyncIterator, _ base2: Base2.AsyncIterator) {
      self.base1 = base1
      self.base2 = base2
    }
    
    public mutating func next() async rethrows -> (Base1.Element, Base2.Element)? {
      func iteration(
        _ group: inout TaskGroup<Partial>,
        _ value1: inout Base1.Element?,
        _ value2: inout Base2.Element?,
        _ iterator1: inout Base1.AsyncIterator?,
        _ iterator2: inout Base2.AsyncIterator?
      ) async -> Result<(Base1.Element, Base2.Element)?, Error>? {
        guard let partial = await group.next() else {
          return .success(nil)
        }
        switch partial {
        case .first(let res, let iter):
          switch res {
          case .success(let value):
            if let value = value {
              value1 = value
              iterator1 = iter
              return nil
            } else {
              group.cancelAll()
              return .success(nil)
            }
          case .failure(let error):
            group.cancelAll()
            return .failure(error)
          }
        case .second(let res, let iter):
          switch res {
          case .success(let value):
            if let value = value {
              value2 = value
              iterator2 = iter
              return nil
            } else {
              group.cancelAll()
              return .success(nil)
            }
          case .failure(let error):
            group.cancelAll()
            return .failure(error)
          }
        }
      }
      
      guard let base1 = base1, let base2 = base2 else {
        return nil
      }
      
      let (result, iter1, iter2) = await withTaskGroup(of: Partial.self) { group -> (Result<(Base1.Element, Base2.Element)?, Error>, Base1.AsyncIterator?, Base2.AsyncIterator?) in
        group.addTask {
          var iterator = base1
          do {
            let value = try await iterator.next()
            return .first(.success(value), iterator)
          } catch {
            return .first(.failure(error), iterator)
          }
        }
        group.addTask {
          var iterator = base2
          do {
            let value = try await iterator.next()
            return .second(.success(value), iterator)
          } catch {
            return .second(.failure(error), iterator)
          }
        }
        var res1: Base1.Element?
        var res2: Base2.Element?
        var iter1: Base1.AsyncIterator?
        var iter2: Base2.AsyncIterator?
        
        if let result = await iteration(&group, &res1, &res2, &iter1, &iter2) {
          return (result, nil, nil)
        }
        if let result = await iteration(&group, &res1, &res2, &iter1, &iter2) {
          return (result, nil, nil)
        }
        guard let res1 = res1, let res2 = res2 else {
          return (.success(nil), nil, nil)
        }
        
        return (.success((res1, res2)), iter1, iter2)
      }
      do {
        guard let value = try result._rethrowGet() else {
          self.base1 = nil
          self.base2 = nil
          return nil
        }
        self.base1 = iter1
        self.base2 = iter2
        return value
      } catch {
        self.base1 = nil
        self.base2 = nil
        throw error
      }
    }
  }
  
  public func makeAsyncIterator() -> Iterator {
    Iterator(base1.makeAsyncIterator(), base2.makeAsyncIterator())
  }
}
