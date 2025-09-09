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
public typealias AsyncSequenceSendableMetatype = SendableMetatype & AsyncSequence
public typealias AsyncIteratorSendableMetatype = SendableMetatype & AsyncIteratorProtocol
#else
public typealias AsyncSequenceSendableMetatype = AsyncSequence
public typealias AsyncIteratorSendableMetatype = AsyncIteratorProtocol
#endif
