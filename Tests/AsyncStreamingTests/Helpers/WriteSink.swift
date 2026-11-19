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

/// Records what a test writer received. `finish` and `pipe` consume the
/// writer, so tests read the results from here afterwards.
final class WriteSink<FinalElement: ~Copyable> {
  /// The values of every element written, in order, including those passed
  /// to `finish`.
  var values: [Int] = []
  /// How many times `write` completed (`finish` isn't counted).
  var writes = 0
  /// Whether `finish` was called.
  var finished = false
  /// The final element passed to `finish`.
  var finalElement: FinalElement? = nil
}
#endif
