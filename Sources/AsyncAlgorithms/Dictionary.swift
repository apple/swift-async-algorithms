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

@available(AsyncAlgorithms 1.0, *)
extension Dictionary {
  /// Creates a new dictionary from the key-value pairs in the given asynchronous sequence.
  ///
  /// You use this initializer to create a dictionary when you have an asynchronous sequence
  /// of key-value tuples with unique keys. Passing an asynchronous sequence with duplicate
  /// keys to this initializer results in a runtime error. If your
  /// asynchronous sequence might have duplicate keys, use the
  /// `Dictionary(_:uniquingKeysWith:)` initializer instead.
  ///
  /// - Parameter keysAndValues: An asynchronous sequence of key-value pairs to use for
  ///   the new dictionary. Every key in `keysAndValues` must be unique.
  /// - Precondition: The sequence must not have duplicate keys.
  @available(AsyncAlgorithms 1.0, *)
  @inlinable
  public init<S: AsyncSequence>(uniqueKeysWithValues keysAndValues: S) async rethrows
  where S.Element == (Key, Value) {
    self.init(uniqueKeysWithValues: try await Array(keysAndValues))
  }

  /// Creates a new dictionary from the key-value pairs in the given asynchronous sequence,
  /// using a combining closure to determine the value for any duplicate keys.
  ///
  /// You use this initializer to create a dictionary when you have a sequence
  /// of key-value tuples that might have duplicate keys. As the dictionary is
  /// built, the initializer calls the `combine` closure with the current and
  /// new values for any duplicate keys. Pass a closure as `combine` that
  /// returns the value to use in the resulting dictionary: The closure can
  /// choose between the two values, combine them to produce a new value, or
  /// even throw an error.
  ///
  /// - Parameters:
  ///   - keysAndValues: An asynchronous sequence of key-value pairs to use for the new
  ///     dictionary.
  ///   - combine: A closure that is called with the values for any duplicate
  ///     keys that are encountered. The closure returns the desired value for
  ///     the final dictionary, or throws an error if building the dictionary
  ///     can't proceed.
  @available(AsyncAlgorithms 1.0, *)
  @inlinable
  public init<S: AsyncSequence>(
    _ keysAndValues: S,
    uniquingKeysWith combine: (Value, Value) async throws -> Value
  ) async rethrows where S.Element == (Key, Value) {
    self.init()
    for try await (key, value) in keysAndValues {
      if let existing = self[key] {
        self[key] = try await combine(existing, value)
      } else {
        self[key] = value
      }
    }
  }

  /// Creates a new dictionary whose keys are the groupings returned by the
  /// given closure and whose values are arrays of the elements that returned
  /// each key.
  ///
  /// The arrays in the "values" position of the new dictionary each contain at
  /// least one element, with the elements in the same order as the source
  /// asynchronous sequence.
  ///
  /// - Parameters:
  ///   - values: An asynchronous sequence of values to group into a dictionary.
  ///   - keyForValue: A closure that returns a key for each element in
  ///     `values`.
  @available(AsyncAlgorithms 1.0, *)
  @inlinable
  public init<S: AsyncSequence>(grouping values: S, by keyForValue: (S.Element) async throws -> Key) async rethrows
  where Value == [S.Element] {
    self.init()
    for try await value in values {
      let key = try await keyForValue(value)
      self[key, default: []].append(value)
    }
  }
}
