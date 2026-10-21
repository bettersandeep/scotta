import Foundation

public enum Phase: String, Codable, Sendable { case charge, drain, recharge, hold }

public enum Mode: Codable, Equatable, Sendable {
    case off                              // firmware limiter disabled, macOS default behaviour
    case limit                            // hold at settings.limit
    case pause(at: Int)                   // hold at the percentage pause was pressed
    case topUp                            // charge to 100 once, then back to limit
    case discharge                        // run from battery while plugged in, down to limit
    case calibrate(Phase, since: Date)    // 100 -> 10 -> 100 -> hold 1h -> limit
}

public enum LED: String, Codable, CaseIterable, Sendable { case system, off, indicate }

/// pmset `powermode`: 0 automatic, 1 low power, 2 high power.
public enum PowerMode: Int, Codable, CaseIterable, Sendable { case auto = 0, low = 1, high = 2 }

public struct Settings: Codable, Equatable, Sendable {
    public var mode: Mode = .limit
    public var limit = 80
    public var sailing = 0                // extra % to drift below limit before charging resumes
    public var heatProtect = false
    public var maxTempC = 35.0
    public var led: LED = .system
    public var preventSleep = false       // keep awake while charging up to the limit
    public var powerBattery: PowerMode = .auto
    public var powerAdapter: PowerMode = .auto
    public init() {}
}

public enum Command: Codable, Sendable {
    case limit(Int), pause, topUp, discharge, calibrate, normal, off
    case sailing(Int), heat(Bool, Double), led(LED), preventSleep(Bool)
    case powerMode(battery: PowerMode, adapter: PowerMode)
    case reset                            // restore firmware defaults and stop controlling
}

public struct Battery: Codable, Equatable, Sendable {
    public var percent = 0
    public var plugged = false
    public var charging = false
    public var full = false
    public var tempC = 0.0
    public var voltageMV = 0
    public var amperageMA = 0
    public var cycles = 0
    public var designMAh = 0
    public var maxMAh = 0
    public var adapterW = 0
    public var systemW = 0.0
    public var minutesLeft: Int?
    public var health: Double { designMAh > 0 ? min(Double(maxMAh) / Double(designMAh), 1) : 0 }
    public init() {}
}

public struct Status: Codable, Sendable {
    public var settings: Settings
    public var battery: Battery
    public var decision: Decision
    public var smcError: String?
    public init(settings: Settings, battery: Battery, decision: Decision, smcError: String?) {
        self.settings = settings; self.battery = battery; self.decision = decision; self.smcError = smcError
    }
}

public extension JSONEncoder { static let scotta: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }() }
public extension JSONDecoder { static let scotta: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }() }
