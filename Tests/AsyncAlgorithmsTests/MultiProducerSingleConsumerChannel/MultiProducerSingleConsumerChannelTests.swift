//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

import AsyncAlgorithms
import XCTest

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
final class MultiProducerSingleConsumerChannelTests: XCTestCase {
    // MARK: - sequenceDeinitialized

    // Following tests are disabled since the channel is not getting deinited due to a known bug

//    func testSequenceDeinitialized_whenNoIterator() async throws {
//        var channelAndStream: MultiProducerSingleConsumerChannel.ChannelAndStream! = MultiProducerSingleConsumerChannel.makeChannel(
//            of: Int.self,
//            backpressureStrategy: .watermark(low: 5, high: 10)
//        )
//        var channel: MultiProducerSingleConsumerChannel? = channelAndStream.channel
//        var source = channelAndStream.source
//        channelAndStream = nil
//
//        let (onTerminationStream, onTerminationContinuation) = AsyncStream<Void>.makeStream()
//        source.onTermination = {
//            onTerminationContinuation.finish()
//        }
//
//        await withThrowingTaskGroup(of: Void.self) { group in
//            group.addTask {
//                onTerminationContinuation.yield()
//                try await Task.sleep(for: .seconds(10))
//            }
//
//            var onTerminationIterator = onTerminationStream.makeAsyncIterator()
//            _ = await onTerminationIterator.next()
//
//            withExtendedLifetime(channel) {}
//            channel = nil
//
//            let terminationResult: Void? = await onTerminationIterator.next()
//            XCTAssertNil(terminationResult)
//
//            do {
//                _ = try { try source.send(2) }()
//                XCTFail("Expected an error to be thrown")
//            } catch {
//                XCTAssertTrue(error is MultiProducerSingleConsumerChannelAlreadyFinishedError)
//            }
//
//            group.cancelAll()
//        }
//    }
//
//    func testSequenceDeinitialized_whenIterator() async throws {
//        let channelAndStream = MultiProducerSingleConsumerChannel.makeChannel(
//            of: Int.self,
//            backpressureStrategy: .watermark(low: 5, high: 10)
//        )
//        var channel: MultiProducerSingleConsumerChannel? = channelAndStream.channel
//        var source = consume channelAndStream.source
//
//        var iterator = channel?.makeAsyncIterator()
//
//        let (onTerminationStream, onTerminationContinuation) = AsyncStream<Void>.makeStream()
//        source.onTermination = {
//            onTerminationContinuation.finish()
//        }
//
//        try await withThrowingTaskGroup(of: Void.self) { group in
//            group.addTask {
//                while !Task.isCancelled {
//                    onTerminationContinuation.yield()
//                    try await Task.sleep(for: .seconds(0.2))
//                }
//            }
//
//            var onTerminationIterator = onTerminationStream.makeAsyncIterator()
//            _ = await onTerminationIterator.next()
//
//            try withExtendedLifetime(channel) {
//                let writeResult = try source.send(1)
//                writeResult.assertIsProducerMore()
//            }
//
//            channel = nil
//
//            do {
//                let writeResult = try { try source.send(2) }()
//                writeResult.assertIsProducerMore()
//            } catch {
//                XCTFail("Expected no error to be thrown")
//            }
//
//            let element1 = await iterator?.next()
//            XCTAssertEqual(element1, 1)
//            let element2 = await iterator?.next()
//            XCTAssertEqual(element2, 2)
//
//            group.cancelAll()
//        }
//    }
//
//    func testSequenceDeinitialized_whenFinished() async throws {
//        let channelAndStream = MultiProducerSingleConsumerChannel.makeChannel(
//            of: Int.self,
//            backpressureStrategy: .watermark(low: 5, high: 10)
//        )
//        var channel: MultiProducerSingleConsumerChannel? = channelAndStream.channel
//        var source = consume channelAndStream.source
//
//        let (onTerminationStream, onTerminationContinuation) = AsyncStream<Void>.makeStream()
//        source.onTermination = {
//            onTerminationContinuation.finish()
//        }
//
//        await withThrowingTaskGroup(of: Void.self) { group in
//            group.addTask {
//                while !Task.isCancelled {
//                    onTerminationContinuation.yield()
//                    try await Task.sleep(for: .seconds(0.2))
//                }
//            }
//
//            var onTerminationIterator = onTerminationStream.makeAsyncIterator()
//            _ = await onTerminationIterator.next()
//
//            channel = nil
//
//            let terminationResult: Void? = await onTerminationIterator.next()
//            XCTAssertNil(terminationResult)
//            XCTAssertNil(channel)
//
//            group.cancelAll()
//        }
//    }
//
//    func testSequenceDeinitialized_whenChanneling_andSuspendedProducer() async throws {
//        let channelAndStream = MultiProducerSingleConsumerChannel.makeChannel(
//            of: Int.self,
//            backpressureStrategy: .watermark(low: 1, high: 2)
//        )
//        var channel: MultiProducerSingleConsumerChannel? = channelAndStream.channel
//        var source = consume channelAndStream.source
//
//        _ = try { try source.send(1) }()
//
//        do {
//            try await withCheckedThrowingContinuation { continuation in
//                source.send(1) { result in
//                    continuation.resume(with: result)
//                }
//
//                channel = nil
//                _ = channel?.makeAsyncIterator()
//            }
//        } catch {
//            XCTAssertTrue(error is MultiProducerSingleConsumerChannelAlreadyFinishedError)
//        }
//    }

