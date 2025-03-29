import DequeModule
import Synchronization

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
final class ManualTaskExecutor: TaskExecutor {
  private let jobs = Mutex<Deque<UnownedJob>>(.init())

  func enqueue(_ job: UnownedJob) {
    self.jobs.withLock { $0.append(job) }
  }

  func run() {
    while let job = self.jobs.withLock({ $0.popFirst() }) {
      job.runSynchronously(on: self.asUnownedTaskExecutor())
    }
  }
}
