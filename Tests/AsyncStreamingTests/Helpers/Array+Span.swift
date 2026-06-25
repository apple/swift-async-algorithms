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

extension Array {
  init(_ span: Span<Element>) {
    self.init()
    for index in span.indices {
      self.append(span[index])
    }
  }

  init(_ inputSpan: borrowing InputSpan<Element>) {
    self.init()
    for index in inputSpan.indices {
      self.append(inputSpan[index])
    }
  }

  init<C: RangeReplaceableContainer<Element> & ~Copyable & ~Escapable>(draining container: inout C) {
    self.init()
    var consumer = container.consumeAll()
    while let value = consumer.next() {
      self.append(value)
    }
  }

  mutating func append(span: Span<Element>) {
    for index in span.indices {
      self.append(span[index])
    }
  }

  mutating func append(inputSpan: borrowing InputSpan<Element>) {
    for index in inputSpan.indices {
      self.append(inputSpan[index])
    }
  }
}
#endif
