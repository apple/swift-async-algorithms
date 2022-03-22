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

/// Creates an asynchronous sequence that concurrently awaits values from three `AsyncSequence` types
/// and emits a tuple of the values.
public func zip<Base1: AsyncSequence, Base2: AsyncSequence, Base3: AsyncSequence>(_ base1: Base1, _ base2: Base2, _ base3: Base3) -> AsyncZip3Sequence<Base1, Base2, Base3>
  where Base1: Sendable,
        Base2: Sendable,
        Base3: Sendable,
        Base1.AsyncIterator: Sendable,
        Base2.AsyncIterator: Sendable,
        Base3.AsyncIterator: Sendable,
        Base1.Element: Sendable,
        Base2.Element: Sendable,
        Base3.Element: Sendable {
  AsyncZip3Sequence(base1, base2, base3)
}

/// An asynchronous sequence that concurrently awaits values from three `AsyncSequence` types
/// and emits a tuple of the values.
public struct AsyncZip3Sequence<Base1: AsyncSequence, Base2: AsyncSequence, Base3: AsyncSequence>: Sendable
  where Base1: Sendable,
        Base2: Sendable,
        Base3: Sendable,
        Base1.AsyncIterator: Sendable,
        Base2.AsyncIterator: Sendable,
        Base3.AsyncIterator: Sendable,
        Base1.Element: Sendable,
        Base2.Element: Sendable,
        Base3.Element: Sendable {
  let base1: Base1
  let base2: Base2
  let base3: Base3
  
  init(_ base1: Base1, _ base2: Base2, _ base3: Base3) {
    self.base1 = base1
    self.base2 = base2
    self.base3 = base3
  }
}

extension AsyncZip3Sequence: AsyncSequence {
  public typealias Element = (Base1.Element, Base2.Element, Base3.Element)
  
  /// The iterator for an `AsyncZip3Sequence` instance.
  public struct Iterator: AsyncIteratorProtocol, Sendable {
    var base1: Base1.AsyncIterator?
    var base2: Base2.AsyncIterator?
    var base3: Base3.AsyncIterator?
    
    enum Partial: Sendable {
      case first(Result<Base1.Element?, Error>, Base1.AsyncIterator)
      case second(Result<Base2.Element?, Error>, Base2.AsyncIterator)
      case third(Result<Base3.Element?, Error>, Base3.AsyncIterator)
    }
    
    init(_ base1: Base1.AsyncIterator, _ base2: Base2.AsyncIterator, _ base3: Base3.AsyncIterator) {
      self.base1 = base1
      self.base2 = base2
      self.base3 = base3
    }
    
    public mutating func next() async rethrows -> (Base1.Element, Base2.Element, Base3.Element)? {
      func iteration(
        _ group: inout TaskGroup<Partial>,
        _ value1: inout Base1.Element?,
        _ value2: inout Base2.Element?,
        _ value3: inout Base3.Element?,
        _ iterator1: inout Base1.AsyncIterator?,
        _ iterator2: inout Base2.AsyncIterator?,
        _ iterator3: inout Base3.AsyncIterator?
      ) async -> Result<(Base1.Element, Base2.Element, Base3.Element)?, Error>? {
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
        case .third(let res, let iter):
          switch res {
          case .success(let value):
            if let value = value {
              value3 = value
              iterator3 = iter
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
      
      guard let base1 = base1, let base2 = base2, let base3 = base3 else {
        return nil
      }
      
      let (result, iter1, iter2, iter3) = await withTaskGroup(of: Partial.self) { group -> (Result<(Base1.Element, Base2.Element, Base3.Element)?, Error>, Base1.AsyncIterator?, Base2.AsyncIterator?, Base3.AsyncIterator?) in
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
        group.addTask {
          var iterator = base3
          do {
            let value = try await iterator.next()
            return .third(.success(value), iterator)
          } catch {
            return .third(.failure(error), iterator)
          }
        }
        var res1: Base1.Element?
        var res2: Base2.Element?
        var res3: Base3.Element?
        var iter1: Base1.AsyncIterator?
        var iter2: Base2.AsyncIterator?
        var iter3: Base3.AsyncIterator?
        
        if let result = await iteration(&group, &res1, &res2, &res3, &iter1, &iter2, &iter3) {
          return (result, nil, nil, nil)
        }
        if let result = await iteration(&group, &res1, &res2, &res3, &iter1, &iter2, &iter3) {
          return (result, nil, nil, nil)
        }
        if let result = await iteration(&group, &res1, &res2, &res3, &iter1, &iter2, &iter3) {
          return (result, nil, nil, nil)
        }
        guard let res1 = res1, let res2 = res2, let res3 = res3 else {
          return (.success(nil), nil, nil, nil)
        }
        
        return (.success((res1, res2, res3)), iter1, iter2, iter3)
      }
      do {
        guard let value = try result._rethrowGet() else {
          self.base1 = nil
          self.base2 = nil
          self.base3 = nil
          return nil
        }
        self.base1 = iter1
        self.base2 = iter2
        self.base3 = iter3
        return value
      } catch {
        self.base1 = nil
        self.base2 = nil
        self.base3 = nil
        throw error
      }
    }
  }
  
  public func makeAsyncIterator() -> Iterator {
    Iterator(base1.makeAsyncIterator(), base2.makeAsyncIterator(), base3.makeAsyncIterator())
  }
}
