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
    // MARK: - sourceDeinitialized
    
    func testSourceDeinitialized_whenChanneling_andNoSuspendedConsumer() async throws {
        let manualExecutor = ManualTaskExecutor()
        try await withThrowingTaskGroup { group in
            let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
                of: Int.self,
                backpressureStrategy: .watermark(low: 5, high: 10)
            )
            var channel = consume channelAndSource.channel
            let source = consume channelAndSource.source
            
            nonisolated(unsafe) var didTerminate = false
            source.setOnTerminationCallback {
                didTerminate = true
            }
            
            group.addTask(executorPreference: manualExecutor) {
                await channel.next()
            }
            
            withExtendedLifetime(source) { }
            _ = consume source
            XCTAssertFalse(didTerminate)
            manualExecutor.run()
            _ = try await group.next()
            XCTAssertTrue(didTerminate)
        }
    }
    
    func testSourceDeinitialized_whenChanneling_andSuspendedConsumer() async throws {
        let manualExecutor = ManualTaskExecutor()
        try await withThrowingTaskGroup { group in
            let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
                of: Int.self,
                backpressureStrategy: .watermark(low: 5, high: 10)
            )
            var channel = channelAndSource.channel
            let source = consume channelAndSource.source
            nonisolated(unsafe) var didTerminate = false
            source.setOnTerminationCallback {
                didTerminate = true
            }
            
            group.addTask(executorPreference: manualExecutor) {
                await channel.next()
            }
            manualExecutor.run()
            XCTAssertFalse(didTerminate)
            
            withExtendedLifetime(source) { }
            _ = consume source
            XCTAssertTrue(didTerminate)
            manualExecutor.run()
            _ = try await group.next()
        }
    }
    
    func testSourceDeinitialized_whenMultipleSources() async throws {
        let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 2, high: 4)
        )
        var channel = consume channelAndSource.channel
        var source1 = consume channelAndSource.source
        var source2 = source1.copy()
        nonisolated(unsafe) var didTerminate = false
        source1.setOnTerminationCallback {
            didTerminate = true
        }

        _ = try await source1.send(1)
        XCTAssertFalse(didTerminate)
        _ = consume source1
        XCTAssertFalse(didTerminate)
        _ = try await source2.send(2)
        XCTAssertFalse(didTerminate)

        _ = await channel.next()
        XCTAssertFalse(didTerminate)
        _ = await channel.next()
        XCTAssertFalse(didTerminate)
        _ = consume source2
        _ = await channel.next()
        XCTAssertTrue(didTerminate)
    }
    
    func testSourceDeinitialized_whenSourceFinished() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
                of: Int.self,
                throwing: Error.self,
                backpressureStrategy: .watermark(low: 5, high: 10)
            )
            let channel = channelAndSource.channel
            var source: MultiProducerSingleConsumerChannel.Source? = consume channelAndSource.source

            let (onTerminationStream, onTerminationContinuation) = AsyncStream<Void>.makeStream()
            source?.setOnTerminationCallback {
                onTerminationContinuation.finish()
            }

            try await source?.send(1)
            try await source?.send(2)
            source?.finish(throwing: nil)
            
            group.addTask {
                while !Task.isCancelled {
                    onTerminationContinuation.yield()
                    try await Task.sleep(for: .seconds(0.2))
                }
            }

            var onTerminationIterator = onTerminationStream.makeAsyncIterator()
            _ = await onTerminationIterator.next()

            var iterator = Optional.some(channel.asyncSequence().makeAsyncIterator())
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
        await withThrowingTaskGroup(of: Void.self) { group in
            let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
                of: Int.self,
                throwing: Error.self,
                backpressureStrategy: .watermark(low: 5, high: 10)
            )
            let channel = channelAndSource.channel
            let source: MultiProducerSingleConsumerChannel.Source? = consume channelAndSource.source

            let (onTerminationStream, onTerminationContinuation) = AsyncStream<Void>.makeStream()
            source?.setOnTerminationCallback {
                onTerminationContinuation.finish()
            }

            source?.finish(throwing: nil)
            
            group.addTask {
                while !Task.isCancelled {
                    onTerminationContinuation.yield()
                    try await Task.sleep(for: .seconds(0.2))
                }
            }

            var onTerminationIterator = onTerminationStream.makeAsyncIterator()
            _ = await onTerminationIterator.next()

            _ = channel.asyncSequence().makeAsyncIterator()

            _ = await onTerminationIterator.next()

            let terminationResult: Void? = await onTerminationIterator.next()
            XCTAssertNil(terminationResult)

            group.cancelAll()
        }
    }
    
    // MARK: Channel deinitialized
    
    func testChannelDeinitialized() async throws {
        let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 5, high: 10)
        )
        let channel = channelAndSource.channel
        let source = consume channelAndSource.source
        nonisolated(unsafe) var didTerminate = false
        source.setOnTerminationCallback { didTerminate = true }
        
        XCTAssertFalse(didTerminate)
        _ = consume channel
        XCTAssertTrue(didTerminate)
    }
    
    // MARK: - sequenceDeinitialized
    
    func testSequenceDeinitialized_whenChanneling_andNoSuspendedConsumer() async throws {
        let manualExecutor = ManualTaskExecutor()
        try await withThrowingTaskGroup { group in
            let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
                of: Int.self,
                backpressureStrategy: .watermark(low: 5, high: 10)
            )
            let channel = channelAndSource.channel
            let asyncSequence = channel.asyncSequence()
            let source = consume channelAndSource.source
            nonisolated(unsafe) var didTerminate = false
            source.setOnTerminationCallback { didTerminate = true }
            
            group.addTask(executorPreference: manualExecutor) {
                await asyncSequence.first { _ in true }
            }
            
            withExtendedLifetime(source) { }
            _ = consume source
            XCTAssertFalse(didTerminate)
            manualExecutor.run()
            _ = try await group.next()
            XCTAssertTrue(didTerminate)
        }
    }
    
    func testSequenceDeinitialized_whenChanneling_andSuspendedConsumer() async throws {
        let manualExecutor = ManualTaskExecutor()
        try await withThrowingTaskGroup(of: Void.self) { group in
            let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
                of: Int.self,
                backpressureStrategy: .watermark(low: 5, high: 10)
            )
            let channel = channelAndSource.channel
            let asyncSequence = channel.asyncSequence()
            let source = consume channelAndSource.source
            nonisolated(unsafe) var didTerminate = false
            source.setOnTerminationCallback { didTerminate = true }
            
            group.addTask(executorPreference: manualExecutor) {
                _ = await asyncSequence.first { _ in true }
            }
            manualExecutor.run()
            XCTAssertFalse(didTerminate)
            
            withExtendedLifetime(source) { }
            _ = consume source
            XCTAssertTrue(didTerminate)
            manualExecutor.run()
            _ = try await group.next()
        }
    }

    // MARK: - iteratorInitialized

    func testIteratorInitialized_whenInitial() async throws {
        let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 5, high: 10)
        )
        let channel = channelAndSource.channel
        _ = consume channelAndSource.source

        _ = channel.asyncSequence().makeAsyncIterator()
    }

    func testIteratorInitialized_whenChanneling() async throws {
        let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 5, high: 10)
        )
        let channel = channelAndSource.channel
        var source = consume channelAndSource.source

        try await source.send(1)

        var iterator = channel.asyncSequence().makeAsyncIterator()
        let element = await iterator.next(isolation: nil)
        XCTAssertEqual(element, 1)
    }

    func testIteratorInitialized_whenSourceFinished() async throws {
        let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 5, high: 10)
        )
        let channel = channelAndSource.channel
        var source = consume channelAndSource.source

        try await source.send(1)
        source.finish(throwing: nil)

        var iterator = channel.asyncSequence().makeAsyncIterator()
        let element1 = await iterator.next(isolation: nil)
        XCTAssertEqual(element1, 1)
        let element2 = await iterator.next(isolation: nil)
        XCTAssertNil(element2)
    }

    func testIteratorInitialized_whenFinished() async throws {
        let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 5, high: 10)
        )
        let channel = channelAndSource.channel
        let source = consume channelAndSource.source

        source.finish(throwing: nil)

        var iterator = channel.asyncSequence().makeAsyncIterator()
        let element = await iterator.next(isolation: nil)
        XCTAssertNil(element)
    }

    // MARK: - iteratorDeinitialized

    func testIteratorDeinitialized_whenInitial() async throws {
        await withThrowingTaskGroup(of: Void.self) { group in
            let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
                of: Int.self,
                backpressureStrategy: .watermark(low: 5, high: 10)
            )
            let channel = channelAndSource.channel
            let source = consume channelAndSource.source

            let (onTerminationStream, onTerminationContinuation) = AsyncStream<Void>.makeStream()
            source.setOnTerminationCallback {
                onTerminationContinuation.finish()
            }
            
            group.addTask {
                while !Task.isCancelled {
                    onTerminationContinuation.yield()
                    try await Task.sleep(for: .seconds(0.2))
                }
            }

            var onTerminationIterator = onTerminationStream.makeAsyncIterator()
            _ = await onTerminationIterator.next()

            var iterator = Optional.some(channel.asyncSequence().makeAsyncIterator())
            iterator = nil
            _ = await iterator?.next(isolation: nil)

            let terminationResult: Void? = await onTerminationIterator.next()
            XCTAssertNil(terminationResult)

            group.cancelAll()
        }
    }

    func testIteratorDeinitialized_whenChanneling() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
                of: Int.self,
                backpressureStrategy: .watermark(low: 5, high: 10)
            )
            let channel = channelAndSource.channel
            var source = consume channelAndSource.source

            let (onTerminationStream, onTerminationContinuation) = AsyncStream<Void>.makeStream()
            source.setOnTerminationCallback {
                onTerminationContinuation.finish()
            }

            try await source.send(1)
            
            group.addTask {
                while !Task.isCancelled {
                    onTerminationContinuation.yield()
                    try await Task.sleep(for: .seconds(0.2))
                }
            }

            var onTerminationIterator = onTerminationStream.makeAsyncIterator()
            _ = await onTerminationIterator.next()

            var iterator = Optional.some(channel.asyncSequence().makeAsyncIterator())
            iterator = nil
            _ = await iterator?.next(isolation: nil)

            let terminationResult: Void? = await onTerminationIterator.next()
            XCTAssertNil(terminationResult)

            group.cancelAll()
        }
    }

    func testIteratorDeinitialized_whenSourceFinished() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
                of: Int.self,
                backpressureStrategy: .watermark(low: 5, high: 10)
            )
            let channel = channelAndSource.channel
            var source = consume channelAndSource.source

            let (onTerminationStream, onTerminationContinuation) = AsyncStream<Void>.makeStream()
            source.setOnTerminationCallback {
                onTerminationContinuation.finish()
            }

            try await source.send(1)
            source.finish(throwing: nil)
            
            group.addTask {
                while !Task.isCancelled {
                    onTerminationContinuation.yield()
                    try await Task.sleep(for: .seconds(0.2))
                }
            }

            var onTerminationIterator = onTerminationStream.makeAsyncIterator()
            _ = await onTerminationIterator.next()

            var iterator = Optional.some(channel.asyncSequence().makeAsyncIterator())
            iterator = nil
            _ = await iterator?.next(isolation: nil)

            let terminationResult: Void? = await onTerminationIterator.next()
            XCTAssertNil(terminationResult)

            group.cancelAll()
        }
    }

    func testIteratorDeinitialized_whenFinished() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
                of: Int.self,
                throwing: Error.self,
                backpressureStrategy: .watermark(low: 5, high: 10)
            )
            let channel = channelAndSource.channel
            let source = consume channelAndSource.source

            let (onTerminationStream, onTerminationContinuation) = AsyncStream<Void>.makeStream()
            source.setOnTerminationCallback {
                onTerminationContinuation.finish()
            }

            source.finish(throwing: nil)
            
            group.addTask {
                while !Task.isCancelled {
                    onTerminationContinuation.yield()
                    try await Task.sleep(for: .seconds(0.2))
                }
            }

            var onTerminationIterator = onTerminationStream.makeAsyncIterator()
            _ = await onTerminationIterator.next()

            var iterator = Optional.some(channel.asyncSequence().makeAsyncIterator())
            iterator = nil
            _ = try await iterator?.next()

            let terminationResult: Void? = await onTerminationIterator.next()
            XCTAssertNil(terminationResult)

            group.cancelAll()
        }
    }

    func testIteratorDeinitialized_whenChanneling_andSuspendedProducer() async throws {
        let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            throwing: Error.self,
            backpressureStrategy: .watermark(low: 5, high: 10)
        )
        var channel: MultiProducerSingleConsumerChannel? = channelAndSource.channel
        var source = consume channelAndSource.source

        var iterator = channel?.asyncSequence().makeAsyncIterator()
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

    // MARK: - write

    func testWrite_whenInitial() async throws {
        let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 2, high: 5)
        )
        let channel = channelAndSource.channel
        var source = consume channelAndSource.source

        try await source.send(1)

        var iterator = channel.asyncSequence().makeAsyncIterator()
        let element = await iterator.next(isolation: nil)
        XCTAssertEqual(element, 1)
    }

    func testWrite_whenChanneling_andNoConsumer() async throws {
        let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 2, high: 5)
        )
        let channel = channelAndSource.channel
        var source = consume channelAndSource.source

        try await source.send(1)
        try await source.send(2)

        var iterator = channel.asyncSequence().makeAsyncIterator()
        let element1 = await iterator.next(isolation: nil)
        XCTAssertEqual(element1, 1)
        let element2 = await iterator.next(isolation: nil)
        XCTAssertEqual(element2, 2)
    }

    func testWrite_whenChanneling_andSuspendedConsumer() async throws {
        try await withThrowingTaskGroup(of: Int?.self) { group in
            let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
                of: Int.self,
                backpressureStrategy: .watermark(low: 2, high: 5)
            )
            var channel = channelAndSource.channel
            var source = consume channelAndSource.source
            
            group.addTask {
                return await channel.next()
            }

            // This is always going to be a bit racy since we need the call to next() suspend
            try await Task.sleep(for: .seconds(0.5))

            try await source.send(1)
            let element = try await group.next()
            XCTAssertEqual(element, 1)
        }
    }

    func testWrite_whenChanneling_andSuspendedConsumer_andEmptySequence() async throws {
        try await withThrowingTaskGroup(of: Int?.self) { group in
            let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
                of: Int.self,
                backpressureStrategy: .watermark(low: 2, high: 5)
            )
            var channel = channelAndSource.channel
            var source = consume channelAndSource.source
            group.addTask {
                return await channel.next()
            }

            // This is always going to be a bit racy since we need the call to next() suspend
            try await Task.sleep(for: .seconds(0.5))

            try await source.send(contentsOf: [])
            try await source.send(contentsOf: [1])
            let element = try await group.next()
            XCTAssertEqual(element, 1)
        }
    }
    
    func testWrite_whenSourceFinished() async throws {
        let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 2, high: 5)
        )
        var channel = consume channelAndSource.channel
        var source1 = consume channelAndSource.source
        var source2 = source1.copy()
        
        try await source1.send(1)
        source1.finish()
        do {
            try await source2.send(1)
            XCTFail("Expected an error to be thrown")
        } catch {
            XCTAssertTrue(error is MultiProducerSingleConsumerChannelAlreadyFinishedError)
        }
        let element1 = await channel.next()
        XCTAssertEqual(element1, 1)
        let element2 = await channel.next()
        XCTAssertNil(element2)
    }
    
    func testWrite_whenConcurrentProduction() async throws {
        await withThrowingTaskGroup { group in
            let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
                of: Int.self,
                backpressureStrategy: .watermark(low: 2, high: 5)
            )
            var channel = consume channelAndSource.channel
            var source1 = consume channelAndSource.source
            var source2 = Optional.some(source1.copy())
            
            let manualExecutor1 = ManualTaskExecutor()
            group.addTask(executorPreference: manualExecutor1) {
                try await source1.send(1)
            }
            
            let manualExecutor2 = ManualTaskExecutor()
            group.addTask(executorPreference: manualExecutor2) {
                var source2 = source2.take()!
                try await source2.send(2)
                source2.finish()
            }
            
            manualExecutor1.run()
            let element1 = await channel.next()
            XCTAssertEqual(element1, 1)
            
            manualExecutor2.run()
            let element2 = await channel.next()
            XCTAssertEqual(element2, 2)
            
            let element3 = await channel.next()
            XCTAssertNil(element3)
        }
    }

    // MARK: - enqueueProducer

    func testEnqueueProducer_whenChanneling_andAndCancelled() async throws {
        let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 1, high: 2)
        )
        var channel = channelAndSource.channel
        var source = consume channelAndSource.source

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

        let element = await channel.next()
        XCTAssertEqual(element, 1)
    }

    func testEnqueueProducer_whenChanneling_andAndCancelled_andAsync() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
                of: Int.self,
                backpressureStrategy: .watermark(low: 1, high: 2)
            )
            var channel = channelAndSource.channel
            var source = consume channelAndSource.source

            try await source.send(1)
            
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
            
            let element = await channel.next()
            XCTAssertEqual(element, 1)
        }
    }

    func testEnqueueProducer_whenChanneling_andInterleaving() async throws {
        let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 1, high: 1)
        )
        let channel = channelAndSource.channel
        var source = consume channelAndSource.source
        var iterator = channel.asyncSequence().makeAsyncIterator()

        let (producerStream, producerSource) = AsyncThrowingStream<Void, Error>.makeStream()

        let writeResult = try { try source.send(1) }()

        switch writeResult {
        case .produceMore:
            preconditionFailure()
        case .enqueueCallback(let callbackToken):
            let element = await iterator.next(isolation: nil)
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
        let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 1, high: 1)
        )
        let channel = channelAndSource.channel
        var source = consume channelAndSource.source
        var iterator = channel.asyncSequence().makeAsyncIterator()

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

        let element = await iterator.next(isolation: nil)
        XCTAssertEqual(element, 1)

        do {
            _ = try await producerStream.first { _ in true }
        } catch {
            XCTFail("Expected no error to be thrown")
        }
    }

    // MARK: - cancelProducer

    func testCancelProducer_whenChanneling() async throws {
        let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 1, high: 2)
        )
        var channel = channelAndSource.channel
        var source = consume channelAndSource.source

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

        let element = await channel.next()
        XCTAssertEqual(element, 1)
    }

    // MARK: - finish

    func testFinish_whenChanneling_andConsumerSuspended() async throws {
        try await withThrowingTaskGroup(of: Int?.self) { group in
            let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
                of: Int.self,
                backpressureStrategy: .watermark(low: 1, high: 1)
            )
            var channel = channelAndSource.channel
            var source: MultiProducerSingleConsumerChannel.Source? = consume channelAndSource.source

            group.addTask {
                while let element = await channel.next() {
                    if element == 2 {
                        return element
                    }
                }
                return nil
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
        let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            throwing: Error.self,
            backpressureStrategy: .watermark(low: 1, high: 1)
        )
        let channel = channelAndSource.channel
        let source = consume channelAndSource.source

        source.finish(throwing: CancellationError())

        do {
            for try await _ in channel.asyncSequence() {}
            XCTFail("Expected an error to be thrown")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

    }

    // MARK: - Backpressure

    func testBackpressure() async throws {
        await withThrowingTaskGroup(of: Void.self) { group in
            let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
                of: Int.self,
                backpressureStrategy: .watermark(low: 2, high: 4)
            )
            let channel = channelAndSource.channel
            var source = consume channelAndSource.source

            let (backpressureEventStream, backpressureEventContinuation) = AsyncStream.makeStream(of: Void.self)
            
            group.addTask {
                while true {
                    backpressureEventContinuation.yield(())
                    try await source.send(contentsOf: [1])
                }
            }

            var backpressureEventIterator = backpressureEventStream.makeAsyncIterator()
            var iterator = channel.asyncSequence().makeAsyncIterator()

            await backpressureEventIterator.next()
            await backpressureEventIterator.next()
            await backpressureEventIterator.next()
            await backpressureEventIterator.next()

            _ = await iterator.next(isolation: nil)
            _ = await iterator.next(isolation: nil)
            _ = await iterator.next(isolation: nil)

            await backpressureEventIterator.next()
            await backpressureEventIterator.next()
            await backpressureEventIterator.next()

            group.cancelAll()
        }
    }

    func testBackpressureSync() async throws {
        await withThrowingTaskGroup(of: Void.self) { group in
            let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
                of: Int.self,
                backpressureStrategy: .watermark(low: 2, high: 4)
            )
            let channel = channelAndSource.channel
            var source = consume channelAndSource.source

            let (backpressureEventStream, backpressureEventContinuation) = AsyncStream.makeStream(of: Void.self)
            
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
            var iterator = channel.asyncSequence().makeAsyncIterator()

            await backpressureEventIterator.next()
            await backpressureEventIterator.next()
            await backpressureEventIterator.next()
            await backpressureEventIterator.next()

            _ = await iterator.next(isolation: nil)
            _ = await iterator.next(isolation: nil)
            _ = await iterator.next(isolation: nil)

            await backpressureEventIterator.next()
            await backpressureEventIterator.next()
            await backpressureEventIterator.next()

            group.cancelAll()
        }
    }

    func testWatermarkWithCustomCoount() async throws {
        let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
            of: [Int].self,
            backpressureStrategy: .watermark(low: 2, high: 4, waterLevelForElement: { $0.count })
        )
        let channel = channelAndSource.channel
        var source = consume channelAndSource.source
        var iterator = channel.asyncSequence().makeAsyncIterator()

        try await source.send([1, 1, 1])

        _ = await iterator.next(isolation: nil)

        try await source.send([1, 1, 1])

        _ = await iterator.next(isolation: nil)
    }

    func testWatermarWithLotsOfElements() async throws {
        await withThrowingTaskGroup(of: Void.self) { group in
            // This test should in the future use a custom task executor to schedule to avoid sending
            // 1000 elements.
            let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
                of: Int.self,
                backpressureStrategy: .watermark(low: 2, high: 4)
            )
            let channel = channelAndSource.channel
            var source: MultiProducerSingleConsumerChannel.Source! = consume channelAndSource.source
            
            group.addTask {
                var source = source.take()!
                for i in 0...10000 {
                    try await source.send(i)
                }
                source.finish()
            }
            
            let asyncSequence = channel.asyncSequence()

            group.addTask {
                var sum = 0
                for try await element in asyncSequence {
                    sum += element
                }
            }
        }
    }

    func testThrowsError() async throws {
        let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            throwing: Error.self,
            backpressureStrategy: .watermark(low: 2, high: 4)
        )
        let channel = channelAndSource.channel
        var source = consume channelAndSource.source

        try await source.send(1)
        try await source.send(2)
        source.finish(throwing: CancellationError())

        var elements = [Int]()
        var iterator = channel.asyncSequence().makeAsyncIterator()

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
        let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
            of: Int.self,
            backpressureStrategy: .watermark(low: 2, high: 4)
        )
        var channel = channelAndSource.channel
        var source = consume channelAndSource.source

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
        await withThrowingTaskGroup(of: Void.self) { group in
            let channelAndSource = MultiProducerSingleConsumerChannel.makeChannel(
                of: Int.self,
                backpressureStrategy: .watermark(low: 2, high: 4)
            )
            let channel = channelAndSource.channel
            var source = consume channelAndSource.source

            let (backpressureEventStream, backpressureEventContinuation) = AsyncStream.makeStream(of: Void.self)
            
            group.addTask {
                while true {
                    backpressureEventContinuation.yield(())
                    try await source.send(contentsOf: [1])
                }
            }

            var backpressureEventIterator = backpressureEventStream.makeAsyncIterator()
            var iterator = channel.asyncSequence().makeAsyncIterator()

            await backpressureEventIterator.next()
            await backpressureEventIterator.next()
            await backpressureEventIterator.next()
            await backpressureEventIterator.next()

            _ = await iterator.next(isolation: nil)
            _ = await iterator.next(isolation: nil)
            _ = await iterator.next(isolation: nil)

            await backpressureEventIterator.next()
            await backpressureEventIterator.next()
            await backpressureEventIterator.next()

            group.cancelAll()
        }
    }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension MultiProducerSingleConsumerChannel {
    /// Collect all elements in the sequence into an array.
    fileprivate mutating func collect() async throws(Failure) -> [Element] {
        var elements = [Element]()
        while let element = try await self.next() {
            elements.append(element)
        }
        return elements
    }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
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
