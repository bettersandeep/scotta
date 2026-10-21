import Foundation

/// Limits Apple's manual charge limit (PowerUI) accepts on macOS 27.
public let mclSteps = [80, 85, 90, 95, 100]

/// What the system should be doing right now. Pure output of `decide`.
public struct Decision: Codable, Equatable, Sendable {
    public var mcl: Int?          // Apple charge limit (nil = disabled); macOS enforces it, even asleep
    public var inhibit = false    // CHIE: run from battery while plugged in
    public var holding = false    // software hold below the Apple limit is active
    public var led: UInt8 = 0     // ACLC: 0 system, 1 off, 2 green, 4 orange, 6 orange blinking
    public var keepAwake = false
    public var mode: Mode = .limit
    public var heatPaused = false
    public init() {}
}

public let calibrationHold: TimeInterval = 3600

/// The Apple limit to use as a ceiling for `target`.
public func ceiling(_ target: Int) -> Int { mclSteps.first { $0 >= target } ?? 100 }

public func decide(_ s: Settings, _ b: Battery, heatPaused wasHot: Bool, holding wasHolding: Bool, now: Date) -> Decision {
    var d = Decision()
    d.mode = advance(s.mode, s, b, now)

    let hot = s.heatProtect && b.tempC >= s.maxTempC
    let cooled = b.tempC <= s.maxTempC - 2
    d.heatPaused = s.heatProtect && (hot || (wasHot && !cooled))

    var target: Int?
    var drain = false
    switch d.mode {
    case .off: target = nil
    case .limit: target = s.limit
    case .pause(let at): target = at
    case .topUp, .calibrate(.charge, _), .calibrate(.recharge, _), .calibrate(.hold, _): target = 100
    case .discharge, .calibrate(.drain, _): target = s.limit; drain = true
    }

    if let t = target {
        d.mcl = ceiling(t)
        // Apple only holds at its own steps; anything else, and sailing, is held by running from battery.
        let sailing = d.mode == .limit && s.sailing > 0
        if !drain, t < ceiling(t) || sailing {
            let gap = sailing ? s.sailing : 1
            d.holding = b.plugged && (b.percent >= t || (wasHolding && b.percent > t - gap))
        }
    }
    d.inhibit = b.plugged && (drain || d.holding || d.heatPaused)

    switch s.led {
    case .system: d.led = 0
    case .off: d.led = 1
    case .indicate: d.led = !b.plugged ? 0 : drain ? 6 : b.charging ? 4 : 2
    }
    d.keepAwake = s.preventSleep && b.plugged && !d.inhibit && b.percent < (target ?? 100)
    return d
}

/// Mode transitions: one-shot modes finish and fall back to `.limit`.
func advance(_ m: Mode, _ s: Settings, _ b: Battery, _ now: Date) -> Mode {
    let full = b.full || b.percent >= 100
    switch m {
    case .topUp: return full ? .limit : m
    case .discharge: return b.percent <= s.limit ? .limit : m
    case .calibrate(.charge, _): return full ? .calibrate(.drain, since: now) : m
    case .calibrate(.drain, _): return b.percent <= 10 ? .calibrate(.recharge, since: now) : m
    case .calibrate(.recharge, _): return full ? .calibrate(.hold, since: now) : m
    case .calibrate(.hold, let t): return now.timeIntervalSince(t) >= calibrationHold ? .discharge : m
    case .off, .limit, .pause: return m
    }
}
