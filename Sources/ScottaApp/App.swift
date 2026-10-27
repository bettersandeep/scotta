import AppKit
import Combine
import ScottaKit
import ServiceManagement
import SwiftUI

@main
struct ScottaApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            Panel(model: .shared)
        } label: {
            MenuLabel(model: .shared)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuLabel: View {
    @ObservedObject var model: Model
    var body: some View {
        Image(nsImage: MenuIcon.image(percent: model.status?.battery.percent ?? 0, badge: model.badge))
        if let p = model.status?.battery.percent { Text("\(p)%") }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// scotta://limit/80, scotta://pause, scotta://led/indicate ...
    func application(_ app: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let host = url.host(), let cmd = Command.parse([host] + url.pathComponents.filter { $0 != "/" }) else { continue }
            Model.shared.send(cmd)
        }
    }
}

@MainActor
final class Model: ObservableObject {
    static let shared = Model()

    @Published var status: Status?
    @Published var error: String?
    @Published var power: [(Date, Double)] = []     // system power samples, last 10 minutes
    private let client = DaemonClient()

    private init() {
        // The daemon posts this after every evaluation, so the UI is push-driven.
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil, { _, _, _, _, _ in
            DispatchQueue.main.async { Model.shared.refresh() }
        }, changedNotification as CFString, nil, .deliverImmediately)
        refresh()
    }

    func refresh() {
        client.status { r in
            DispatchQueue.main.async {
                switch r {
                case .success(let s):
                    self.status = s
                    self.error = s.smcError
                    let now = Date()
                    self.power.append((now, s.battery.systemW))
                    self.power.removeAll { now.timeIntervalSince($0.0) > 600 }
                case .failure(let e): self.error = e.localizedDescription
                }
            }
        }
    }

    func send(_ c: Command) {
        client.send(c) { err in
            DispatchQueue.main.async { self.error = err; self.refresh() }
        }
    }

    /// State drawn inside the menu-bar battery; nil on battery power with nothing special going on.
    var badge: String? {
        guard let s = status else { return "exclamationmark" }
        switch s.decision.mode {
        case .discharge, .calibrate(.drain, _): return "arrow.down"
        default: break
        }
        if s.decision.heatPaused { return "thermometer.medium" }
        if s.battery.charging { return "bolt.fill" }
        guard s.battery.plugged else { return nil }
        if case .off = s.decision.mode { return "powerplug.fill" }
        return "pause.fill"
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            objectWillChange.send()
        }
    }
}
