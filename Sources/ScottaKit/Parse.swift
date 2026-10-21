import Foundation

public extension Command {
    /// Parses CLI words or URL parts, e.g. ["limit", "80"] or scotta://limit/80.
    static func parse(_ a: [String]) -> Command? {
        func int(_ i: Int) -> Int? { a.count > i ? Int(a[i]) : nil }
        func on(_ i: Int) -> Bool? { a.count > i ? ["on": true, "off": false][a[i]] : nil }
        func pm(_ i: Int) -> PowerMode? { a.count > i ? ["auto": .auto, "low": .low, "high": .high][a[i]] : nil }
        switch a.first {
        case "limit": return int(1).map(Command.limit)
        case "normal": return .normal
        case "pause": return .pause
        case "topup": return .topUp
        case "discharge": return .discharge
        case "calibrate": return .calibrate
        case "off": return .off
        case "reset": return .reset
        case "sailing": return int(1).map(Command.sailing)
        case "heat": return on(1).map { .heat($0, a.count > 2 ? Double(a[2]) ?? 35 : 35) }
        case "led": return a.count > 1 ? LED(rawValue: a[1]).map(Command.led) : nil
        case "sleep": return on(1).map(Command.preventSleep)
        case "powermode": return pm(1).flatMap { b in pm(2).map { .powerMode(battery: b, adapter: $0) } }
        default: return nil
        }
    }
}
