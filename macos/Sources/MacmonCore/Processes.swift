import CMacmon
import Foundation

/// One row of the process list, decoded from the C ABI.
public struct Process: Decodable, Equatable {
  public let pid: Int32
  public let name: String
  public let user: String
  /// 100% is one busy core, as in Activity Monitor.
  public let cpuPct: Double
  public let memBytes: UInt64
  /// Watts, nil when the energy counter is not readable: another user's process, or macOS before 13.
  public let powerW: Double?
  /// Share of the interval the GPU spent on the process, 0...100.
  public let gpuPct: Double
}

/// The process sampler behind the C ABI. Like `Sampler`, it belongs to one thread.
public final class ProcessSampler {
  private var handle: UnsafeMutableRawPointer?

  /// Create a sampler, or throw with the C side's reason.
  public init() throws {
    guard let handle = macmon_procs_new() else { throw MacmonError(message: Self.lastError()) }
    self.handle = handle
  }

  deinit {
    if let handle { macmon_procs_free(handle) }
  }

  /// Sample every process and decode the busiest `topN`, busiest first; 0 is every process.
  ///
  /// CPU and power are rates since the previous call, so a sampler's first call reports them as
  /// zero: call `warmUp()` once after creating it rather than publishing those zeros.
  public func next(topN: Int = 0) throws -> [Process] {
    guard let handle else { throw MacmonError(message: "process sampler is not alive") }
    guard let raw = macmon_procs_next(handle, UInt32(max(0, topN))) else {
      throw MacmonError(message: Self.lastError())
    }
    defer { macmon_free(UnsafeMutableRawPointer(raw)) }

    do {
      return try Sampler.decoder.decode([Process].self, from: Data(String(cString: raw).utf8))
    } catch {
      throw MacmonError(message: "decoding the process list: \(error)")
    }
  }

  /// Take the baseline call, whose rates are zero, so the next one reports real rates.
  public func warmUp() throws {
    _ = try next(topN: 0)
  }

  /// The reason the last call failed, or a placeholder when the C side has none.
  private static func lastError() -> String {
    guard let raw = macmon_last_error() else { return "unknown error" }
    let text = String(cString: raw)
    return text.isEmpty ? "unknown error" : text
  }
}
