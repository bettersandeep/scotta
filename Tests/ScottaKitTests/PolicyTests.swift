import Foundation
import ScottaKit
import Testing

private func battery(_ pct: Int, plugged: Bool = true, charging: Bool = false, temp: Double = 30) -> Battery {
    var b = Battery(); b.percent = pct; b.plugged = plugged; b.charging = charging; b.tempC = temp; b.full = pct >= 100
    return b
}

private let now = Date(timeIntervalSince1970: 1_000_000)

private func run(_ s: Settings, _ b: Battery, hot: Bool = false, holding: Bool = false, at t: Date = now) -> Decision {
    decide(s, b, heatPaused: hot, holding: holding, now: t)
}

@Test func appleStepsNeedNoSoftwareHold() {
    var s = Settings(); s.limit = 85
    let d = run(s, battery(85))
    #expect(d.mcl == 85 && !d.inhibit && !d.holding)
}

@Test func lowLimitHeldBySoftwareUnderAppleCeiling() {
    var s = Settings(); s.limit = 60
    #expect(run(s, battery(50)).mcl == 80)
    #expect(!run(s, battery(59)).inhibit)
    let held = run(s, battery(60))
    #expect(held.holding && held.inhibit)
    #expect(!run(s, battery(59), holding: true).inhibit)     // resumes one point below
    #expect(!run(s, battery(70, plugged: false)).inhibit)     // nothing to inhibit on battery
}

@Test func sailingDriftsBeforeCharging() {
    var s = Settings(); s.limit = 80; s.sailing = 5
    #expect(run(s, battery(80)).inhibit)
    #expect(run(s, battery(76), holding: true).inhibit)
    #expect(!run(s, battery(75), holding: true).inhibit)
    #expect(!run(s, battery(78)).inhibit)                     // not holding yet: charge up first
}

@Test func offDisablesAppleLimit() {
    var s = Settings(); s.mode = .off
    let d = run(s, battery(50))
    #expect(d.mcl == nil && !d.inhibit)
}

@Test func topUpFinishesAtFull() {
    var s = Settings(); s.mode = .topUp
    #expect(run(s, battery(90)).mcl == 100)
    #expect(run(s, battery(100)).mode == .limit)
}

@Test func dischargeStopsAtLimit() {
    var s = Settings(); s.limit = 60; s.mode = .discharge
    #expect(run(s, battery(70)).inhibit)
    let d = run(s, battery(60))
    #expect(d.mode == .limit && d.holding)                    // then holds at the limit
}

@Test func heatPauseHasHysteresis() {
    var s = Settings(); s.heatProtect = true; s.maxTempC = 35
    let hot = run(s, battery(50, charging: true, temp: 36))
    #expect(hot.heatPaused && hot.inhibit)
    #expect(run(s, battery(50, temp: 34), hot: true).heatPaused)    // not cooled enough
    #expect(!run(s, battery(50, temp: 32.9), hot: true).heatPaused)
}

@Test func calibrationRunsAllPhases() {
    var s = Settings(); s.limit = 80
    s.mode = .calibrate(.charge, since: now)
    s.mode = run(s, battery(100)).mode
    #expect(s.mode == .calibrate(.drain, since: now))
    #expect(run(s, battery(50)).inhibit)
    s.mode = run(s, battery(10)).mode
    #expect(s.mode == .calibrate(.recharge, since: now))
    s.mode = run(s, battery(100)).mode
    #expect(s.mode == .calibrate(.hold, since: now))
    #expect(run(s, battery(100), at: now + 3599).mode == s.mode)
    #expect(run(s, battery(100), at: now + 3600).mode == .discharge)
}

@Test func ledIndicatesState() {
    var s = Settings(); s.led = .indicate
    #expect(run(s, battery(50, charging: true)).led == 4)
    #expect(run(s, battery(80)).led == 2)
    #expect(run(s, battery(80, plugged: false)).led == 0)
    s.mode = .discharge
    #expect(run(s, battery(90)).led == 6)
}

@Test func parsesCliAndUrlWords() {
    guard case .limit(70)? = Command.parse(["limit", "70"]) else { Issue.record("limit"); return }
    guard case .powerMode(.low, .high)? = Command.parse(["powermode", "low", "high"]) else { Issue.record("powermode"); return }
    #expect(Command.parse(["limit"]) == nil)
}
