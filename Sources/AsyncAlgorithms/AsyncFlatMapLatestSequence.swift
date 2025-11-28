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

import Foundation

@available(AsyncAlgorithms 1.0, *)
extension AsyncSequence where Self: Sendable {
  
  /// Transforms elements into new asynchronous sequences, emitting elements
  /// from the most recent inner sequence.
  ///
  /// When a new element is emitted by this sequence, the `transform`
  /// is called to produce a new inner sequence. Iteration on the
  /// previous inner sequence is cancelled, and iteration begins
  /// on the new one.
  public func flatMapLatest<T: AsyncSequence & Sendable>(
    _ transform: @escaping @Sendable (Element) -> T
  ) -> AsyncThrowingStream<T.Element, Error>
  where T.Element: Sendable {
    
    AsyncThrowingStream { continuation in
      let outerIterationTask = Task {
        var innerIterationTask: Task<Void, Never>? = nil
        
        do {
          for try await element in self {
            innerIterationTask?.cancel()
            
            let innerSequence = transform(element)
            
            innerIterationTask = Task {
              do {
                for try await innerElement in innerSequence {
                  try Task.checkCancellation()
                  continuation.yield(innerElement)
                }
              } catch is CancellationError {
                // Inner task was cancelled, this is normal
              } catch {
                // Inner sequence threw an error
                continuation.finish(throwing: error)
              }
            }
          }
        } catch {
          // Outer sequence threw an error
          continuation.finish(throwing: error)
        }
        
        // Outer sequence finished
        await innerIterationTask?.value
        continuation.finish()
      }
      
      continuation.onTermination = { @Sendable _ in
        outerIterationTask.cancel()
      }
    }
  }
}
