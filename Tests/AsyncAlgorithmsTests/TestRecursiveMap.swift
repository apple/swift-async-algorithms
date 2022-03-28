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

@preconcurrency import XCTest
import AsyncAlgorithms

final class TestRecursiveMap: XCTestCase {
    
    struct Dir: Hashable {
        
        var id: UUID = UUID()
        
        var parent: UUID?
        
        var name: String
        
    }
    
    struct Path: Hashable {
        
        var id: UUID
        
        var path: String
        
    }
    
    func testAsyncRecursiveMap() async {
        
        var list: [Dir] = []
        list.append(Dir(name: "root"))
        list.append(Dir(parent: list[0].id, name: "images"))
        list.append(Dir(parent: list[0].id, name: "Users"))
        list.append(Dir(parent: list[2].id, name: "Susan"))
        list.append(Dir(parent: list[3].id, name: "Desktop"))
        list.append(Dir(parent: list[1].id, name: "test.jpg"))
        
        let answer = [
            Path(id: list[0].id, path: "/root"),
            Path(id: list[1].id, path: "/root/images"),
            Path(id: list[2].id, path: "/root/Users"),
            Path(id: list[5].id, path: "/root/images/test.jpg"),
            Path(id: list[3].id, path: "/root/Users/Susan"),
            Path(id: list[4].id, path: "/root/Users/Susan/Desktop"),
        ]
        
        let _list = list
        
        let _result: AsyncRecursiveMapSequence = list.async
            .compactMap { $0.parent == nil ? Path(id: $0.id, path: "/\($0.name)") : nil }
            .recursiveMap(option: .breadthFirst) { parent in _list.async.compactMap { $0.parent == parent.id ? Path(id: $0.id, path: "\(parent.path)/\($0.name)") : nil } }
        
        var result: [Path] = []
        
        for await item in _result {
            result.append(item)
        }
        
        XCTAssertEqual(result, answer)
    }
    
    func testAsyncThrowingRecursiveMap() async throws {
        
        var list: [Dir] = []
        list.append(Dir(name: "root"))
        list.append(Dir(parent: list[0].id, name: "images"))
        list.append(Dir(parent: list[0].id, name: "Users"))
        list.append(Dir(parent: list[2].id, name: "Susan"))
        list.append(Dir(parent: list[3].id, name: "Desktop"))
        list.append(Dir(parent: list[1].id, name: "test.jpg"))
        
        let answer = [
            Path(id: list[0].id, path: "/root"),
            Path(id: list[1].id, path: "/root/images"),
            Path(id: list[2].id, path: "/root/Users"),
            Path(id: list[5].id, path: "/root/images/test.jpg"),
            Path(id: list[3].id, path: "/root/Users/Susan"),
            Path(id: list[4].id, path: "/root/Users/Susan/Desktop"),
        ]
        
        let _list = list
        
        let _result: AsyncThrowingRecursiveMapSequence = list.async
            .compactMap { $0.parent == nil ? Path(id: $0.id, path: "/\($0.name)") : nil }
            .recursiveMap(option: .breadthFirst) { parent in _list.async.compactMap { $0.parent == parent.id ? Path(id: $0.id, path: "\(parent.path)/\($0.name)") : nil } }
        
        var result: [Path] = []
        
        for try await item in _result {
            result.append(item)
        }
        
        XCTAssertEqual(result, answer)
    }
    
    struct Node {
        
        var id: Int
        
        var children: [Node] = []
    }
    
    func testAsyncRecursiveMap2() async {
        
        let tree = [
            Node(id: 1, children: [
                Node(id: 2),
                Node(id: 3, children: [
                    Node(id: 4),
                ]),
                Node(id: 5),
            ]),
            Node(id: 6),
        ]
        
        let nodes: AsyncRecursiveMapSequence = tree.async.recursiveMap { $0.children.async }  // default depthFirst option
        
        var result: [Int] = []
        
        for await node in nodes {
            result.append(node.id)
        }
        
        XCTAssertEqual(result, Array(1...6))
    }
    
    func testAsyncThrowingRecursiveMap2() async throws {
        
        let tree = [
            Node(id: 1, children: [
                Node(id: 2),
                Node(id: 3, children: [
                    Node(id: 4),
                ]),
                Node(id: 5),
            ]),
            Node(id: 6),
        ]
        
        let nodes: AsyncThrowingRecursiveMapSequence = tree.async.recursiveMap { $0.children.async }  // default depthFirst option
        
        var result: [Int] = []
        
        for try await node in nodes {
            result.append(node.id)
        }
        
        XCTAssertEqual(result, Array(1...6))
    }
    
    func testAsyncRecursiveMap3() async {
        
        let tree = [
            Node(id: 1, children: [
                Node(id: 3),
                Node(id: 4, children: [
                    Node(id: 6),
                ]),
                Node(id: 5),
            ]),
            Node(id: 2),
        ]
        
        let nodes: AsyncRecursiveMapSequence = tree.async.recursiveMap(option: .breadthFirst) { $0.children.async }
        
        var result: [Int] = []
        
        for await node in nodes {
            result.append(node.id)
        }
        
        XCTAssertEqual(result, Array(1...6))
    }
    
    func testAsyncThrowingRecursiveMap3() async throws {
        
        let tree = [
            Node(id: 1, children: [
                Node(id: 3),
                Node(id: 4, children: [
                    Node(id: 6),
                ]),
                Node(id: 5),
            ]),
            Node(id: 2),
        ]
        
        let nodes: AsyncThrowingRecursiveMapSequence = tree.async.recursiveMap(option: .breadthFirst) { $0.children.async }
        
        var result: [Int] = []
        
        for try await node in nodes {
            result.append(node.id)
        }
        
        XCTAssertEqual(result, Array(1...6))
    }
    
    func testAsyncThrowingRecursiveMapWithClosureThrows() async throws {
        
        let tree = [
            Node(id: 1, children: [
                Node(id: 3),
                Node(id: 4, children: [
                    Node(id: 6),
                ]),
                Node(id: 5),
            ]),
            Node(id: 2),
        ]
        
        let nodes = tree.async.recursiveMap { node async throws -> AsyncLazySequence<[TestRecursiveMap.Node]> in
            if node.id == 4 { throw NSError(domain: NSCocoaErrorDomain, code: -1, userInfo: nil) }
            return node.children.async
        }
        
        var result: [Int] = []
        var iterator = nodes.makeAsyncIterator()
        
        do {
            
            while let node = try await iterator.next() {
                result.append(node.id)
            }
            
            XCTFail()
            
        } catch {
            
            XCTAssertEqual((error as NSError).code, -1)  // we got throw from the closure
        }
        
        let expectedNil = try await iterator.next()  // we should get nil in here
        XCTAssertNil(expectedNil)
    }
    
}
