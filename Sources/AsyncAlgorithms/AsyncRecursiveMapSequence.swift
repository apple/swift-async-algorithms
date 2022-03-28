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
    /// Returns a sequence containing the original sequence and the recursive mapped sequence.
    /// The order of ouput elements affects by the traversal option.
    ///
    /// ```
    /// struct Node {
    ///     var id: Int
    ///     var children: [Node] = []
    /// }
    /// let tree = [
    ///     Node(id: 1, children: [
    ///         Node(id: 2),
    ///         Node(id: 3, children: [
    ///             Node(id: 4),
    ///         ]),
    ///         Node(id: 5),
    ///     ]),
    ///     Node(id: 6),
    /// ]
    /// for await node in tree.async.recursiveMap({ $0.children.async }) {
    ///     print(node.id)
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
    ///   - option: Traversal option. This option affects the element order of the output sequence. default depth-first.
    ///   - transform: A closure that map the element to new sequence.
    /// - Returns: A sequence of the original sequence followed by recursive mapped sequence.
    @inlinable
    public func recursiveMap<C>(
        option: AsyncRecursiveMapSequence<Self, C>.TraversalOption = .depthFirst,
        _ transform: @Sendable @escaping (Element) async -> C
    ) -> AsyncRecursiveMapSequence<Self, C> {
        return AsyncRecursiveMapSequence(self, option, transform)
    }
}

/// A sequence containing the original sequence and the recursive mapped sequence.
/// The order of ouput elements affects by the traversal option.
public struct AsyncRecursiveMapSequence<Base: AsyncSequence, Transformed: AsyncSequence>: AsyncSequence where Base.Element == Transformed.Element {
    
    public typealias Element = Base.Element
    
    @usableFromInline
    let base: Base
    
    @usableFromInline
    let option: TraversalOption
    
    @usableFromInline
    let transform: @Sendable (Base.Element) async -> Transformed
    
    @inlinable
    init(
        _ base: Base,
        _ option: TraversalOption,
        _ transform: @Sendable @escaping (Base.Element) async -> Transformed
    ) {
        self.base = base
        self.option = option
        self.transform = transform
    }
    
    @inlinable
    public func makeAsyncIterator() -> AsyncIterator {
        return AsyncIterator(base, option, transform)
    }
}

extension AsyncRecursiveMapSequence {
    
    /// Traversal option. This option affects the element order of the output sequence.
    public enum TraversalOption {
        
        /// The algorithm will go down first and produce the resulting path.
        case depthFirst
        
        /// The algorithm will go through the previous sequence first and chaining all the occurring sequences.
        case breadthFirst
        
    }
    
    public struct AsyncIterator: AsyncIteratorProtocol {
        
        @usableFromInline
        var base: Base.AsyncIterator?
        
        @usableFromInline
        let option: TraversalOption
        
        @usableFromInline
        var mapped: ArraySlice<Transformed.AsyncIterator> = []
        
        @usableFromInline
        var mapped_iterator: Transformed.AsyncIterator?
        
        @usableFromInline
        let transform: @Sendable (Base.Element) async -> Transformed
        
        @inlinable
        init(
            _ base: Base,
            _ option: TraversalOption,
            _ transform: @Sendable @escaping (Base.Element) async -> Transformed
        ) {
            self.base = base.makeAsyncIterator()
            self.option = option
            self.transform = transform
        }
        
        @inlinable
        public mutating func next() async rethrows -> Base.Element? {
            
            switch option {
                
            case .depthFirst:
                
                while self.mapped_iterator != nil {
                    
                    if let element = try await self.mapped_iterator!.next() {
                        mapped.append(self.mapped_iterator!)
                        self.mapped_iterator = await transform(element).makeAsyncIterator()
                        return element
                    }
                    
                    self.mapped_iterator = mapped.popLast()
                }
                
                if self.base != nil {
                    
                    if let element = try await self.base!.next() {
                        self.mapped_iterator = await transform(element).makeAsyncIterator()
                        return element
                    }
                    
                    self.base = nil
                }
                
                return nil
                
            case .breadthFirst:
                
                if self.base != nil {
                    
                    if let element = try await self.base!.next() {
                        await mapped.append(transform(element).makeAsyncIterator())
                        return element
                    }
                    
                    self.base = nil
                    self.mapped_iterator = mapped.popFirst()
                }
                
                while self.mapped_iterator != nil {
                    
                    if let element = try await self.mapped_iterator!.next() {
                        await mapped.append(transform(element).makeAsyncIterator())
                        return element
                    }
                    
                    self.mapped_iterator = mapped.popFirst()
                }
                
                return nil
            }
        }
    }
}

extension AsyncRecursiveMapSequence: Sendable
where Base: Sendable, Base.Element: Sendable, Transformed: Sendable { }

extension AsyncRecursiveMapSequence.AsyncIterator: Sendable
where Base.AsyncIterator: Sendable, Base.Element: Sendable, Transformed: Sendable, Transformed.AsyncIterator: Sendable { }
