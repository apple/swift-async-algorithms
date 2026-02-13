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

#if UnstableAsyncStreaming
/// An enumeration that represents one of two possible error types.
///
/// ``EitherError`` provides a type-safe way to represent errors that can be one of two distinct
/// error types.
public enum EitherError<First: Error, Second: Error>: Error {
  /// An error of the first type.
  ///
  /// The associated value contains the specific error instance of type `First`.
  case first(First)

  /// An error of the second type.
  ///
  /// The associated value contains the specific error instance of type `Second`.
  case second(Second)

  /// Throws the underlying error by unwrapping this either error.
  ///
  /// This method extracts and throws the actual error contained within the either error,
  /// whether it's the first or second type. This is useful when you need to propagate
  /// the original error without the either error wrapper.
  ///
  /// - Throws: The underlying error, either of type `First` or `Second`.
  ///
  /// ## Example
  ///
  /// ```swift
  /// do {
  ///     // Some operation that returns EitherError
  ///     let result = try await operation()
  /// } catch let eitherError as EitherError<NetworkError, ParseError> {
  ///     try eitherError.unwrap() // Throws the original error
  /// }
  /// ```
  public func unwrap() throws {
    switch self {
    case .first(let first):
      throw first
    case .second(let second):
      throw second
    }
  }
}
#endif
