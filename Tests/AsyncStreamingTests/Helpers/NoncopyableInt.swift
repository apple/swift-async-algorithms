//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if UnstableAsyncStreaming && compiler(>=6.4)
import BasicContainers
import ContainersPreview

/// The element type the AsyncStreaming tests use: a noncopyable wrapper around
/// an `Int`, so the tests always cover noncopyable elements.
struct NoncopyableInt: ~Copyable {
  let value: Int

  init(_ value: Int) {
    self.value = value
  }
}

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
extension UniqueArray where Element == NoncopyableInt {
  /// Creates an array holding a ``NoncopyableInt`` for each of `values`.
  init(values: [Int]) {
    self.init(minimumCapacity: values.count)
    for value in values {
      self.append(NoncopyableInt(value))
    }
  }

  /// The wrapped values, in order.
  var values: [Int] {
    var result: [Int] = []
    for index in self.indices {
      result.append(self[index].value)
    }
    return result
  }
}

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
extension RigidArray where Element == NoncopyableInt {
  /// The wrapped values, in order.
  var values: [Int] {
    var result: [Int] = []
    for index in self.indices {
      result.append(self[index].value)
    }
    return result
  }
}

extension Array where Element == Int {
  /// Removes every element from `container` and collects their wrapped values.
  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  init<Container: RangeReplaceableContainer<NoncopyableInt> & ~Copyable & ~Escapable>(
    drainingValues container: inout Container
  ) where Container.Element: ~Copyable {
    self.init()
    var consumer = container.consumeAll()
    while let element = consumer.next() {
      self.append(element.value)
    }
  }
}
#endif
