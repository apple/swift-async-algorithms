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

#if compiler(>=6.3)
import Testing
import AsyncAlgorithms

@Suite struct ContinuationTests {
    @Test func continuationTrapsIfDropped() async throws {
        try await #expect(processExitsWith: .failure) {
            try await withContinuation(of: Void.self) { continuation in
                _ = consume continuation
            }
        }
    }

    @Test func continuationDoesNotDropIfRetained() async throws {
        try await withContinuation(of: Void.self) { continuation in
            continuation.resume()
        }
    }
}
#endif
