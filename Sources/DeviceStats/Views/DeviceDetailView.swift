import SwiftUI
import Charts

struct DeviceDetailView: View {
    let device: Device
    let history: [BatterySample]
    let hideSensitive: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if !device.batteries.isEmpty {
                    HStack(spacing: 16) {
                        ForEach(device.batteries) { BatteryGauge(battery: $0) }
                    }
                }

                if history.count >= 2 {
                    BatteryHistoryChart(samples: history)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                    ForEach(device.sections) { section in
                        SectionCard(section: section, hideSensitive: hideSensitive)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(device.name)
        .navigationSubtitle(device.category.title)
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: device.symbol)
                .font(.system(size: 44))
                .foregroundStyle(device.isConnected ? Color.accentColor : .secondary)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name).font(.title.bold())
                Text(device.subtitle).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Circle().fill(device.isConnected ? .green : .gray).frame(width: 8, height: 8)
                    Text(device.isConnected ? "Verbunden" : "Nicht verbunden")
                    if device.isApple {
                        Text("·")
                        Image(systemName: "apple.logo")
                        Text("Apple")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

struct BatteryGauge: View {
    let battery: BatteryReading

    var body: some View {
        VStack(spacing: 6) {
            Gauge(value: Double(battery.percent), in: 0...100) {
                EmptyView()
            } currentValueLabel: {
                Text("\(battery.percent)").monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(BatteryStyle.color(battery.percent))
            .scaleEffect(1.3)
            .frame(width: 70, height: 70)
            HStack(spacing: 3) {
                if battery.isCharging == true { Image(systemName: "bolt.fill").foregroundStyle(.yellow) }
                Text(battery.label)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct BatteryHistoryChart: View {
    let samples: [BatterySample]
    @State private var range: TimeInterval = 86_400

    private var visible: [BatterySample] {
        let start = Date.now.addingTimeInterval(-range)
        return samples.filter { $0.date >= start }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Akkuverlauf").font(.headline)
                Spacer()
                Picker("Zeitraum", selection: $range) {
                    Text("6 Std.").tag(21_600.0)
                    Text("24 Std.").tag(86_400.0)
                    Text("7 Tage").tag(604_800.0)
                    Text("30 Tage").tag(2_592_000.0)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 280)
            }
            if visible.count >= 2 {
                Chart(visible, id: \.self) { sample in
                    LineMark(x: .value("Zeit", sample.date), y: .value("Akku", sample.percent))
                        .foregroundStyle(by: .value("Teil", sample.label))
                        .interpolationMethod(.monotone)
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine()
                        AxisValueLabel { Text("\(value.as(Int.self) ?? 0) %") }
                    }
                }
                .frame(height: 180)
            } else {
                Text("Noch zu wenige Messwerte in diesem Zeitraum. Der Verlauf wird bei jeder Aktualisierung ergänzt.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(height: 60)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct SectionCard: View {
    let section: StatSection
    let hideSensitive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.title).font(.headline)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 6) {
                ForEach(section.items) { item in
                    GridRow {
                        Text(item.label)
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.leading)
                        Text(hideSensitive && item.isSensitive ? Privacy.mask(item.value) : item.value)
                            .textSelection(.enabled)
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.callout)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}
