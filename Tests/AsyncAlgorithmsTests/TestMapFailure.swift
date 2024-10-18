import AsyncAlgorithms
import XCTest

#if compiler(>=6.0)
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
final class TestMapFailure: XCTestCase {

    func test_mapFailure() async throws {
        let array: [Any] = [1, 2, 3, MyAwesomeError.originalError, 4, 5, 6]
        let sequence = array.async
            .map {
                if let error = $0 as? Error {
                    throw error
                } else {
                    $0 as! Int
                }
            }
            .mapFailure { _ in
                MyAwesomeError.mappedError
            }

        var results: [Int] = []

        do {
            for try await number in sequence {
                results.append(number)
            }
            XCTFail("sequence should throw")
        } catch {
            XCTAssertEqual(error, .mappedError)
        }

        XCTAssertEqual(results, [1, 2, 3])
    }

    func test_mapFailure_cancellation() async throws {
        let value = "test"
        let source = Indefinite(value: value).async
        let sequence = source
            .map {
                if $0 == "just to trick compiler that this may throw" {
                    throw MyAwesomeError.originalError
                } else {
                    $0
                }
            }
            .mapFailure { _ in
                MyAwesomeError.mappedError
            }

        let finished = expectation(description: "finished")
        let iterated = expectation(description: "iterated")

        let task = Task {
            var firstIteration = false
            for try await el in sequence {
                XCTAssertEqual(el, value)

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

    func test_mapFailure_empty() async throws {
        let array: [String] = []
        let sequence = array.async
            .map {
                if $0 == "just to trick compiler that this may throw" {
                    throw MyAwesomeError.originalError
                } else {
                    $0
                }
            }
            .mapFailure { _ in
                MyAwesomeError.mappedError
            }

        var results: [String] = []
        for try await value in sequence {
            results.append(value)
        }
        XCTAssert(results.isEmpty)
    }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
private extension TestMapFailure {

    enum MyAwesomeError: Error {
        case originalError
        case mappedError
    }
}
#endif
