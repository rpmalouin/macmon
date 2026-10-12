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
/// Everything below is always present in a document, so a decode failure means the ABI changed
/// shape and should be seen rather than silently defaulted.
public struct Sample: Decodable, Equatable {
  /// Memory and swap, in bytes.
  public struct Memory: Decodable, Equatable {
    public let ramTotal: UInt64
    public let ramUsage: UInt64
    /// What the kernel can still hand out without compressing or swapping.
    public let ramAvailable: UInt64
    public let swapTotal: UInt64
    public let swapUsage: UInt64

    /// Used memory as a fraction of the installed memory, 0...1.
    public var ramFraction: Double {
      ramTotal == 0 ? 0 : Double(ramUsage) / Double(ramTotal)
    }

    /// Memory still available as a fraction of the installed memory, 0...1.
    ///
    /// This, not [`ramFraction`], is the pressure figure: `ramUsage` counts reclaimable `inactive`
    /// pages, so it reads 87–92% on a machine holding a resident local model while nothing is wrong.
    public var availableFraction: Double {
      ramTotal == 0 ? 0 : Double(ramAvailable) / Double(ramTotal)
    }

    /// Used swap as a fraction of the configured swap, 0...1.
    public var swapFraction: Double {
      swapTotal == 0 ? 0 : Double(swapUsage) / Double(swapTotal)
    }
  }

  /// Average temperatures in Celsius; nil when the sensor is unavailable, as in a VM.
  public struct Temperature: Decodable, Equatable {
    public let cpuTempAvg: Double?
    public let gpuTempAvg: Double?
  }

  public struct Fan: Decodable, Equatable {
    public let name: String
    public let rpm: UInt32
    public let maxRpm: UInt32?
  }

  /// One core of a CPU tier.
  public struct Core: Decodable, Equatable {
    public let dieId: Int
    public let coreId: Int
    /// Average frequency while the core was active.
    public let freqMhz: UInt32
    public let scaledRatio: Double
    public let activeRatio: Double
  }

  /// One CPU tier (core type): `E`, `P` or `S`, or `_` when the core type is unknown.
  public struct Tier: Decodable, Equatable {
    public let label: String
    public let freqMhz: UInt32
    public let scaledRatio: Double
    public let activeRatio: Double
    public let cores: [Core]
  }

  /// Unix epoch seconds.
  public let timestamp: Double
  /// Frequency-weighted active residency across all cores, 0...1.
  public let cpuScaledRatio: Double
  public let cpuActiveRatio: Double
  public let cpuTiers: [Tier]
  public let cpuPower: Double
  public let gpuScaledRatio: Double
  public let gpuFreqMhz: UInt32
  public let gpuActiveRatio: Double
  public let gpuPower: Double
  public let anePower: Double
  /// CPU, GPU and ANE together.
  public let allPower: Double
  /// System power estimate, 0 when unavailable.
  public let sysPower: Double
  public let ramPower: Double
  public let gpuRamPower: Double
  public let temp: Temperature
  public let memory: Memory
  public let fans: [Fan]
}

/// Static machine information, read once: the panel labels itself with the chip name.
public struct SocInfo: Decodable, Equatable {
  public let macModel: String
  public let chipName: String
  public let memoryGb: Int
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
    let json = try document { macmon_sampler_next(handle, durationMs) }
    do {
      return try Self.decoder.decode(Sample.self, from: Data(json.utf8))
    } catch {
      throw MacmonError(message: "decoding a sample: \(error)")
    }
  }

  /// Static machine information, which does not change while the sampler lives.
  public func soc() throws -> SocInfo {
    let json = try document { macmon_sampler_soc_json(handle) }
    do {
      return try Self.decoder.decode(SocInfo.self, from: Data(json.utf8))
    } catch {
      throw MacmonError(message: "decoding the soc information: \(error)")
    }
  }

  /// Run one C call, take its string and release it.
  private func document(_ call: () -> UnsafeMutablePointer<CChar>?) throws -> String {
    guard handle != nil else { throw MacmonError(message: "sampler is not alive") }
    guard let raw = call() else { throw MacmonError(message: Self.lastError()) }
    defer { macmon_free(UnsafeMutableRawPointer(raw)) }
    return String(cString: raw)
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
