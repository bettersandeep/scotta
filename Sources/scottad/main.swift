import CSMC
import Foundation
import IOKit.ps
import IOKit.pwr_mgt
import ScottaKit
import Security

let settingsURL = URL(fileURLWithPath: "/Library/Application Support/Scotta/settings.json")

func log(_ s: String) { FileHandle.standardError.write(Data("\(Date()) \(s)\n".utf8)) }

/// Team ID from the daemon's own signature; nil when unsigned.
func ownTeamID() -> String? {
    var code: SecCode?, staticCode: SecStaticCode?, info: CFDictionary?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
          SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
          SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
    else { return nil }
    return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
}
let teamID = ownTeamID()

/// All state lives on the main queue: XPC handlers, the power-source callback and the timer hop onto it.
final class Controller: NSObject, ScottaXPC, NSXPCListenerDelegate {
    var settings = Settings()
    var applied: Decision?
    var heatPaused = false
    var holding = false
    var smcError: String?
    var last = Decision()

    override init() {
        super.init()
        if let data = try? Data(contentsOf: settingsURL),
           let s = try? JSONDecoder.scotta.decode(Settings.self, from: data) { settings = s }
    }

    func save() {
        try? FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder.scotta.encode(settings).write(to: settingsURL, options: .atomic)
    }

    /// IORegistry battery plus the SMC battery temperature (not in the registry on macOS 27).
    func battery() -> Battery {
        var b = Battery.read()
        var buf = [UInt8](repeating: 0, count: 32); var n: UInt32 = 0
        if b.tempC == 0, smc_read("TB0T", &buf, &n) == 0, n == 4 {
            b.tempC = Double(buf.withUnsafeBytes { Float(bitPattern: UInt32(littleEndian: $0.load(as: UInt32.self))) })
        }
        return b
    }

    func evaluate() {
        let b = battery()
        let d = decide(settings, b, heatPaused: heatPaused, holding: holding, now: Date())
        heatPaused = d.heatPaused
        holding = d.holding
        if d.mode != settings.mode { settings.mode = d.mode; save() }
        if d != applied { apply(d) }
        last = d
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(changedNotification as CFString), nil, nil, true)
    }

    // MARK: firmware

    func write(_ key: String, _ bytes: [UInt8]) -> Bool {
        let r = smc_write(key, bytes, UInt32(bytes.count))
        if r != 0 { smcError = "write \(key) failed: \(r)"; log(smcError!) }
        return r == 0
    }

    func apply(_ d: Decision) {
        smcError = nil
        var ok = true
        if applied?.mcl != d.mcl {
            let r = d.mcl.map { pui_set_limit(Int32($0)) } ?? pui_disable()
            if r != 0 { smcError = "Apple charge limit \(d.mcl.map(String.init) ?? "off") failed: \(r)"; log(smcError!); ok = false }
        }
        if applied?.inhibit != d.inhibit { ok = write("CHIE", [d.inhibit ? 8 : 0]) && ok }
        if applied?.led != d.led { ok = write("ACLC", [d.led]) && ok }
        if applied?.keepAwake != d.keepAwake { setSleepDisabled(d.keepAwake) }
        applied = ok ? d : nil   // on failure, retry everything at the next event
        log("applied mcl=\(d.mcl.map(String.init) ?? "off") inhibit=\(d.inhibit) holding=\(d.holding) led=\(d.led) awake=\(d.keepAwake) mode=\(d.mode) ok=\(ok)")
    }

    /// Never sleep while running from battery on purpose: hand back to the Apple ceiling instead.
    func willSleep() {
        if applied?.inhibit != false, write("CHIE", [0]) { applied?.inhibit = false }
    }

    func setSleepDisabled(_ on: Bool) {
        let r = pm_set_sleep_disabled(on ? 1 : 0)
        if r != 0 { log("SleepDisabled=\(on) failed: \(r)") }
    }

    func pmset(_ flag: String, _ mode: PowerMode) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = [flag, "powermode", String(mode.rawValue)]
        try? p.run(); p.waitUntilExit()
    }

    // MARK: commands

    func handle(_ c: Command) -> String? {
        let b = battery()
        switch c {
        case .limit(let n):
            guard (10...100).contains(n) else { return "limit must be 10...100" }
            settings.limit = n
            switch settings.mode { case .pause, .off, .topUp: settings.mode = .limit; default: break }
        case .pause: settings.mode = .pause(at: max(b.percent, 10))
        case .topUp: settings.mode = .topUp
        case .discharge:
            guard b.percent > settings.limit else { return "battery is already at or below the limit" }
            settings.mode = .discharge
        case .calibrate: settings.mode = .calibrate(.charge, since: Date())
        case .normal: settings.mode = .limit
        case .off: settings.mode = .off
        case .sailing(let n):
            guard (0...30).contains(n) else { return "sailing must be 0...30" }
            settings.sailing = n
        case .heat(let on, let max):
            guard (25...50).contains(max) else { return "max temperature must be 25...50 C" }
            settings.heatProtect = on; settings.maxTempC = max
        case .led(let l): settings.led = l
        case .preventSleep(let on): settings.preventSleep = on
        case .powerMode(let bat, let ac):
            pmset("-b", bat); pmset("-c", ac)
            settings.powerBattery = bat; settings.powerAdapter = ac
        case .reset:
            settings.mode = .off; settings.led = .system; settings.preventSleep = false; settings.sailing = 0
            applied = nil
        }
        save()
        evaluate()
        return smcError
    }

    // MARK: XPC

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection c: NSXPCConnection) -> Bool {
        guard let teamID else { return false }   // unsigned daemon: refuse everyone rather than trust anyone
        c.setCodeSigningRequirement(clientRequirement(team: teamID))
        c.exportedInterface = NSXPCInterface(with: ScottaXPC.self)
        c.exportedObject = self
        c.resume()
        return true
    }

    func status(reply: @escaping (Data) -> Void) {
        DispatchQueue.main.async {
            let s = Status(settings: self.settings, battery: self.battery(), decision: self.last, smcError: self.smcError)
            reply((try? JSONEncoder.scotta.encode(s)) ?? Data())
        }
    }

    func send(_ command: Data, reply: @escaping (String?) -> Void) {
        DispatchQueue.main.async {
            guard let c = try? JSONDecoder.scotta.decode(Command.self, from: command) else { return reply("bad command") }
            reply(self.handle(c))
        }
    }
}

