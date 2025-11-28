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
    
    // Explicitly specify the type of the stream
    return AsyncThrowingStream<T.Element, Error> { continuation in
      let state = ManagedCriticalState(FlatMapLatestState())
      
      let outerTask = Task {
        do {
          for try await element in self {
            let innerSequence = transform(element)
            
            // Increment generation and get the new value
            let currentGeneration = state.withCriticalRegion { state -> Int in
              state.innerTask?.cancel()
              state.generation += 1
              return state.generation
            }
            
            let innerTask = Task {
              do {
                for try await innerElement in innerSequence {
                  // Check if we are still the latest generation
                  let shouldYield = state.withCriticalRegion { state in
                    state.generation == currentGeneration
                  }
                  
                  if shouldYield {
                    continuation.yield(innerElement)
                  } else {
                    // If we are not the latest, we should stop
                    return
                  }
                }
              } catch is CancellationError {
                // Normal cancellation
              } catch {
                // If an error occurs, we only propagate it if we are the latest generation
                let shouldPropagate = state.withCriticalRegion { state in
                  state.generation == currentGeneration
                }
                if shouldPropagate {
                  continuation.finish(throwing: error)
                }
              }
            }
            
            state.withCriticalRegion { state in
              // Only update the inner task if the generation hasn't changed again
              if state.generation == currentGeneration {
                state.innerTask = innerTask
              }
            }
          }
          
          // Outer sequence finished
          // Wait for the last inner task to finish
          let lastInnerTask = state.withCriticalRegion { $0.innerTask }
          _ = await lastInnerTask?.result
          continuation.finish()
          
        } catch {
          continuation.finish(throwing: error)
        }
      }
      
      continuation.onTermination = { @Sendable _ in
        outerTask.cancel()
        state.withCriticalRegion { state in
          state.innerTask?.cancel()
        }
      }
    }
  }
}

@available(AsyncAlgorithms 1.0, *)
private struct FlatMapLatestState: Sendable {
  var generation: Int = 0
  var innerTask: Task<Void, Never>? = nil
}
