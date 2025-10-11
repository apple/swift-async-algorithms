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

/// A backportable protocol / hack to allow `Failure` associated type on older iOS/macOS/etc. versions.
///
/// By assigning this protocol to any value conforming to `AsyncSequence`, they will both have access to `Failure`
/// > There could be a possible issue with mangled name of the entire object as discussed
/// [here](https://forums.swift.org/t/how-to-use-asyncsequence-on-macos-14-5-in-xcode-16-beta-need-help-with-availability-check-since-failure-is-unavailb-e/72439/5).
/// However, the issue should only happen if the object conforming to this protocol follows (_Concurrency, AsyncSequence)
/// in lexicographic order. (AsyncAlgorithms, MySequence) should always be after it.
///
/// Example:
/// ```swift
/// class MySequence: AsyncSequence, FailableAsyncSequence { ... }
///
/// ```
@available(AsyncAlgorithms 1.1, *)
public protocol FailableAsyncSequence {
  typealias _Failure = Failure
  associatedtype Failure: Error
}
