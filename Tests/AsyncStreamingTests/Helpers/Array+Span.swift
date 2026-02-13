//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if UnstableAsyncStreaming
extension Array {
  init(_ span: Span<Element>) {
    self.init()
    for index in span.indices {
      self.append(span[index])
    }
  }

  mutating func append(span: Span<Element>) {
    for index in span.indices {
      self.append(span[index])
    }
  }
}
#endif
