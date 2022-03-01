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

// For moving values across tasks where the value will never be consumed elsewhere
struct Envelope<Contents>: @unchecked Sendable {
  var contents: Contents
  
  init(_ contents: Contents) {
    self.contents = contents
  }
}
