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

import XCTest

#if canImport(Darwin) || canImport(Glibc) || canImport(Musl) || canImport(Bionic) || canImport(wasi_pthread)

import AsyncSequenceValidation
import AsyncAlgorithms

@Sendable
func sumCharacters(_ array: [String]) -> String {
  return "\(array.reduce(into: 0) { $0 = $0 + Int($1)! })"
}

@Sendable
func concatCharacters(_ array: [String]) -> String {
  return array.joined()
}

final class TestChunk: XCTestCase {
  func test_count_one() {
    validate {
      "ABCDE|"
      $0.inputs[0].chunks(ofCount: 1).map(concatCharacters)
      "ABCDE|"
    }
  }

  func test_signal_equalChunks() {
    validate {
      "ABC-    DEF-    GHI-     |"
      "---X    ---X    ---X    |"
      $0.inputs[0].chunked(by: $0.inputs[1]).map(concatCharacters)
      "---'ABC'---'DEF'---'GHI'|"
    }
  }

  func test_signal_unequalChunks() {
    validate {
      "AB-   A-ABCDEFGH-         |"
      "--X   -X--------X         |"
      $0.inputs[0].chunked(by: $0.inputs[1]).map(concatCharacters)
      "--'AB'-A--------'ABCDEFGH'|"
    }
  }

  func test_signal_emptyChunks() {
    validate {
      "--1--|"
      "XX-XX|"
      $0.inputs[0].chunked(by: $0.inputs[1]).map(concatCharacters)
      "---1-|"
    }
  }

  func test_signal_error() {
    validate {
      "AB^"
      "---X|"
      $0.inputs[0].chunked(by: $0.inputs[1]).map(concatCharacters)
      "--^"
    }
  }

  func test_signal_unsignaledTrailingChunk() {
    validate {
      "111-111|"
      "---X---|"
      $0.inputs[0].chunked(by: $0.inputs[1]).map(sumCharacters)
      "---3---[3|]"
    }
  }

  func test_signalAndCount_signalAlwaysPrevails() {
    validate {
      "AB-   A-ABCDEFGH-         |"
      "--X   -X--------X         |"
      $0.inputs[0].chunks(ofCount: 42, or: $0.inputs[1]).map(concatCharacters)
      "--'AB'-A--------'ABCDEFGH'|"
    }
  }

  func test_signalAndCount_countAlwaysPrevails() {
    validate {
      "AB   --A-B   -|"
      "--   X----   X|"
      $0.inputs[0].chunks(ofCount: 2, or: $0.inputs[1]).map(concatCharacters)
      "-'AB'----'AB'-|"
    }
  }

  func test_signalAndCount_countResetsAfterCount() {
    validate {
      "ABCDE      -ABCDE      |"
      "-----      ------      |"
      $0.inputs[0].chunks(ofCount: 5, or: $0.inputs[1]).map(concatCharacters)
      "----'ABCDE'-----'ABCDE'|"
    }
  }

  func test_signalAndCount_countResetsAfterSignal() {
    validate {
      "AB-   ABCDE      |"
      "--X   -----      |"
      $0.inputs[0].chunks(ofCount: 5, or: $0.inputs[1]).map(concatCharacters)
      "--'AB'----'ABCDE'|"
    }
  }

  func test_signalAndCount_error() {
    validate {
      "ABC^"
      "----X|"
      $0.inputs[0].chunks(ofCount: 5, or: $0.inputs[1]).map(concatCharacters)
      "---^"
    }
  }

