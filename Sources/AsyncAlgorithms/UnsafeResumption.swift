struct UnsafeResumption<Success, Failure: Error> {
  let continuation: UnsafeContinuation<Success, Failure>?
  let result: Result<Success, Failure>
  
  init(continuation: UnsafeContinuation<Success, Failure>?, result: Result<Success, Failure>) {
    self.continuation = continuation
    self.result = result
  }
  
  init(continuation: UnsafeContinuation<Success, Failure>?, success: Success) {
    self.init(continuation: continuation, result: .success(success))
  }
  
  init(continuation: UnsafeContinuation<Success, Failure>?, failure: Failure) {
    self.init(continuation: continuation, result: .failure(failure))
  }
  
  func resume() {
    continuation?.resume(with: result)
  }
}

extension UnsafeResumption where Failure == Error {
  init(continuation: UnsafeContinuation<Success, Failure>, catching body: () throws -> Success) {
    self.init(continuation: continuation, result: Result(catching: body))
  }
}

extension UnsafeResumption where Success == Void {
  init(continuation: UnsafeContinuation<Success, Failure>) {
    self.init(continuation: continuation, result: .success(()))
  }
}

extension UnsafeResumption: Sendable where Success: Sendable { }


