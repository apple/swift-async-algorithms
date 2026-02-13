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
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension InlineArray where Element: ~Copyable {
  package static func one(value: consuming Element) -> InlineArray<1, Element> {
    return InlineArray<1, Element>(first: value) { _ in fatalError() }
  }

  package static func zero(of elementType: Element.Type = Element.self) -> InlineArray<0, Element> {
    return InlineArray<0, Element> { _ in }
  }
}
#endif