    // MARK: - iteratorInitialized

    func testIteratorInitialized_whenInitial() async throws {
        let channelAndStream = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 5, high: 10)
        )
        let channel = channelAndStream.channel
        let source = consume channelAndStream.source

        _ = channel.makeAsyncIterator()
    }

    func testIteratorInitialized_whenChanneling() async throws {
        let channelAndStream = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 5, high: 10)
        )
        let channel = channelAndStream.channel
        var source = consume channelAndStream.source

        try await source.send(1)

        var iterator = channel.makeAsyncIterator()
        let element = await iterator.next()
        XCTAssertEqual(element, 1)
    }

    func testIteratorInitialized_whenSourceFinished() async throws {
        let channelAndStream = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 5, high: 10)
        )
        let channel = channelAndStream.channel
        var source = consume channelAndStream.source

        try await source.send(1)
        source.finish(throwing: nil)

        var iterator = channel.makeAsyncIterator()
        let element1 = await iterator.next()
        XCTAssertEqual(element1, 1)
        let element2 = await iterator.next()
        XCTAssertNil(element2)
    }

    func testIteratorInitialized_whenFinished() async throws {
        let channelAndStream = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 5, high: 10)
        )
        let channel = channelAndStream.channel
        let source = consume channelAndStream.source

        source.finish(throwing: nil)

        var iterator = channel.makeAsyncIterator()
        let element = await iterator.next()
        XCTAssertNil(element)
    }

    // MARK: - iteratorDeinitialized

    func testIteratorDeinitialized_whenInitial() async throws {
        let channelAndStream = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 5, high: 10)
        )
        let channel = channelAndStream.channel
        var source = consume channelAndStream.source

        let (onTerminationStream, onTerminationContinuation) = AsyncStream<Void>.makeStream()
        source.onTermination = {
            onTerminationContinuation.finish()
        }

        await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                while !Task.isCancelled {
                    onTerminationContinuation.yield()
                    try await Task.sleep(for: .seconds(0.2))
                }
            }

            var onTerminationIterator = onTerminationStream.makeAsyncIterator()
            _ = await onTerminationIterator.next()

            var iterator: MultiProducerSingleConsumerChannel<Int, Never>.AsyncIterator? = channel.makeAsyncIterator()
            iterator = nil
            _ = await iterator?.next()

            let terminationResult: Void? = await onTerminationIterator.next()
            XCTAssertNil(terminationResult)

            group.cancelAll()
        }
    }

    func testIteratorDeinitialized_whenChanneling() async throws {
        let channelAndStream = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 5, high: 10)
        )
        let channel = channelAndStream.channel
        var source = consume channelAndStream.source

        let (onTerminationStream, onTerminationContinuation) = AsyncStream<Void>.makeStream()
        source.onTermination = {
            onTerminationContinuation.finish()
        }

        try await source.send(1)

        await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                while !Task.isCancelled {
                    onTerminationContinuation.yield()
                    try await Task.sleep(for: .seconds(0.2))
                }
            }

            var onTerminationIterator = onTerminationStream.makeAsyncIterator()
            _ = await onTerminationIterator.next()

            var iterator: MultiProducerSingleConsumerChannel<Int, Never>.AsyncIterator? = channel.makeAsyncIterator()
            iterator = nil
            _ = await iterator?.next(isolation: nil)

            let terminationResult: Void? = await onTerminationIterator.next()
            XCTAssertNil(terminationResult)

            group.cancelAll()
        }
    }

    func testIteratorDeinitialized_whenSourceFinished() async throws {
        let channelAndStream = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 5, high: 10)
        )
        let channel = channelAndStream.channel
        var source = consume channelAndStream.source

        let (onTerminationStream, onTerminationContinuation) = AsyncStream<Void>.makeStream()
        source.onTermination = {
            onTerminationContinuation.finish()
        }

        try await source.send(1)
        source.finish(throwing: nil)

        await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                while !Task.isCancelled {
                    onTerminationContinuation.yield()
                    try await Task.sleep(for: .seconds(0.2))
                }
            }

            var onTerminationIterator = onTerminationStream.makeAsyncIterator()
            _ = await onTerminationIterator.next()

            var iterator: MultiProducerSingleConsumerChannel<Int, Never>.AsyncIterator? = channel.makeAsyncIterator()
            iterator = nil
            _ = await iterator?.next()

            let terminationResult: Void? = await onTerminationIterator.next()
            XCTAssertNil(terminationResult)

            group.cancelAll()
        }
    }

    func testIteratorDeinitialized_whenFinished() async throws {
        let channelAndStream = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            throwing: Error.self,
            backpressureStrategy: .watermark(low: 5, high: 10)
        )
        let channel = channelAndStream.channel
        var source = consume channelAndStream.source

        let (onTerminationStream, onTerminationContinuation) = AsyncStream<Void>.makeStream()
        source.onTermination = {
            onTerminationContinuation.finish()
        }

        source.finish(throwing: nil)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                while !Task.isCancelled {
                    onTerminationContinuation.yield()
                    try await Task.sleep(for: .seconds(0.2))
                }
            }

            var onTerminationIterator = onTerminationStream.makeAsyncIterator()
            _ = await onTerminationIterator.next()

            var iterator: MultiProducerSingleConsumerChannel<Int, Error>.AsyncIterator? = channel.makeAsyncIterator()
            iterator = nil
            _ = try await iterator?.next()

            let terminationResult: Void? = await onTerminationIterator.next()
            XCTAssertNil(terminationResult)

            group.cancelAll()
        }
    }

    func testIteratorDeinitialized_whenChanneling_andSuspendedProducer() async throws {
        let channelAndStream = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            throwing: Error.self,
            backpressureStrategy: .watermark(low: 5, high: 10)
        )
        var channel: MultiProducerSingleConsumerChannel? = channelAndStream.channel
        var source = consume channelAndStream.source

        var iterator: MultiProducerSingleConsumerChannel<Int, Error>.AsyncIterator? = channel?.makeAsyncIterator()
        channel = nil

        _ = try { try source.send(1) }()

        do {
            try await withCheckedThrowingContinuation { continuation in
                source.send(1) { result in
                    continuation.resume(with: result)
                }

                iterator = nil
            }
        } catch {
            XCTAssertTrue(error is MultiProducerSingleConsumerChannelAlreadyFinishedError)
        }

        _ = try await iterator?.next()
    }

    // MARK: - sourceDeinitialized

    func testSourceDeinitialized_whenSourceFinished() async throws {
        let channelAndStream = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            throwing: Error.self,
            backpressureStrategy: .watermark(low: 5, high: 10)
        )
        let channel = channelAndStream.channel
        var source: MultiProducerSingleConsumerChannel.Source? = consume channelAndStream.source

        let (onTerminationStream, onTerminationContinuation) = AsyncStream<Void>.makeStream()
        source?.onTermination = {
            onTerminationContinuation.finish()
        }

        try await source?.send(1)
        try await source?.send(2)
        source?.finish(throwing: nil)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                while !Task.isCancelled {
                    onTerminationContinuation.yield()
                    try await Task.sleep(for: .seconds(0.2))
                }
            }

            var onTerminationIterator = onTerminationStream.makeAsyncIterator()
            _ = await onTerminationIterator.next()

            var iterator: MultiProducerSingleConsumerChannel<Int, Error>.AsyncIterator? = channel.makeAsyncIterator()
            _ = try await iterator?.next()

            _ = await onTerminationIterator.next()

            _ = try await iterator?.next()
            _ = try await iterator?.next()

            let terminationResult: Void? = await onTerminationIterator.next()
            XCTAssertNil(terminationResult)

            group.cancelAll()
        }
    }

    func testSourceDeinitialized_whenFinished() async throws {
        let channelAndStream = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            throwing: Error.self,
            backpressureStrategy: .watermark(low: 5, high: 10)
        )
        let channel = channelAndStream.channel
        var source: MultiProducerSingleConsumerChannel.Source? = consume channelAndStream.source

        let (onTerminationStream, onTerminationContinuation) = AsyncStream<Void>.makeStream()
        source?.onTermination = {
            onTerminationContinuation.finish()
        }

        source?.finish(throwing: nil)

        await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                while !Task.isCancelled {
                    onTerminationContinuation.yield()
                    try await Task.sleep(for: .seconds(0.2))
                }
            }

            var onTerminationIterator = onTerminationStream.makeAsyncIterator()
            _ = await onTerminationIterator.next()

            _ = channel.makeAsyncIterator()

            _ = await onTerminationIterator.next()

            let terminationResult: Void? = await onTerminationIterator.next()
            XCTAssertNil(terminationResult)

            group.cancelAll()
        }
    }

    // MARK: - write

    func testWrite_whenInitial() async throws {
        let channelAndStream = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 2, high: 5)
        )
        let channel = channelAndStream.channel
        var source = consume channelAndStream.source

        try await source.send(1)

        var iterator = channel.makeAsyncIterator()
        let element = await iterator.next()
        XCTAssertEqual(element, 1)
    }

    func testWrite_whenChanneling_andNoConsumer() async throws {
        let channelAndStream = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 2, high: 5)
        )
        let channel = channelAndStream.channel
        var source = consume channelAndStream.source

        try await source.send(1)
        try await source.send(2)

        var iterator = channel.makeAsyncIterator()
        let element1 = await iterator.next()
        XCTAssertEqual(element1, 1)
        let element2 = await iterator.next()
        XCTAssertEqual(element2, 2)
    }

    func testWrite_whenChanneling_andSuspendedConsumer() async throws {
        let channelAndStream = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 2, high: 5)
        )
        let channel = channelAndStream.channel
        var source = consume channelAndStream.source

        try await withThrowingTaskGroup(of: Int?.self) { group in
            group.addTask {
                return await channel.first { _ in true }
            }

            // This is always going to be a bit racy since we need the call to next() suspend
            try await Task.sleep(for: .seconds(0.5))

            try await source.send(1)
            let element = try await group.next()
            XCTAssertEqual(element, 1)
        }
    }

    func testWrite_whenChanneling_andSuspendedConsumer_andEmptySequence() async throws {
        let channelAndStream = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 2, high: 5)
        )
        let channel = channelAndStream.channel
        var source = consume channelAndStream.source

        try await withThrowingTaskGroup(of: Int?.self) { group in
            group.addTask {
                return await channel.first { _ in true }
            }

            // This is always going to be a bit racy since we need the call to next() suspend
            try await Task.sleep(for: .seconds(0.5))

            try await source.send(contentsOf: [])
            try await source.send(contentsOf: [1])
            let element = try await group.next()
            XCTAssertEqual(element, 1)
        }
    }

    // MARK: - enqueueProducer

    func testEnqueueProducer_whenChanneling_andAndCancelled() async throws {
        let channelAndStream = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 1, high: 2)
        )
        let channel = channelAndStream.channel
        var source = consume channelAndStream.source

        let (producerStream, producerSource) = AsyncThrowingStream<Void, Error>.makeStream()

        try await source.send(1)

        let writeResult = try { try source.send(2) }()

        switch consume writeResult {
        case .produceMore:
            preconditionFailure()
        case .enqueueCallback(let callbackToken):
            source.cancelCallback(callbackToken: callbackToken)

            source.enqueueCallback(callbackToken: callbackToken) { result in
                producerSource.yield(with: result)
            }
        }

        do {
            _ = try await producerStream.first { _ in true }
            XCTFail("Expected an error to be thrown")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        let element = await channel.first { _ in true }
        XCTAssertEqual(element, 1)
    }

    func testEnqueueProducer_whenChanneling_andAndCancelled_andAsync() async throws {
        let channelAndStream = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 1, high: 2)
        )
        let channel = channelAndStream.channel
        var source = consume channelAndStream.source

        try await source.send(1)

        await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await source.send(2)
            }

            group.cancelAll()
            do {
                try await group.next()
                XCTFail("Expected an error to be thrown")
            } catch {
                XCTAssertTrue(error is CancellationError)
            }
        }

        let element = await channel.first { _ in true }
        XCTAssertEqual(element, 1)
    }

    func testEnqueueProducer_whenChanneling_andInterleaving() async throws {
        let channelAndStream = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 1, high: 1)
        )
        let channel = channelAndStream.channel
        var source = consume channelAndStream.source
        var iterator = channel.makeAsyncIterator()

        let (producerStream, producerSource) = AsyncThrowingStream<Void, Error>.makeStream()

        let writeResult = try { try source.send(1) }()

        switch writeResult {
        case .produceMore:
            preconditionFailure()
        case .enqueueCallback(let callbackToken):
            let element = await iterator.next()
            XCTAssertEqual(element, 1)

            source.enqueueCallback(callbackToken: callbackToken) { result in
                producerSource.yield(with: result)
            }
        }

        do {
            _ = try await producerStream.first { _ in true }
        } catch {
            XCTFail("Expected no error to be thrown")
        }
    }

    func testEnqueueProducer_whenChanneling_andSuspending() async throws {
        let channelAndStream = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 1, high: 1)
        )
        let channel = channelAndStream.channel
        var source = consume channelAndStream.source
        var iterator = channel.makeAsyncIterator()

        let (producerStream, producerSource) = AsyncThrowingStream<Void, Error>.makeStream()

        let writeResult = try { try source.send(1) }()

        switch writeResult {
        case .produceMore:
            preconditionFailure()
        case .enqueueCallback(let callbackToken):
            source.enqueueCallback(callbackToken: callbackToken) { result in
                producerSource.yield(with: result)
            }
        }

        let element = await iterator.next()
        XCTAssertEqual(element, 1)

        do {
            _ = try await producerStream.first { _ in true }
        } catch {
            XCTFail("Expected no error to be thrown")
        }
    }

    // MARK: - cancelProducer

    func testCancelProducer_whenChanneling() async throws {
        let channelAndStream = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 1, high: 2)
        )
        let channel = channelAndStream.channel
        var source = consume channelAndStream.source

        let (producerStream, producerSource) = AsyncThrowingStream<Void, Error>.makeStream()

        try await source.send(1)

        let writeResult = try { try source.send(2) }()

        switch writeResult {
        case .produceMore:
            preconditionFailure()
        case .enqueueCallback(let callbackToken):
            source.enqueueCallback(callbackToken: callbackToken) { result in
                producerSource.yield(with: result)
            }

            source.cancelCallback(callbackToken: callbackToken)
        }

        do {
            _ = try await producerStream.first { _ in true }
            XCTFail("Expected an error to be thrown")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        let element = await channel.first { _ in true }
        XCTAssertEqual(element, 1)
    }

    // MARK: - finish

    func testFinish_whenChanneling_andConsumerSuspended() async throws {
        let channelAndStream = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 1, high: 1)
        )
        let channel = channelAndStream.channel
        var source: MultiProducerSingleConsumerChannel.Source? = consume channelAndStream.source

        try await withThrowingTaskGroup(of: Int?.self) { group in
            group.addTask {
                return await channel.first { $0 == 2 }
            }

            // This is always going to be a bit racy since we need the call to next() suspend
            try await Task.sleep(for: .seconds(0.5))

            source?.finish(throwing: nil)
            source = nil

            let element = try await group.next()
            XCTAssertEqual(element, .some(nil))
        }
    }

    func testFinish_whenInitial() async throws {
        let channelAndStream = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            throwing: Error.self,
            backpressureStrategy: .watermark(low: 1, high: 1)
        )
        let channel = channelAndStream.channel
        var source = consume channelAndStream.source

        source.finish(throwing: CancellationError())

        do {
            for try await _ in channel {}
            XCTFail("Expected an error to be thrown")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

    }

    // MARK: - Backpressure

    func testBackpressure() async throws {
        let channelAndStream = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 2, high: 4)
        )
        let channel = channelAndStream.channel
        var source = consume channelAndStream.source

        let (backpressureEventStream, backpressureEventContinuation) = AsyncStream.makeStream(of: Void.self)

        await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                while true {
                    backpressureEventContinuation.yield(())
                    try await source.send(contentsOf: [1])
                }
            }

            var backpressureEventIterator = backpressureEventStream.makeAsyncIterator()
            var iterator = channel.makeAsyncIterator()

            await backpressureEventIterator.next()
            await backpressureEventIterator.next()
            await backpressureEventIterator.next()
            await backpressureEventIterator.next()

            _ = await iterator.next()
            _ = await iterator.next()
            _ = await iterator.next()

            await backpressureEventIterator.next()
            await backpressureEventIterator.next()
            await backpressureEventIterator.next()

            group.cancelAll()
        }
    }

    func testBackpressureSync() async throws {
        let channelAndStream = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 2, high: 4)
        )
        let channel = channelAndStream.channel
        var source = consume channelAndStream.source

        let (backpressureEventStream, backpressureEventContinuation) = AsyncStream.makeStream(of: Void.self)

        await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                while true {
                    backpressureEventContinuation.yield(())
                    try await withCheckedThrowingContinuation { continuation in
                        source.send(contentsOf: [1]) { result in
                            continuation.resume(with: result)
                        }
                    }
                }
            }

            var backpressureEventIterator = backpressureEventStream.makeAsyncIterator()
            var iterator = channel.makeAsyncIterator()

            await backpressureEventIterator.next()
            await backpressureEventIterator.next()
            await backpressureEventIterator.next()
            await backpressureEventIterator.next()

            _ = await iterator.next()
            _ = await iterator.next()
            _ = await iterator.next()

            await backpressureEventIterator.next()
            await backpressureEventIterator.next()
            await backpressureEventIterator.next()

            group.cancelAll()
        }
    }

    func testWatermarkWithCustomCoount() async throws {
        let channelAndStream = MultiProducerSingleConsumerChannel.makeChannel(
            of: [Int].self,
            backpressureStrategy: .watermark(low: 2, high: 4, waterLevelForElement: { $0.count })
        )
        let channel = channelAndStream.channel
        var source = consume channelAndStream.source
        var iterator = channel.makeAsyncIterator()

        try await source.send([1, 1, 1])

        _ = await iterator.next()

        try await source.send([1, 1, 1])

        _ = await iterator.next()
    }

    func testWatermarWithLotsOfElements() async throws {
        // This test should in the future use a custom task executor to schedule to avoid sending
        // 1000 elements.
        let channelAndStream = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 2, high: 4)
        )
        let channel = channelAndStream.channel
        var source: MultiProducerSingleConsumerChannel.Source! = consume channelAndStream.source
        await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                var source = source.take()!
                for i in 0...10000 {
                    try await source.send(i)
                }
                source.finish()
            }

            group.addTask {
                var sum = 0
                for try await element in channel {
                    sum += element
                }
            }
        }
    }

    func testThrowsError() async throws {
        let channelAndStream = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            throwing: Error.self,
            backpressureStrategy: .watermark(low: 2, high: 4)
        )
        let channel = channelAndStream.channel
        var source = consume channelAndStream.source

        try await source.send(1)
        try await source.send(2)
        source.finish(throwing: CancellationError())

        var elements = [Int]()
        var iterator = channel.makeAsyncIterator()

        do {
            while let element = try await iterator.next() {
                elements.append(element)
            }
            XCTFail("Expected an error to be thrown")
        } catch {
            XCTAssertTrue(error is CancellationError)
            XCTAssertEqual(elements, [1, 2])
        }

        let element = try await iterator.next()
        XCTAssertNil(element)
    }

    func testAsyncSequenceWrite() async throws {
        let (stream, continuation) = AsyncStream<Int>.makeStream()
        let channelAndStream = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 2, high: 4)
        )
        let channel = channelAndStream.channel
        var source = consume channelAndStream.source

        continuation.yield(1)
        continuation.yield(2)
        continuation.finish()

        try await source.send(contentsOf: stream)
        source.finish(throwing: nil)

        let elements = await channel.collect()
        XCTAssertEqual(elements, [1, 2])
    }

    // MARK: NonThrowing

    func testNonThrowing() async throws {
        let channelAndStream = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 2, high: 4)
        )
        let channel = channelAndStream.channel
        var source = consume channelAndStream.source

        let (backpressureEventStream, backpressureEventContinuation) = AsyncStream.makeStream(of: Void.self)

        await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                while true {
                    backpressureEventContinuation.yield(())
                    try await source.send(contentsOf: [1])
                }
            }

            var backpressureEventIterator = backpressureEventStream.makeAsyncIterator()
            var iterator = channel.makeAsyncIterator()

            await backpressureEventIterator.next()
            await backpressureEventIterator.next()
            await backpressureEventIterator.next()
            await backpressureEventIterator.next()

            _ = await iterator.next()
            _ = await iterator.next()
            _ = await iterator.next()

            await backpressureEventIterator.next()
            await backpressureEventIterator.next()
            await backpressureEventIterator.next()

            group.cancelAll()
        }
    }
}

extension AsyncSequence {
    /// Collect all elements in the sequence into an array.
    fileprivate func collect() async rethrows -> [Element] {
        try await self.reduce(into: []) { accumulated, next in
            accumulated.append(next)
        }
    }
}

extension MultiProducerSingleConsumerChannel.Source.SendResult {
    func assertIsProducerMore() {
        switch self {
        case .produceMore:
            return ()

        case .enqueueCallback:
            XCTFail("Expected produceMore")
        }
    }

    func assertIsEnqueueCallback() {
        switch self {
        case .produceMore:
            XCTFail("Expected enqueueCallback")

        case .enqueueCallback:
            return ()
        }
    }
}

extension Optional where Wrapped: ~Copyable {
    fileprivate mutating func take() -> Self {
        let result = consume self
        self = nil
        return result
    }
}
