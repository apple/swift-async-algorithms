import AsyncAlgorithms
import XCTest

final class TestMapError: XCTestCase {

    func test_mapError() async throws {
        let array = [URLError(.badURL)]
        let sequence = array.async
            .map { throw $0 }
            .mapError { _ in
                MyAwesomeError()
            }

        do {
            for try await _ in sequence {
                XCTFail("sequence should throw")
            }
        } catch {
            _ = try XCTUnwrap(error as? MyAwesomeError)
        }
    }

    func test_nonThrowing() async throws {
        let array = [1, 2, 3, 4, 5]
        let sequence = array.async
            .mapError { _ in
                MyAwesomeError()
            }

        var actual: [Int] = []
        for try await value in sequence {
            actual.append(value)
        }
        XCTAssertEqual(array, actual)
    }

    func test_cancellation() async throws {
        let source = Indefinite(value: "test").async
        let sequence = source.mapError { _ in MyAwesomeError() }

        let finished = expectation(description: "finished")
        let iterated = expectation(description: "iterated")

        let task = Task {
            var firstIteration = false
            for try await el in sequence {
                XCTAssertEqual(el, "test")

                if !firstIteration {
                    firstIteration = true
                    iterated.fulfill()
                }
            }
            finished.fulfill()
        }

        // ensure the other task actually starts
        await fulfillment(of: [iterated], timeout: 1.0)
        // cancellation should ensure the loop finishes
        // without regards to the remaining underlying sequence
        task.cancel()
        await fulfillment(of: [finished], timeout: 1.0)
    }

    func test_empty() async throws {
        let array: [Int] = []
        let sequence = array.async
            .mapError { _ in
                MyAwesomeError()
            }

        var actual: [Int] = []
        for try await value in sequence {
            actual.append(value)
        }
        XCTAssert(actual.isEmpty)
    }
}

private extension TestMapError {

    struct MyAwesomeError: Error {}
}
