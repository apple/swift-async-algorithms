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
    /// Returns a sequence containing the original sequence followed by recursive mapped sequence.
    ///
    /// ```
    /// struct View {
    ///     var id: Int
    ///     var children: [View] = []
    /// }
    /// let tree = [
    ///     View(id: 1, children: [
    ///         View(id: 3),
    ///         View(id: 4, children: [
    ///             View(id: 6),
    ///         ]),
    ///         View(id: 5),
    ///     ]),
    ///     View(id: 2),
    /// ]
    /// for await view in tree.async.recursiveMap({ $0.children.async }) {
    ///     print(view.id)
    /// }
    /// // 1
    /// // 2
    /// // 3
    /// // 4
    /// // 5
    /// // 6
    /// ```
    ///
    /// - Parameters:
    ///   - transform: A closure that map the element to new sequence.
    /// - Returns: A sequence of the original sequence followed by recursive mapped sequence.
    @inlinable
    public func recursiveMap<C>(_ transform: @Sendable @escaping (Element) async -> C) -> AsyncRecursiveMapSequence<Self, C> {
        return AsyncRecursiveMapSequence(self, transform)
    }
}

public struct AsyncRecursiveMapSequence<Base: AsyncSequence, Transformed: AsyncSequence>: AsyncSequence where Base.Element == Transformed.Element {
    
    public typealias Element = Base.Element
    
    @usableFromInline
    let base: Base
    
    @usableFromInline
    let transform: @Sendable (Base.Element) async -> Transformed
    
    @inlinable
    init(_ base: Base, _ transform: @Sendable @escaping (Base.Element) async -> Transformed) {
        self.base = base
        self.transform = transform
    }
    
    @inlinable
    public func makeAsyncIterator() -> AsyncIterator {
        return AsyncIterator(base, transform)
    }
}

extension AsyncRecursiveMapSequence {
    
    public struct AsyncIterator: AsyncIteratorProtocol {
        
        @usableFromInline
        var base: Base.AsyncIterator?
        
        @usableFromInline
        var mapped: ArraySlice<Transformed> = []
        
        @usableFromInline
        var mapped_iterator: Transformed.AsyncIterator?
        
        @usableFromInline
        var transform: @Sendable (Base.Element) async -> Transformed
        
        @inlinable
        init(_ base: Base, _ transform: @Sendable @escaping (Base.Element) async -> Transformed) {
            self.base = base.makeAsyncIterator()
            self.transform = transform
        }
        
        @inlinable
        public mutating func next() async rethrows -> Base.Element? {
            
            if self.base != nil {
                
                if let element = try await self.base?.next() {
                    await mapped.append(transform(element))
                    return element
                }
                
                self.base = nil
                self.mapped_iterator = mapped.popFirst()?.makeAsyncIterator()
            }
            
            while self.mapped_iterator != nil {
                
                if let element = try await self.mapped_iterator?.next() {
                    await mapped.append(transform(element))
                    return element
                }
                
                self.mapped_iterator = mapped.popFirst()?.makeAsyncIterator()
            }
            
            return nil
        }
    }
}

extension AsyncRecursiveMapSequence: Sendable
where Base: Sendable, Base.Element: Sendable, Transformed: Sendable { }

extension AsyncRecursiveMapSequence.AsyncIterator: Sendable
where Base.AsyncIterator: Sendable, Base.Element: Sendable, Transformed: Sendable, Transformed.AsyncIterator: Sendable { }
