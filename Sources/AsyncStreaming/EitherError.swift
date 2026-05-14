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

#if UnstableAsyncStreaming && compiler(>=6.4)
/// A type-safe wrapper around one of two distinct error types.
///
/// Use ``EitherError`` when an operation can fail with errors from two
/// different sources, such as a read failure and a body closure failure.
@frozen
public enum EitherError<First: Error, Second: Error>: Error {
  /// An error of the first type.
  case first(First)

  /// An error of the second type.
  case second(Second)

  /// Throws the underlying error, unwrapping this ``EitherError``.
  ///
  /// This method extracts and throws the contained error,
  /// whether it's the first or second type. Use this when you need to propagate
  /// the original error without the ``EitherError`` wrapper.
  ///
  /// - Throws: The underlying error, either of type `First` or `Second`.
  ///
  /// ## Example
  ///
  /// ```swift
  /// do {
  ///     let result = try await operation()
  /// } catch let eitherError as EitherError<NetworkError, ParseError> {
  ///     try eitherError.unwrap()
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

extension EitherError: Equatable where First: Equatable, Second: Equatable {}
extension EitherError: Hashable where First: Hashable, Second: Hashable {}
#endif
