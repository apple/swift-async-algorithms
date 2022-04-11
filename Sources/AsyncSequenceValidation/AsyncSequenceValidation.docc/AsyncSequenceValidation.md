# ``AsyncSequenceValidation``


## Overview

Testing is a critical area of focus for any package to make it robust, catch bugs, and explain the expected behaviors in a documented manner. Testing things that are asynchronous can be difficult, testing things that are asynchronous multiple times can be even more difficult.

Types that implement `AsyncSequence` can often be described in deterministic actions given particular inputs. For the inputs, the events can be described as a discrete set: values, errors being thrown, the terminal state of returning a `nil` value from the iterator, or advancing in time and not doing anything. Likewise, the expected output has a discrete set of events: values, errors being caught, the terminal state of receiving a `nil` value from the iterator, or advancing in time and not doing anything. 

## Topics

### Getting Started

- <doc:Validation>
