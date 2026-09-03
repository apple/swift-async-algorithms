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

import Synchronization

struct AsyncSplitSync<Collection: RangeReplaceableCollection<Base.Element>, Base: AsyncSequence>: AsyncSequence where Base.Element: Equatable {
    let base: Base
    let separator: Base.Element
    
    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(base: base.makeAsyncIterator(), separator: separator)
    }
    
    struct AsyncIterator: AsyncIteratorProtocol {
            var base: Base.AsyncIterator
            let separator: Base.Element
        
        mutating func next(isolation actor: isolated (any Actor)?) async throws(Base.Failure) -> Collection? {
            var res = Collection()
            
            while let x = try await base.next(isolation: actor) {
                if x == separator {
                    break
                } else {
                    res.append(x)
                }
            }
            
            return res
        }
    }
}

struct AsyncSplitAsync<Base: AsyncSequence>: AsyncSequence where Base.AsyncIterator: Sendable, Base.Element: Equatable & Sendable {
    typealias Element = NestedSequence
    typealias Failure = Never
    
    let base: Base
    let separator: Base.Element
    
    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator.initial(base: base.makeAsyncIterator(), separator: separator)
    }
    
    enum Message: Sendable {
        case next(Base.AsyncIterator), stop
    }

    enum AsyncIterator: AsyncIteratorProtocol {
        case initial(
            base: Base.AsyncIterator,
            separator: Base.Element,
        )
        case continuing(
            separator: Base.Element,
            fromNested: AsyncStream<Message>.AsyncIterator,
            toSelf: AsyncStream<Message>.Continuation,
        )
        case final
        
        typealias Element = NestedSequence
        typealias Failure = Never
        
        mutating func next(isolation actor: isolated (any Actor)?) async -> NestedSequence? {
            switch self {
            case let .initial(base, separator):
                let (fromNested, toSelf) = AsyncStream.makeStream(of: Message.self)
                self = .continuing(
                    separator: separator,
                    fromNested: fromNested.makeAsyncIterator(),
                    toSelf: toSelf,
                )
                return NestedSequence(base: base, separator: separator, toOuter: toSelf)
            case var .continuing(separator, fromNested, toSelf):
                switch await fromNested.next(isolation: actor) {
                case let .next(base):
                    return NestedSequence(base: base, separator: separator, toOuter: toSelf)
                case .stop, .none:
                    self = .final
                    return nil
                }
            case let .final:
                return nil
            }
        }
    }
     
    struct NestedSequence: AsyncSequence, Sendable {
        let base: Base.AsyncIterator
        let separator: Base.Element
        let toOuter: AsyncStream<Message>.Continuation
        
        func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(base: base, separator: separator, toOuter: toOuter)
        }

        struct AsyncIterator: AsyncIteratorProtocol {
            var base: Base.AsyncIterator
            let separator: Base.Element
            let toOuter: AsyncStream<Message>.Continuation

            mutating func next(isolation actor: isolated (any Actor)?) async throws(Base.Failure) -> Base.Element? {
                let x = try await base.next(isolation: actor)
                
                guard let x = x else {
                    toOuter.yield(.stop)
                    return nil
                }
                guard x != separator else {
                    toOuter.yield(.next(base))
                    return nil
                }
                return x
            }
        }
    }
}

extension AsyncSequence {
    func split<Collection>(separator: Element, collectInto _: Collection.Type) -> AsyncSplitSync<Collection, Self> where Element: Equatable {
        AsyncSplitSync(base: self, separator: separator)
    }
    
    func split(separator: Element) -> AsyncSplitAsync<Self> where Element: Equatable {
        AsyncSplitAsync(base: self, separator: separator)
    }
}
