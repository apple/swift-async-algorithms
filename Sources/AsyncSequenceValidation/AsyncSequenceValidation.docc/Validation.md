# AsyncSequence Validation

* Author(s): [Philippe Hausler](https://github.com/phausler)
* Implementation: [AsyncSequenceValidation](https://github.com/apple/swift-async-algorithms/tree/main/Sources/AsyncSequenceValidation)

## Introduction

Testing is a critical area of focus for any package to make it robust, catch bugs, and explain the expected behaviors in a documented manner. Testing things that are asynchronous can be difficult, testing things that are asynchronous multiple times can be even more difficult.

Types that implement `AsyncSequence` can often be described in deterministic actions given particular inputs. For the inputs, the events can be described as a discrete set: values, errors being thrown, the terminal state of returning a `nil` value from the iterator, or advancing in time and not doing anything. Likewise, the expected output has a discrete set of events: values, errors being caught, the terminal state of receiving a `nil` value from the iterator, or advancing in time and not doing anything. 

## Proposed Solution

By restricting the domain space of values to `String` we can describe the events as a domain specific language, and with monospaced characters that domain space can be used to show values over time for both the input to an `AsyncSequence` but also the expected output. 

```swift
validate {
  "a--b--c---|"
  $0.inputs[0].map { $0.capitalized }
  "A--B--C---|"
}
```

This syntax can be accomplished with a confluence of utilizing some of the advanced features of XCTest, the concurrency runtime, and result builders. The diagram as listed flows as if each event that would propagate is an event flowing along a column but also it shows the expression progressed over time; describing each event. 

By utilizing result builders, this same function can accommodate more than one input specification for testing things like `merge`.

```swift
validate {
  "a-c--f-|"
  "-b-de-g|"
  merge($0.inputs[0], $0.inputs[1])
  "abcdefg|"
}
```

Normally testing a function like `merge` would result in either limited expectations or be stochastic in nature. Those approaches are to account for the potential ordering not being deterministic. Taking the approach of having explicit ordering of time defined by the diagram allows for the test to be predictable. That determinism is sourced directly from the input sequences and the expected correlative output sequence. In short, the syntax of the test inputs and expectations make the execution reliable.

The syntax is trivially parsable (and consequently customizable). By default, the events require only a limited subset of characters for control; such as the advancing in time `-`, or the termination of a sequence by returning nil `|`. However some events may produce strings greater than just one character, other events may happen at the same time, and there is also the cancellation event. This all culminates into a test theme definition of:

|  Symbol |  Description      | Example    |  
| ------- | ----------------- | ---------- |
|   `-`   | Advance time      | `"a--b--"` |
|   `\|`  | Termination       | `"ab-\|"`  |
|   `^`   | Thrown error      | `"ab-^"`   |
|   `;`   | Cancellation      | `"ab;-"`   |
|   `[`   | Begin group       | `"[ab]-"`  |
|   `]`   | End group         | `"[ab]-"`  |
|   `'`   | Begin/End Value   | `"'foo'-"` |
|   `,`   | Delay next        | `",[a,]b"` |

Because some events may take up more than one character and the alignment is important to the visual progression of events, spaces are not counted as part of the parsed events. A space means that no time is advanced and not event is produced or expected. This means that the string `"a -    -b- -"` is equivalent to `"a--b--"`.

Defining a custom theme can then be trivial, since the list of expected interactions are well known. For example an emoji based diagram can be easily constructed:

```swift
struct EmojiTokens: AsyncSequenceValidationTheme {
  func token(_ character: Character, inValue: Bool) -> AsyncSequenceValidationDiagram.Token {
    switch character {
    case "➖": return .step
    case "❗️": return .error
    case "❌": return .finish
    case "➡️": return .beginValue
    case "⬅️": return .endValue
    case "⏳": return .delayNext
    case " ": return .skip
    default: return .value(String(character))
    }
  }
}

validate(theme: EmojiTokens()) {
  "➖🔴➖🟠➖🟡➖🟢➖❌"
  $0.inputs[0]
  "➖🔴➖🟠➖🟡➖🟢➖❌"
}
```

## Detailed Design

The public interface for this system comes in two parts: the `AsyncSequenceValidationDiagram` subsystem and the `XCTest` extensions. The most commonly interacted-with and most approachable portion is the `XCTest` extension.

```swift
extension XCTestCase {
  public func validate<Test: AsyncSequenceValidationTest, Theme: AsyncSequenceValidationTheme>(theme: Theme, @AsyncSequenceValidationDiagram _ build: (inout AsyncSequenceValidationDiagram) -> Test, file: StaticString = #file, line: UInt = #line)
  
  public func validate<Test: AsyncSequenceValidationTest>(@AsyncSequenceValidationDiagram _ build: (inout AsyncSequenceValidationDiagram) -> Test, file: StaticString = #file, line: UInt = #line)
}
```

These two methods break down to usage like some of the previously used examples. However, the reality of how it works is perhaps the more important portion. For example, the code listed below has some points of interest worth mentioning.

```swift
validate {
  "a--b--c---|"
  $0.inputs[0].map { item in await Task { item.capitalized }.value }
  "A--B--C---|"
}
``` 

The progression of the input sequence can be derived from the `$0.inputs[0]`. This is an `AsyncSequence` with the `Element` type of `String` which at the given input emits an `"a"` at tick 0, a `"b"` at tick 3, a `"c"` at tick 6 and a finish event at tick 10. The output of the middle expression `$0.inputs[0].map { item in await Task { item.capitalized }.value }` is expected to emit an `"A"` at tick 0, a `"B"` at tick 3, a `"C"` at tick 6 and a finish event at tick 10.

Careful readers may immediately recognize that the `map` function is asynchronous and schedules work on a separate task. Normally, this would pose a distinct hazard to deterministic testing for timing of events. However, the `validate` utilizes a specialized hook into the Swift concurrency runtime to schedule the events stepwise and deterministically. This works in a two-fold manner: first, it uses a custom `Clock` to schedule events. Second, it ties that clock into a task driver that ensures enqueued jobs are executed in lockstep with that clock.

The underpinnings to make that work are the actual `AsyncSequenceValidationDiagram` subsystem. The `XCTest` interface does offer a considerably more simple surface area so the diagrams will be broken down into a few key sections for approachability. Those sections are the result builder, the diagram clock, the inputs, themes, and expectations/tests.

### Result Builder

The result builder syntax allows for simple and concise diagrams to be built. Those diagrams can come in a few forms, ranging from no inputs to three inputs. It is worth noting the implementation is not limited to just three inputs and can easily be expanded to more as we deem it needed. The builder itself uses the multiple parameter build block functions to ensure the proper ordering of inputs, tested sequences, and outputs. 

```swift
@resultBuilder
public struct AsyncSequenceValidationDiagram : Sendable {
  public static func buildBlock<Operation: AsyncSequence>(
    _ sequence: Operation,
    _ output: String
  ) -> some AsyncSequenceValidationTest where Operation.Element == String
  
  public static func buildBlock<Operation: AsyncSequence>(
    _ input: String, 
    _ sequence: Operation, 
    _ output: String
  ) -> some AsyncSequenceValidationTest where Operation.Element == String
  
  public static func buildBlock<Operation: AsyncSequence>(
    _ input1: String, 
    _ input2: String, 
    _ sequence: Operation, 
    _ output: String
  ) -> some AsyncSequenceValidationTest where Operation.Element == String 
  
  public static func buildBlock<Operation: AsyncSequence>(
    _ input1: String, 
    _ input2: String, 
    _ input3: String, 
    _ sequence: Operation, 
    _ output: String
  ) -> some AsyncSequenceValidationTest where Operation.Element == String
  
  public var inputs: InputList { get }
  public var clock: Clock { get }
}
```

The `AsyncSequenceValidationTest`, `InputList`, and `Clock` will be covered in subsequent sections.

### Validation Diagram Clock

One of the key functionalities of the validation diagrams is being able to control time. For proper usage of this testing infrastructure, all clock sources must be tied to the `AsyncSequenceValidationDiagram.Clock` that is exposed on the diagram itself. This is the heartbeat of how each columnar input and expectation are produced and consumed. It measures time in an integral manner of `steps`. One step is advanced per event symbol; in the default ASCII diagrams that means:

*  `-`, `;`, `|`, `^`, and any character value event.
* Quoted values like `"'foo'"`.
* Grouped events like `"[ab]"`.

```swift
extension AsyncSequenceValidationDiagram {
  public struct Clock { }
}

extension AsyncSequenceValidationDiagram.Clock: Clock {
  public struct Step: DurationProtocol, Hashable, CustomStringConvertible {
    public static func + (lhs: Step, rhs: Step) -> Step
    public static func - (lhs: Step, rhs: Step) -> Step
    public static func / (lhs: Step, rhs: Int) -> Step
    public static func * (lhs: Step, rhs: Int) -> Step
    public static func / (lhs: Step, rhs: Step) -> Double
    public static func < (lhs: Step, rhs: Step) -> Bool
  
    public static var zero: Step
  
    public static func steps(_ amount: Int) -> Step
  }
  
  public struct Instant: InstantProtocol, CustomStringConvertible {
    public func advanced(by duration: Step) -> Instant
    
    public func duration(to other: Instant) -> Step
  }
  
  public var now: Instant { get }
  public var minimumResolution: Step { get }
  
  public func sleep(
    until deadline: Instant,
    tolerance: Step? = nil
  ) async throws
}
```

Key notes: the `minimumResolution` of the `AsyncSequenceValidationDiagram.Clock` is fixed at `.steps(1)`, and the tolerance to the `sleep` function is ignored. These two behaviors were chosen because there is no sub-step granularity besides the order of execution and any coalescing due to tolerance would detract from the explicit expectations of deterministic execution order.

### Inputs

The inputs to the validation diagram are lazily constructed with the input parameters built by the result builder syntax. The inputs are `Sendable` and `AsyncSequence` conforming types that have their `Element` defined as `String`. The elements are produced as defined by the input specification in the result builder. This means that on each tick that an element is defined, the `next` function will resume to return that element (or return `nil` or throw an error, depending on the input specification). The `InputList` grants access to the defined inputs lazily. 

```swift
extension AsyncSequenceValidationDiagram {
  public struct Input: AsyncSequence, Sendable {
    public typealias Element = String
    
    public struct Iterator: AsyncIteratorProtocol {
      public mutating func next() async throws -> String?
    }
    
    public func makeAsyncIterator() -> Iterator 
  }
  
  public struct InputList: RandomAccessCollection, Sendable {
    public typealias Element = Input
  }
}
```

Access to the validation diagram input list is done through calls such as `$0.inputs[0]` seen in other examples. This access fetches lazily the first input specification and creates an `Input` `AsyncSequence` out of that domain specific language symbology. 

### Themes

|  Symbol | Token                     |  Description      | Example    |  
| ------- | ------------------------- | ----------------- | ---------- |
|   `-`   | `.step`                   | Advance time      | `"a--b--"` |
|   `\|`   | `.finish`                 | Termination       | `"ab-\|"`   |
|   `^`   | `.error`                  | Thrown error      | `"ab-^"`   |
|   `;`   | `.cancel`                 | Cancellation      | `"ab;-"`   |
|   `[`   | `.beginGroup`             | Begin group       | `"[ab]-"`  |
|   `]`   | `.endGroup`               | End group         | `"[ab]-"`  |
|   `'`   | `.beginValue` `.endValue` | Begin/End Value   | `"'foo'-"` |
|   `,`   | `.delayNext`              | Delay next        | `",[a,]b"` |
|   ` `   | `.skip`                   | Skip/Ignore       | `"a b- \|"` |
|         | `.value`                  | Values.           | `"ab-\|"`   |

There are some diagram input specifications that are not valid. The three cases are:

* A step being specified in a group (`"[a-]b|"`).
* A nested group (`"[[ab]]|"`).
* An unbalanced nesting (`"[ab|"`).

```swift
public protocol AsyncSequenceValidationTheme {
  func token(_ character: Character, inValue: Bool) -> AsyncSequenceValidationDiagram.Token
}

extension AsyncSequenceValidationTheme where Self == AsyncSequenceValidationDiagram.ASCIITheme {
  public static var ascii: AsyncSequenceValidationDiagram.ASCIITheme
}

extension AsyncSequenceValidationDiagram {
  public enum Token {
    case step
    case error
    case finish
    case cancel
    case delayNext
    case beginValue
    case endValue
    case beginGroup
    case endGroup
    case skip
    case value(String)
  }
  
  public struct ASCIITheme: AsyncSequenceValidationTheme {
    public func token(_ character: Character, inValue: Bool) -> AsyncSequenceValidationDiagram.Token
  }
}
```

### Expectations and Tests

This set of interfaces are the primary mechanism in which the simplified XCTest extension rests upon. 

Expectations defined by the domain specific language symbology can be roughly expressed as expected results and actual results. This notably avoids cancellation and steps, since those are better expressed through the failure reporting system. The expectation failures can express the combination of these expected and actual values. This can also show when the expectation failure occurred and the kind of expectation failure that happened, along with the payload of the actual and expected values.

```swift
extension AsyncSequenceValidationDiagram {
  public struct ExpectationResult {
    public var expected: [(Clock.Instant, Result<String?, Error>)]
    public var actual: [(Clock.Instant, Result<String?, Error>)]
  }
  
  public struct ExpectationFailure: CustomStringConvertible {
    public enum Kind {
      case expectedFinishButGotValue(String)
      case expectedMismatch(String, String)
      case expectedValueButGotFinished(String)
      case expectedFailureButGotValue(Error, String)
      case expectedFailureButGotFinish(Error)
      case expectedValueButGotFailure(String, Error)
      case expectedFinishButGotFailure(Error)
      case expectedValue(String)
      case expectedFinish
      case expectedFailure(Error)
      case unexpectedValue(String)
      case unexpectedFinish
      case unexpectedFailure(Error)
    }
    
    public var when: Clock.Instant
    public var kind: Kind
  }
}
```

The testing itself reduces down to two methods, one being a default theme parameter of `.ascii`. The test methods execute the validation diagram using a custom scheduling hook from the concurrency runtime such that all events are sequentially processed on a single cooperatively-multitasking executed thread. That thread is responsible for ensuring the ordering of the events and the execution of each time delineation such that the order of emissions of any input events are sequential top to bottom: input 0 is emitted first, then input 1, etc. After the ordering of input events, the jobs enqueued onto that task driver thread are executed in order of receipt. This ensures the overall order of execution is stable and deterministic but, most importantly, predictable.

```swift
public protocol AsyncSequenceValidationTest: Sendable {
  var inputs: [String] { get }
  var output: String { get }
  
  func test(_ event: (String) -> Void) async throws
}

extension AsyncSequenceValidationDiagram {
  public static func test<Test: AsyncSequenceValidationTest, Theme: AsyncSequenceValidationTheme>(
    theme: Theme,
    @AsyncSequenceValidationDiagram _ build: (inout AsyncSequenceValidationDiagram) -> Test
  ) throws -> (ExpectationResult, [ExpectationFailure])
  
  public static func test<Test: AsyncSequenceValidationTest>(
    @AsyncSequenceValidationDiagram _ build: (inout AsyncSequenceValidationDiagram) -> Test
  ) throws -> (ExpectationResult, [ExpectationFailure])
}
```

## Future Directions/Improvements

The emoji diagram theme could be made to be a built-in system. It makes for really flashy slides/demos and makes it really easy to see what is going on, but at the cost of being slightly harder to type.

The testing infrastructure could support (with minor alteration) testing iteration beyond the terminal cases, either errors being thrown from the iterator or past the first `nil` return value from `next`. This could help enforce some of the semantical expectations of `AsyncSequence`.

In addition to hooking into the runtime for execution of jobs, the deferred execution of jobs could also be hooked so that a time scale conversion could be made such that any sleep using any clock could map directly to the validation diagram internal clock ticks. 

The testing infrastructure could also have support for testing for values that do not have specified order for a given tick. Some race conditions from external systems not under the control of the concurrency runtime may not be accountable. If that were to be a consideration, unordered group tokens could be added. For example the symbols `{` and `}` could be used to represent a group that is unordered. However, since there are not any cases where this really seems useful for the swift-async-algorithms package, this is not a priority at this time.

## Alternatives Considered

The validation diagram system could be retrofitted to accommodate other value types other than strings, however most use cases can easily be expressed in a readable form with minor adjustments to use strings. 

The builder functions could pass in N-ary variants of the diagram to enforce the inputs to be specific instead of accessed via the lazy `InputList`. As we may potentially add additional numbers of inputs in the future this seems like a less maintainable implementation even though it may offer slightly more safety and only marginally better spelling,  i.e., `$0.inputs[0]` versus `$0.input0` etc.

## Credits/Inspiration

Some of the major sources of inspiration for the validation diagram system were https://rxjs.dev/guide/testing/marble-testing and the graphical representations from https://rxmarbles.com. Both of these were immensely useful to help discuss the expected behaviors of how asynchronous sequences should behave. 
