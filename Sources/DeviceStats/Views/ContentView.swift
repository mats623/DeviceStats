import SwiftUI

struct ContentView: View {
    @Environment(DeviceStore.self) private var store
    @AppStorage("hideSensitive") private var hideSensitive = true
    @AppStorage("appleOnly") private var appleOnly = false
    @AppStorage("connectedOnly") private var connectedOnly = false
    @AppStorage("autoRefresh") private var autoRefresh: Double = 60
    @State private var selection: String? = Self.overviewID

    private static let overviewID = "overview"

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Übersicht", systemImage: "square.grid.2x2")
                    .tag(Self.overviewID as String?)
                ForEach(DeviceCategory.allCases) { category in
                    let devices = store.devices(in: category, appleOnly: appleOnly, connectedOnly: connectedOnly)
                    if !devices.isEmpty {
                        Section(category.title) {
                            ForEach(devices) { device in
                                DeviceRow(device: device).tag(device.id as String?)
                            }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 280)
            .safeAreaInset(edge: .bottom) { statusBar }
        } detail: {
            if let id = selection, let device = store.devices.first(where: { $0.id == id }) {
                DeviceDetailView(device: device, history: store.history[device.id] ?? [], hideSensitive: hideSensitive)
            } else {
                OverviewView(appleOnly: appleOnly, connectedOnly: connectedOnly) { selection = $0 }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Toggle(isOn: $appleOnly) { Label("Nur Apple-Geräte", systemImage: "apple.logo") }
                    .help("Nur Apple-Geräte anzeigen")
                Toggle(isOn: $connectedOnly) { Label("Nur verbundene", systemImage: "link") }
                    .help("Nur verbundene Geräte anzeigen")
                Toggle(isOn: $hideSensitive) { Label("Datenschutz", systemImage: hideSensitive ? "eye.slash" : "eye") }
                    .help("Seriennummern, Adressen und UDIDs ausblenden")
                Menu {
                    Picker("Automatisch aktualisieren", selection: $autoRefresh) {
                        Text("Aus").tag(0.0)
                        Text("Alle 30 Sekunden").tag(30.0)
                        Text("Jede Minute").tag(60.0)
                        Text("Alle 5 Minuten").tag(300.0)
                    }
                    Divider()
                    Button("Als JSON exportieren …") { Exporter.export(store: store, maskSensitive: hideSensitive, appleOnly: appleOnly) }
                    Button("Akkuverlauf löschen", role: .destructive) { store.clearHistory() }
                } label: {
                    Label("Mehr", systemImage: "ellipsis.circle")
                }
                Button {
                    Task { await store.refresh() }
                } label: {
                    if store.isRefreshing { ProgressView().controlSize(.small) } else { Label("Aktualisieren", systemImage: "arrow.clockwise") }
                }
                .help("Aktualisieren (⌘R)")
                .disabled(store.isRefreshing)
            }
        }
        .task {
            if store.lastRefresh == nil { await store.refresh() }
            store.setAutoRefresh(interval: autoRefresh)
        }
        .onChange(of: autoRefresh) { _, value in store.setAutoRefresh(interval: value) }
    }

    private var statusBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(store.errors, id: \.self) { error in
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            }
            if let date = store.lastRefresh {
                Text("Aktualisiert \(date.formatted(date: .omitted, time: .standard))")
                    .foregroundStyle(.secondary)
            } else {
                Text("Lese Geräte aus …").foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
    }
}

struct DeviceRow: View {
    let device: Device

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: device.symbol)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(device.isConnected ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name).lineLimit(1)
                Text(device.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let battery = device.lowestBattery {
                BatteryBadge(battery: battery)
            }
        }
        .padding(.vertical, 2)
        .opacity(device.isConnected ? 1 : 0.6)
    }
}

struct BatteryBadge: View {
    let battery: BatteryReading

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: battery.isCharging == true ? "battery.100percent.bolt" : BatteryStyle.symbol(battery.percent))
            Text("\(battery.percent) %").monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(BatteryStyle.color(battery.percent))
    }
}

enum BatteryStyle {
    static func color(_ percent: Int) -> Color {
        percent <= 10 ? .red : percent <= 20 ? .orange : .green
    }

    static func symbol(_ percent: Int) -> String {
        switch percent {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }
}
