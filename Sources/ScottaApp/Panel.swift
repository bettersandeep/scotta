import Charts
import Combine
import ScottaKit
import SwiftUI

struct Panel: View {
    @ObservedObject var model: Model
    @StateObject private var draft = Draft()
    @AppStorage("showStats") private var showStats = false
    private let tick = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let s = model.status {
                header(s)
                Divider()
                limitRow(s)
                modes(s)
                Divider()
                options(s.settings)
                Divider()
                DisclosureGroup("Stats", isExpanded: $showStats) { stats(s.battery) }
            } else {
                Text("Connecting to the Scotta daemon…").foregroundStyle(.secondary)
            }
            if let e = model.error { Text(e).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            Divider()
            HStack {
                Toggle("Launch at login", isOn: $model.launchAtLogin).toggleStyle(.checkbox)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { model.refresh() }
        .onReceive(tick) { _ in if showStats { model.refresh() } }
        .onChange(of: model.status?.settings.limit, initial: true) { _, v in if let v { draft.limit = Double(v) } }
    }

    private func header(_ s: Status) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(s.battery.percent)%").font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
            VStack(alignment: .leading, spacing: 2) {
                Text(state(s)).font(.headline)
                Text(s.battery.plugged ? "On power adapter\(s.battery.adapterW > 0 ? " · \(s.battery.adapterW) W" : "")" : "On battery")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func state(_ s: Status) -> String {
        let d = s.decision, b = s.battery
        if d.heatPaused { return "Paused: battery too warm" }
        switch d.mode {
        case .off: return "Not controlling"
        case .limit: return !b.plugged ? "Limit \(s.settings.limit)%" : b.charging ? "Charging to \(s.settings.limit)%" : "Holding at \(s.settings.limit)%"
        case .pause(let at): return "Paused at \(at)%"
        case .topUp: return "Topping up to 100%"
        case .discharge: return "Discharging to \(s.settings.limit)%"
        case .calibrate(let p, _):
            return switch p {
            case .charge: "Calibrating: charging to 100%"
            case .drain: "Calibrating: draining to 10%"
            case .recharge: "Calibrating: charging to 100% again"
            case .hold: "Calibrating: holding at 100%"
            }
        }
    }

    private var limit: Int { Int(draft.limit.rounded()) }

    private func limitRow(_ s: Status) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Charge limit")
                Spacer()
                Text("\(limit)%").monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $draft.limit, in: 10...100) { editing in
                if !editing { model.send(.limit(limit)) }
            }
            if !mclSteps.contains(limit) {
                Text("macOS only holds 80, 85, 90, 95 or 100%. Scotta holds \(limit)% while awake, and macOS holds \(ceiling(limit))% while asleep.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func modes(_ s: Status) -> some View {
        let m = s.decision.mode
        func active(_ c: Command) -> Bool {
            switch (c, m) {
            case (.pause, .pause), (.topUp, .topUp), (.discharge, .discharge), (.calibrate, .calibrate), (.normal, .limit), (.off, .off): true
            default: false
            }
        }
        let items: [(String, String, Command)] = [
            ("Limit", "gauge.with.dots.needle.67percent", .normal), ("Pause", "pause.fill", .pause),
            ("Top up", "bolt.fill", .topUp), ("Discharge", "arrow.down", .discharge),
            ("Calibrate", "arrow.triangle.2.circlepath", .calibrate), ("Off", "power", .off),
        ]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(items, id: \.0) { title, icon, cmd in
                let button = Button { model.send(cmd) } label: {
                    Label(title, systemImage: icon).frame(maxWidth: .infinity)
                }
                .controlSize(.regular)
                if active(cmd) { button.buttonStyle(.borderedProminent) } else { button.buttonStyle(.bordered) }
            }
        }
    }

    private func options(_ st: ScottaKit.Settings) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                Text("Sailing")
                Stepper("\(st.sailing == 0 ? "Off" : "\(st.sailing)%")", value: binding(st.sailing) { .sailing($0) }, in: 0...30)
            }
            GridRow {
                Toggle("Heat protection", isOn: binding(st.heatProtect) { .heat($0, st.maxTempC) }).toggleStyle(.checkbox)
                Stepper("\(Int(st.maxTempC)) °C", value: binding(st.maxTempC) { .heat(st.heatProtect, $0) }, in: 25...50)
                    .disabled(!st.heatProtect)
            }
            GridRow {
                Toggle("Prevent sleep until limit", isOn: binding(st.preventSleep) { .preventSleep($0) })
                    .toggleStyle(.checkbox).gridCellColumns(2)
            }
            GridRow {
                Text("MagSafe LED")
                Picker("", selection: binding(st.led) { .led($0) }) {
                    Text("System").tag(LED.system); Text("Off").tag(LED.off); Text("Show state").tag(LED.indicate)
                }.labelsHidden()
            }
            GridRow {
                Text("Power on battery")
                powerPicker(binding(st.powerBattery) { .powerMode(battery: $0, adapter: st.powerAdapter) })
            }
            GridRow {
                Text("Power on adapter")
                powerPicker(binding(st.powerAdapter) { .powerMode(battery: st.powerBattery, adapter: $0) })
            }
        }
    }

    private func powerPicker(_ b: Binding<PowerMode>) -> some View {
        Picker("", selection: b) {
            Text("Auto").tag(PowerMode.auto); Text("Low").tag(PowerMode.low); Text("High").tag(PowerMode.high)
        }.labelsHidden().pickerStyle(.segmented)
    }

    /// Settings are owned by the daemon: reads come from status, writes become commands.
    private func binding<T>(_ value: T, _ cmd: @escaping (T) -> Command) -> Binding<T> {
        Binding(get: { value }, set: { model.send(cmd($0)) })
    }

    private func stats(_ b: Battery) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                row("Health", b.health > 0 ? "\(Int((b.health * 100).rounded()))% (\(b.maxMAh)/\(b.designMAh) mAh)" : "–")
                row("Cycles", "\(b.cycles)")
                row("Temperature", String(format: "%.1f °C", b.tempC))
                row("Voltage", String(format: "%.2f V", Double(b.voltageMV) / 1000))
                row("Current", "\(b.amperageMA) mA")
                row("System power", String(format: "%.1f W", b.systemW))
                row(b.charging ? "Time to full" : "Time left", b.minutesLeft.map { "\($0 / 60)h \($0 % 60)m" } ?? "–")
            }
            .font(.callout)
            if model.power.count > 1 {
                Chart(model.power, id: \.0) {
                    LineMark(x: .value("Time", $0.0), y: .value("W", $0.1)).interpolationMethod(.monotone)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 44)
            }
        }
        .padding(.top, 6)
    }

    private func row(_ k: String, _ v: String) -> some View {
        GridRow { Text(k).foregroundStyle(.secondary); Text(v).monospacedDigit() }
    }
}

/// Slider position while dragging; committed to the daemon on release.
final class Draft: ObservableObject { @Published var limit = 80.0 }
