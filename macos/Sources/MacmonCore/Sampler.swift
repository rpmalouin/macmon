import CMacmon
import Foundation

/// A failure reported by the C ABI, or by decoding its document.
public struct MacmonError: Error, CustomStringConvertible {
  public let message: String
  public var description: String { message }
}

/// One sample, decoded from the C ABI's document.
///
/// Only the fields the app reads are declared here. The document carries more, under the same
/// names `macmon pipe` uses, minus that command's deprecated v0.7 aliases (`ffi/include/macmon.h`).
public struct Sample: Decodable, Equatable {
  public struct Memory: Decodable, Equatable {
    public let ramTotal: UInt64
    public let ramUsage: UInt64
    public let swapTotal: UInt64
    public let swapUsage: UInt64

    /// Used memory as a fraction of the installed memory, 0...1.
    public var ramFraction: Double {
      ramTotal == 0 ? 0 : Double(ramUsage) / Double(ramTotal)
    }
  }

  /// Unix epoch seconds.
  public let timestamp: Double
  /// Frequency-weighted active residency across all cores, 0...1.
  public let cpuScaledRatio: Double
  public let memory: Memory
}

/// The sampler behind the C ABI. It owns low-level macOS handles, so it belongs to one thread:
/// create it, sample it and release it on the same one (see `Monitor`).
public final class Sampler {
  private var handle: UnsafeMutableRawPointer?

  /// Create a sampler, or throw with the C side's reason.
  public init() throws {
    guard let handle = macmon_sampler_new() else { throw MacmonError(message: Self.lastError()) }
    self.handle = handle
  }

  deinit {
    if let handle { macmon_sampler_free(handle) }
  }

  /// Take one sample, waiting `durationMs`, and decode it.
  ///
  /// The sampler keeps its baseline between calls, so call this in a loop: the interval between
  /// two calls is the interval the metrics describe.
  public func next(durationMs: UInt32) throws -> Sample {
    guard let handle else { throw MacmonError(message: "sampler is not alive") }
    guard let raw = macmon_sampler_next(handle, durationMs) else {
      throw MacmonError(message: Self.lastError())
    }
    defer { macmon_free(UnsafeMutableRawPointer(raw)) }

    do {
      return try Self.decoder.decode(Sample.self, from: Data(String(cString: raw).utf8))
    } catch {
      throw MacmonError(message: "decoding a sample: \(error)")
    }
  }

  /// The reason the last call failed, or a placeholder when the C side has none.
  private static func lastError() -> String {
    guard let raw = macmon_last_error() else { return "unknown error" }
    let text = String(cString: raw)
    return text.isEmpty ? "unknown error" : text
  }

  /// Internal so a test can decode a captured document without a sampler.
  static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }()
}
