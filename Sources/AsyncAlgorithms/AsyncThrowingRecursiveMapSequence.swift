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

extension AsyncSequence {
    
    @inlinable
    public func recursiveMap<C>(_ transform: @Sendable @escaping (Element) async throws -> C) -> AsyncThrowingRecursiveMapSequence<Self, C> {
        return AsyncThrowingRecursiveMapSequence(self, transform)
    }
}

public struct AsyncThrowingRecursiveMapSequence<Base: AsyncSequence, Transformed: AsyncSequence>: AsyncSequence where Base.Element == Transformed.Element {
    
    public typealias Element = Base.Element
    
    @usableFromInline
    let base: Base
    
    @usableFromInline
    let transform: @Sendable (Base.Element) async throws -> Transformed
    
    @inlinable
    init(_ base: Base, _ transform: @Sendable @escaping (Base.Element) async throws -> Transformed) {
        self.base = base
        self.transform = transform
    }
    
    @inlinable
    public func makeAsyncIterator() -> AsyncIterator {
        return AsyncIterator(base, transform)
    }
}

extension AsyncThrowingRecursiveMapSequence {
    
    public struct AsyncIterator: AsyncIteratorProtocol {
        
        @usableFromInline
        var base: Base.AsyncIterator?
        
        @usableFromInline
        var mapped: ArraySlice<Transformed> = []
        
        @usableFromInline
        var mapped_iterator: Transformed.AsyncIterator?
        
        @usableFromInline
        var transform: @Sendable (Base.Element) async throws -> Transformed
        
        @inlinable
        init(_ base: Base, _ transform: @Sendable @escaping (Base.Element) async throws -> Transformed) {
            self.base = base.makeAsyncIterator()
            self.transform = transform
        }
        
        @inlinable
        public mutating func next() async throws -> Base.Element? {
            
            if self.base != nil {
                
                if let element = try await self.base?.next() {
                    try await mapped.append(transform(element))
                    return element
                }
                
                self.base = nil
                self.mapped_iterator = mapped.popFirst()?.makeAsyncIterator()
            }
            
            while self.mapped_iterator != nil {
                
                if let element = try await self.mapped_iterator?.next() {
                    try await mapped.append(transform(element))
                    return element
                }
                
                self.mapped_iterator = mapped.popFirst()?.makeAsyncIterator()
            }
            
            return nil
        }
    }
}

extension AsyncThrowingRecursiveMapSequence: Sendable
where Base: Sendable, Base.Element: Sendable, Transformed: Sendable { }

extension AsyncThrowingRecursiveMapSequence.AsyncIterator: Sendable
where Base.AsyncIterator: Sendable, Base.Element: Sendable, Transformed: Sendable, Transformed.AsyncIterator: Sendable { }
