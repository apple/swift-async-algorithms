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
import MarbleDiagram
import AsyncAlgorithms

func sumCharacters(_ array: [String]) -> String {
  return "\(array.reduce(into: 0) { $0 = $0 + Int($1)! })"
}

func concatCharacters(_ array: [String]) -> String {
  return array.joined()
}

final class TestChunkSequence: XCTestCase {

  func test_signal_equalChunks() {
    marbleDiagram {
      "ABC-    DEF-    GHI-     |"
      "---X    ---X    ---X    |"
      $0.inputs[0].chunked(bySignal: $0.inputs[1]).map(concatCharacters)
      "---'ABC'---'DEF'---'GHI'|"
    }
  }

  func test_signal_unequalChunks() {
    marbleDiagram {
      "AB-   A-ABCDEFGH-         |"
      "--X   -X--------X         |"
      $0.inputs[0].chunked(bySignal: $0.inputs[1]).map(concatCharacters)
      "--'AB'-A--------'ABCDEFGH'|"
    }
  }

  func test_signal_emptyChunks() {
    marbleDiagram {
      "--1--|"
      "XX-XX|"
      $0.inputs[0].chunked(bySignal: $0.inputs[1]).map(concatCharacters)
      "---1-|"
    }
  }

  func test_signal_error() {
    marbleDiagram {
      "AB^"
      "---X|"
      $0.inputs[0].chunked(bySignal: $0.inputs[1]).map(concatCharacters)
      "--^"
    }
  }

  func test_signal_unsignaledTrailingChunk() {
    marbleDiagram {
      "111-111|"
      "---X---|"
      $0.inputs[0].chunked(bySignal: $0.inputs[1]).map(sumCharacters)
      "---3---[3|]"
    }
  }

  func test_signalAndCount_signalAlwaysPrevails() {
    marbleDiagram {
      "AB-   A-ABCDEFGH-         |"
      "--X   -X--------X         |"
      $0.inputs[0].chunked(byCount: 42, andSignal: $0.inputs[1]).map(concatCharacters)
      "--'AB'-A--------'ABCDEFGH'|"
    }
  }

  func test_signalAndCount_countAlwaysPrevails() {
    marbleDiagram {
      "AB   --A-B   -|"
      "--   X----   X|"
      $0.inputs[0].chunked(byCount: 2, andSignal: $0.inputs[1]).map(concatCharacters)
      "-'AB'----'AB'-|"
    }
  }

  func test_signalAndCount_countResetsAfterCount() {
    marbleDiagram {
      "ABCDE      -ABCDE      |"
      "-----      ------      |"
      $0.inputs[0].chunked(byCount: 5, andSignal: $0.inputs[1]).map(concatCharacters)
      "----'ABCDE'-----'ABCDE'|"
    }
  }

  func test_signalAndCount_countResetsAfterSignal() {
    marbleDiagram {
      "AB-   ABCDE      |"
      "--X   -----      |"
      $0.inputs[0].chunked(byCount: 5, andSignal: $0.inputs[1]).map(concatCharacters)
      "--'AB'----'ABCDE'|"
    }
  }

  func test_signalAndCount_error() {
    marbleDiagram {
      "ABC^"
      "----X|"
      $0.inputs[0].chunked(byCount: 5, andSignal: $0.inputs[1]).map(concatCharacters)
      "---^"
    }
  }

  func test_count() {
    marbleDiagram {
      "ABC    DEF    |"
      $0.inputs[0].chunks(ofCount: 3).map(concatCharacters)
      "--'ABC'--'DEF'|"
    }
  }

  func test_count_nonuniformTiming() {
    marbleDiagram {
      "A--B-C    --DE-F    |"
      $0.inputs[0].chunks(ofCount: 3).map(concatCharacters)
      "-----'ABC'-----'DEF'|"
    }
  }

  func test_count_trailingChunk() {
    marbleDiagram {
      "11111|"
      $0.inputs[0].chunks(ofCount: 3).map(sumCharacters)
      "--3--[2|]"
    }
  }

  func test_count_error() {
    marbleDiagram {
      "AB^"
      $0.inputs[0].chunks(ofCount: 3).map(concatCharacters)
      "--^"
    }
  }

  func test_group() {
    marbleDiagram {
      "ABC    def    GH   ij   Kl|"
      $0.inputs[0].chunked(by: { $0.first!.isUppercase == $1.first!.isUppercase }).map(concatCharacters)
      "---'ABC'--'def'-'GH'-'ij'K[l|]"
    }
  }

  func test_group_singleValue() {
    marbleDiagram {
      "A----|"
      $0.inputs[0].chunked(by: { $0.first!.isUppercase == $1.first!.isUppercase }).map(concatCharacters)
      "-----[A|]"
    }
  }

  func test_group_singleGroup() {
    marbleDiagram {
      "ABCDE|"
      $0.inputs[0].chunked(by: { _, _ in true }).map(concatCharacters)
      "-----['ABCDE'|]"
    }
  }

  func test_group_error() {
    marbleDiagram {
      "AB^"
      $0.inputs[0].chunked(by: { $0.first!.isUppercase == $1.first!.isUppercase }).map(concatCharacters)
      "--^"
    }
  }

  func test_projection() {
    marbleDiagram {
      "A'Aa''ab'    b'BB''bb'    'cc''CC'      |"
      $0.inputs[0].chunked(on: { $0.first!.lowercased() }).map { concatCharacters($0.1.map( {String($0.first!)} ) ) }
      "--   -   'AAa' -  -   'bBb'   -   ['cC'|]"
    }
  }

  func test_projection_singleValue() {
    marbleDiagram {
      "A----|"
      $0.inputs[0].chunked(on: { $0.first!.lowercased() }).map { concatCharacters($0.1.map( {String($0.first!)} ) ) }
      "-----[A|]"
    }
  }

  func test_projection_singleGroup() {
    marbleDiagram {
      "ABCDE|"
      $0.inputs[0].chunked(on: { _ in 42 }).map { concatCharacters($0.1.map( {String($0.first!)} ) ) }
      "-----['ABCDE'|]"
    }
  }

  func test_projection_error() {
    marbleDiagram {
      "Aa^"
      $0.inputs[0].chunked(on: { $0.first!.lowercased() }).map { concatCharacters($0.1.map( {String($0.first!)} ) ) }
      "--^"
    }
  }
}