// MARK: startup

let r = smc_open()
guard r == 0 else { log("cannot open AppleSMC: \(r)"); exit(1) }
for key in ["CHIE", "ACLC", "TB0T"] {
    var buf = [UInt8](repeating: 0, count: 32); var n: UInt32 = 0
    let e = smc_read(key, &buf, &n)
    log("startup \(key) = \(e == 0 ? buf.prefix(Int(n)).map { String(format: "%02x", $0) }.joined(separator: " ") : "error \(e)")")
}
var mclOn: Int32 = 0, mclLimit: Int32 = 0
log("startup Apple charge limit: result \(pui_get(&mclOn, &mclLimit)) enabled=\(mclOn) limit=\(mclLimit)")

log("startup accepting clients from team \(teamID ?? "none (unsigned daemon, all clients refused)")")
let controller = Controller()
controller.setSleepDisabled(false)   // never inherit a stale keep-awake from a crash

let source = IOPSNotificationCreateRunLoopSource({ _ in controller.evaluate() }, nil).takeRetainedValue()
CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)

// Power-source events cover charge changes; the timer covers temperature and the calibration hold.
let timer = DispatchSource.makeTimerSource(queue: .main)
timer.schedule(deadline: .now() + 60, repeating: 60, leeway: .seconds(10))
timer.setEventHandler { controller.evaluate() }
timer.resume()

// Sleep/wake: release CHIE before sleep, re-evaluate on wake.
// iokit_common_msg() values; the C macros do not import into Swift.
let kIOMessageCanSystemSleep: UInt32 = 0xE000_0270
let kIOMessageSystemWillSleep: UInt32 = 0xE000_0280
let kIOMessageSystemHasPoweredOn: UInt32 = 0xE000_0300
var rootPort: io_connect_t = 0
var notifier: io_object_t = 0
var notifyPort: IONotificationPortRef?
rootPort = IORegisterForSystemPower(nil, &notifyPort, { _, _, type, arg in
    switch type {
    case kIOMessageSystemWillSleep: controller.willSleep(); IOAllowPowerChange(rootPort, Int(bitPattern: arg))
    case kIOMessageCanSystemSleep: IOAllowPowerChange(rootPort, Int(bitPattern: arg))
    case kIOMessageSystemHasPoweredOn: controller.evaluate()
    default: break
    }
}, &notifier)
IONotificationPortSetDispatchQueue(notifyPort, .main)

let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
signal(SIGTERM, SIG_IGN)
term.setEventHandler {
    // Keep the firmware limit (it protects the battery while we are gone); undo anything that needs us.
    if controller.applied?.inhibit != false { _ = controller.write("CHIE", [0]) }
    controller.setSleepDisabled(false)
    exit(0)
}
term.resume()

let listener = NSXPCListener(machServiceName: daemonService)
listener.delegate = controller
listener.resume()

controller.evaluate()
RunLoop.main.run()
