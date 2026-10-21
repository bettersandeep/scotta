import Foundation
import IOKit

public extension Battery {
    /// Reads AppleSmartBattery from the IORegistry. Unprivileged and cheap.
    static func read() -> Battery {
        var b = Battery()
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard svc != 0 else { return b }
        defer { IOObjectRelease(svc) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let d = props?.takeRetainedValue() as? [String: Any] else { return b }
        func int(_ k: String, in dict: [String: Any] = d) -> Int { (dict[k] as? NSNumber)?.intValue ?? 0 }
        b.percent = int("CurrentCapacity")
        b.plugged = d["ExternalConnected"] as? Bool ?? false
        b.charging = d["IsCharging"] as? Bool ?? false
        b.full = d["FullyCharged"] as? Bool ?? false
        b.tempC = Double(int("Temperature")) / 100   // absent on macOS 27; the daemon fills it from SMC
        b.voltageMV = int("Voltage")
        b.amperageMA = Int(Int16(truncatingIfNeeded: int("Amperage")))
        b.cycles = int("CycleCount")
        // macOS 27 moved capacities into BatteryData.
        let data = d["BatteryData"] as? [String: Any] ?? d
        b.designMAh = int("DesignCapacity", in: data)
        b.maxMAh = int("FullChargeCapacity", in: data)
        if let a = d["AdapterDetails"] as? [String: Any] { b.adapterW = int("Watts", in: a) }
        if let t = d["PowerTelemetryData"] as? [String: Any] { b.systemW = Double(int("SystemPowerIn", in: t)) / 1000 }
        // Only meaningful while draining, or while actually charging.
        let left = b.plugged ? (b.charging ? int("AvgTimeToFull") : 0) : int("AvgTimeToEmpty")
        b.minutesLeft = left > 0 && left < 0xFFFF ? left : nil
        return b
    }
}
