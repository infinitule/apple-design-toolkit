import Foundation

/// Parsing traps for the companion telemetry governor. The skill documents
/// two ioreg pitfalls: nested dictionaries repeat key names (so a naive
/// "find InstantAmperage anywhere" walk double-counts), and InstantAmperage
/// is unsigned two's complement (an unguarded Int64 read reports drain in
/// quintillions of watts).
public enum BatteryTelemetry {
    public struct Sample: Equatable {
        public var volts: Double          // V
        public var amperes: Double        // A (negative = discharge)
        public var watts: Double { volts * amperes }
        public var percent: Int?
    }

    /// Decode InstantAmperage from the raw unsigned value ioreg reports.
    /// Values above 2^63 - 1 are negative currents in two's complement.
    public static func signedAmperage(_ raw: UInt64) -> Int64 {
        if raw > UInt64(Int64.max) {
            return Int64(bitPattern: raw)
        }
        return Int64(raw)
    }

    /// Threshold from the skill: subtract 2^64 if > 9.2e18.
    public static let unsignedThreshold: UInt64 = 9_200_000_000_000_000_000

    public static func amperes(fromInstant raw: UInt64, milli: Bool = true) -> Double {
        let signed = signedAmperage(raw)
        let a = Double(signed)
        return milli ? a / 1000 : a
    }

    /// Walk only top-level keys of an ioreg -rn AppleSmartBattery dump.
    /// Nested dicts are ignored so InstantAmperage / Voltage are not taken
    /// from a child that repeats those names.
    public static func parseIORegTopLevel(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        var depth = 0
        for line in text.split(whereSeparator: \.isNewline) {
            let s = String(line)
            // Depth before this line's braces: a one-line nested dict
            // ("Nested" = {...}) must not count as a top-level key.
            let lineDepth = depth
            depth += s.filter { $0 == "{" || $0 == "(" }.count
            depth -= s.filter { $0 == "}" || $0 == ")" }.count
            guard lineDepth == 1 else { continue }
            guard let eq = s.firstIndex(of: "=") else { continue }
            let left = s[..<eq].trimmingCharacters(in: .whitespaces)
            let right = s[s.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            guard left.hasPrefix("\""), left.hasSuffix("\"") else { continue }
            if right.contains("{") || right.contains("(") { continue }
            let key = String(left.dropFirst().dropLast())
            out[key] = right.hasSuffix(",") ? String(right.dropLast()) : right
        }
        return out
    }

    public static func sample(fromIOReg text: String) -> Sample? {
        let kv = parseIORegTopLevel(text)
        guard let vRaw = kv["Voltage"], let aRaw = kv["InstantAmperage"] else { return nil }
        let volts = (Double(vRaw.trimmingCharacters(in: CharacterSet(charactersIn: " \""))) ?? 0) / 1000
        let ampsRaw = UInt64(aRaw.trimmingCharacters(in: CharacterSet(charactersIn: " \""))) ?? 0
        let pct = kv["CurrentCapacity"].flatMap { Int($0.trimmingCharacters(in: CharacterSet(charactersIn: " \""))) }
        return Sample(volts: volts, amperes: amperes(fromInstant: ampsRaw), percent: pct)
    }
}

/// One-dimensional Kalman filter used by the governor to smooth wattage.
/// State is persisted in a root-owned file between StartInterval wakes.
public struct Kalman1D: Equatable {
    public var estimate: Double
    public var error: Double
    public var processNoise: Double
    public var measurementNoise: Double

    public init(estimate: Double = 0, error: Double = 1,
                processNoise: Double = 0.05, measurementNoise: Double = 0.8) {
        self.estimate = estimate; self.error = error
        self.processNoise = processNoise; self.measurementNoise = measurementNoise
    }

    public mutating func update(_ measurement: Double) -> Double {
        let priorError = error + processNoise
        let k = priorError / (priorError + measurementNoise)
        estimate = estimate + k * (measurement - estimate)
        error = (1 - k) * priorError
        return estimate
    }

    /// `estimate error processNoise measurementNoise` on one line.
    public func serialize() -> String {
        "\(estimate) \(error) \(processNoise) \(measurementNoise)\n"
    }

    public static func deserialize(_ s: String) -> Kalman1D? {
        let parts = s.split(whereSeparator: \.isWhitespace).compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        return Kalman1D(estimate: parts[0], error: parts[1],
                        processNoise: parts[2], measurementNoise: parts[3])
    }
}
