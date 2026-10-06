import SwiftUI

struct OverviewView: View {
    @Environment(DeviceStore.self) private var store
    let appleOnly: Bool
    let connectedOnly: Bool
    let select: (String) -> Void

    private var visible: [Device] { store.devices(appleOnly: appleOnly, connectedOnly: connectedOnly) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Übersicht").font(.largeTitle.bold())

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    StatTile(title: "Geräte gesamt", value: "\(visible.count)", symbol: "square.stack.3d.up")
                    StatTile(title: "Verbunden", value: "\(visible.filter(\.isConnected).count)", symbol: "link")
                    StatTile(title: "Apple-Geräte", value: "\(visible.filter(\.isApple).count)", symbol: "apple.logo")
                    StatTile(title: "Mit Akku", value: "\(visible.filter { !$0.batteries.isEmpty }.count)", symbol: "battery.75percent")
                }

                let withBattery = visible.filter { !$0.batteries.isEmpty && $0.isConnected }
                if !withBattery.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Akkus").font(.title2.bold())
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                            ForEach(withBattery) { device in
                                Button { select(device.id) } label: { BatteryCard(device: device) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }

                ForEach(DeviceCategory.allCases) { category in
                    let devices = store.devices(in: category, appleOnly: appleOnly, connectedOnly: connectedOnly)
                    if !devices.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(category.title) (\(devices.count))").font(.title3.bold())
                            ForEach(devices) { device in
                                Button { select(device.id) } label: {
                                    DeviceRow(device: device)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if store.devices.isEmpty && store.isRefreshing {
                    ProgressView("Lese Geräte aus …").frame(maxWidth: .infinity)
                }
            }
            .padding(24)
        }
        .navigationTitle("Übersicht")
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(Color.accentColor)
            Text(value).font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct BatteryCard: View {
    let device: Device

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: device.symbol).font(.title2).foregroundStyle(Color.accentColor)
                Text(device.name).font(.headline).lineLimit(1)
                Spacer()
            }
            ForEach(device.batteries) { battery in
                HStack(spacing: 8) {
                    Text(battery.label).font(.caption).foregroundStyle(.secondary).frame(width: 50, alignment: .leading)
                    ProgressView(value: Double(battery.percent), total: 100)
                        .tint(BatteryStyle.color(battery.percent))
                    BatteryBadge(battery: battery).frame(width: 64, alignment: .trailing)
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
    }
}

struct MenuBarContent: View {
    @Environment(DeviceStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Akkus").font(.headline)
            let devices = store.devices.filter { $0.isConnected && !$0.batteries.isEmpty }
            if devices.isEmpty {
                Text(store.lastRefresh == nil ? "Noch nicht geladen" : "Keine Geräte mit Akku verbunden")
                    .foregroundStyle(.secondary)
            }
            ForEach(devices) { device in
                HStack {
                    Image(systemName: device.symbol).frame(width: 20)
                    Text(device.name).lineLimit(1)
                    Spacer()
                    ForEach(device.batteries) { BatteryBadge(battery: $0) }
                }
            }
            Divider()
            HStack {
                Button("Aktualisieren") { Task { await store.refresh() } }
                Spacer()
                Button("Fenster öffnen") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Button("Beenden") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 320)
        .task { if store.lastRefresh == nil { await store.refresh() } }
    }
}
