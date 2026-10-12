import Foundation
import Observation

/// The last sample, kept fresh by one sampling loop on its own serial queue.
///
/// The C sampler is thread-affine, so it is created, used and released inside that queue; readers
/// only see the last decoded sample. `onUpdate` is called on the main thread after every change,
/// which is what the status item refreshes from.
@Observable
public final class Monitor {
  public private(set) var sample: Sample?
  /// Static machine information, published once with the first sample.
  public private(set) var soc: SocInfo?
  /// The busiest processes, busiest first.
  public private(set) var processes: [Process] = []
  public private(set) var failure: String?

  /// Called on the main thread whenever `sample` or `failure` changes.
  @ObservationIgnored public var onUpdate: (() -> Void)?

  @ObservationIgnored private let queue = DispatchQueue(label: "macmon.sampler")
  /// Everything below is touched only on `queue`.
  @ObservationIgnored private var intervalMs: UInt32
  @ObservationIgnored private var running = false
  @ObservationIgnored private var stopped = false
  /// How many processes the panel shows. The rest never leaves the sampler: a whole process list
  /// is over a thousand rows and would be serialized every tick for nothing.
  @ObservationIgnored private static let topProcesses = 8

  public init(intervalMs: UInt32 = 1000) {
    self.intervalMs = max(100, intervalMs)
  }

  /// Polling interval in milliseconds; the loop picks a change up on its next tick.
  public func setInterval(_ ms: UInt32) {
    queue.async { self.intervalMs = max(100, ms) }
  }

  /// Start sampling and keep going until `stop()`. Does nothing when it is already running.
  public func start() {
    queue.async {
      guard !self.running else { return }
      self.running = true
      self.stopped = false
      var sampler: Sampler?
      var processSampler: ProcessSampler?

      while !self.stopped {
        do {
          if sampler == nil {
            let created = try Sampler()
            sampler = created
            self.publish(soc: try created.soc())
          }
          let next = try sampler?.next(durationMs: self.intervalMs)
          self.publish(sample: next, failure: nil)
        } catch {
          self.publish(sample: nil, failure: String(describing: error))
          // A sampler that cannot be created keeps failing: wait a beat instead of spinning.
          Thread.sleep(forTimeInterval: 1)
          continue
        }

        do {
          if processSampler == nil {
            let created = try ProcessSampler()
            try created.warmUp() // the first call of a sampler reports zero rates
            processSampler = created
          }
          self.publish(processes: try processSampler?.next(topN: Self.topProcesses) ?? [])
        } catch {
          // A process list that cannot be read leaves the metrics alone.
          self.publish(failure: String(describing: error))
        }
      }

      // Both samplers are released here, on the thread that created them.
      self.running = false
    }
  }

  /// Ask the loop to stop; it exits after the sample in flight (up to one interval).
  public func stop() {
    stopped = true
  }

  private func publish(processes: [Process]) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      self.processes = processes
      self.onUpdate?()
    }
  }

  private func publish(failure: String) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      self.failure = failure
      self.onUpdate?()
    }
  }

  private func publish(soc: SocInfo) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      self.soc = soc
      self.onUpdate?()
    }
  }

  private func publish(sample: Sample?, failure: String?) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      self.sample = sample
      self.failure = failure
      self.onUpdate?()
    }
  }
}