  func test_time_equalChunks() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }
    validate {
      "ABC-    DEF-    GHI-     |"
      $0.inputs[0].chunked(by: .repeating(every: .steps(4), clock: $0.clock)).map(concatCharacters)
      "---'ABC'---'DEF'---'GHI'|"
    }
  }

  func test_time_unequalChunks() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }
    validate {
      "AB------    A------- ABCDEFG-         |"
      $0.inputs[0].chunked(by: .repeating(every: .steps(8), clock: $0.clock)).map(concatCharacters)
      "-------'AB' -------A -------'ABCDEFG'|"
    }
  }

  func test_time_emptyChunks() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }
    validate {
      "-- 1- --|"
      $0.inputs[0].chunked(by: .repeating(every: .steps(2), clock: $0.clock)).map(concatCharacters)
      "-- -1 --|"
    }
  }

  func test_time_error() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }
    validate {
      "AB^"
      $0.inputs[0].chunked(by: .repeating(every: .steps(5), clock: $0.clock)).map(concatCharacters)
      "--^"
    }
  }

  func test_time_unsignaledTrailingChunk() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }
    validate {
      "111-111|"
      $0.inputs[0].chunked(by: .repeating(every: .steps(4), clock: $0.clock)).map(sumCharacters)
      "---3---[3|]"
    }
  }

  func test_timeAndCount_timeAlwaysPrevails() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }
    validate {
      "AB------    A------- ABCDEFG-         |"
      $0.inputs[0].chunks(ofCount: 42, or: .repeating(every: .steps(8), clock: $0.clock)).map(concatCharacters)
      "-------'AB' -------A -------'ABCDEFG'|"
    }
  }

  func test_timeAndCount_countAlwaysPrevails() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }
    validate {
      "AB   --A-B   -|"
      $0.inputs[0].chunks(ofCount: 2, or: .repeating(every: .steps(8), clock: $0.clock)).map(concatCharacters)
      "-'AB'----'AB'-|"
    }
  }

  func test_timeAndCount_countResetsAfterCount() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }
    validate {
      "ABCDE      --- ABCDE      |"
      $0.inputs[0].chunks(ofCount: 5, or: .repeating(every: .steps(8), clock: $0.clock)).map(concatCharacters)
      "----'ABCDE'--- ----'ABCDE'|"
    }
  }

  func test_timeAndCount_countResetsAfterSignal() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }
    validate {
      "AB------    ABCDE      |"
      $0.inputs[0].chunks(ofCount: 5, or: .repeating(every: .steps(8), clock: $0.clock)).map(concatCharacters)
      "-------'AB' ----'ABCDE'|"
    }
  }

  func test_timeAndCount_error() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }
    validate {
      "ABC^"
      $0.inputs[0].chunks(ofCount: 5, or: .repeating(every: .steps(8), clock: $0.clock)).map(concatCharacters)
      "---^"
    }
  }

  func test_count() {
    validate {
      "ABC    DEF    |"
      $0.inputs[0].chunks(ofCount: 3).map(concatCharacters)
      "--'ABC'--'DEF'|"
    }
  }

  func test_count_nonuniformTiming() {
    validate {
      "A--B-C    --DE-F    |"
      $0.inputs[0].chunks(ofCount: 3).map(concatCharacters)
      "-----'ABC'-----'DEF'|"
    }
  }

  func test_count_trailingChunk() {
    validate {
      "11111|"
      $0.inputs[0].chunks(ofCount: 3).map(sumCharacters)
      "--3--[2|]"
    }
  }

  func test_count_error() {
    validate {
      "AB^"
      $0.inputs[0].chunks(ofCount: 3).map(concatCharacters)
      "--^"
    }
  }

  func test_group() {
    validate {
      "ABC    def    GH   ij   Kl|"
      $0.inputs[0].chunked(by: { $0.first!.isUppercase == $1.first!.isUppercase }).map(concatCharacters)
      "---'ABC'--'def'-'GH'-'ij'K[l|]"
    }
  }

  func test_group_singleValue() {
    validate {
      "A----|"
      $0.inputs[0].chunked(by: { $0.first!.isUppercase == $1.first!.isUppercase }).map(concatCharacters)
      "-----[A|]"
    }
  }

  func test_group_singleGroup() {
    validate {
      "ABCDE|"
      $0.inputs[0].chunked(by: { _, _ in true }).map(concatCharacters)
      "-----['ABCDE'|]"
    }
  }

  func test_group_error() {
    validate {
      "AB^"
      $0.inputs[0].chunked(by: { $0.first!.isUppercase == $1.first!.isUppercase }).map(concatCharacters)
      "--^"
    }
  }

  func test_projection() {
    validate {
      "A'Aa''ab'    b'BB''bb'    'cc''CC'      |"
      $0.inputs[0].chunked(on: { $0.first!.lowercased() }).map {
        concatCharacters($0.1.map({ String($0.first!) }))
      }
      "--   -   'AAa' -  -   'bBb'   -   ['cC'|]"
    }
  }

  func test_projection_singleValue() {
    validate {
      "A----|"
      $0.inputs[0].chunked(on: { $0.first!.lowercased() }).map {
        concatCharacters($0.1.map({ String($0.first!) }))
      }
      "-----[A|]"
    }
  }

  func test_projection_singleGroup() {
    validate {
      "ABCDE|"
      $0.inputs[0].chunked(on: { _ in 42 }).map { concatCharacters($0.1.map({ String($0.first!) })) }
      "-----['ABCDE'|]"
    }
  }

  func test_projection_error() {
    validate {
      "Aa^"
      $0.inputs[0].chunked(on: { $0.first!.lowercased() }).map {
        concatCharacters($0.1.map({ String($0.first!) }))
      }
      "--^"
    }
  }
}

#endif
