//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if compiler(>=6.2)
@available(AsyncAlgorithms 1.1, *)
public typealias AsyncSequenceSendableMetatype = SendableMetatype & AsyncSequence
@available(AsyncAlgorithms 1.1, *)
public typealias AsyncIteratorSendableMetatype = SendableMetatype & AsyncIteratorProtocol
#else
@available(AsyncAlgorithms 1.1, *)
public typealias AsyncSequenceSendableMetatype = AsyncSequence
@available(AsyncAlgorithms 1.1, *)
public typealias AsyncIteratorSendableMetatype = AsyncIteratorProtocol
#endif
