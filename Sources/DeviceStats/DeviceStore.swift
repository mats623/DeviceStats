import Foundation
import Observation

@MainActor
@Observable
final class DeviceStore {
    private(set) var devices: [Device] = []
    private(set) var history: [String: [BatterySample]] = [:]
    private(set) var errors: [String] = []
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?

    private var autoRefreshTask: Task<Void, Never>?
    private static let maxSamplesPerDevice = 5_000

    init() {
        history = Self.loadHistory()
    }

    func devices(in category: DeviceCategory? = nil, appleOnly: Bool, connectedOnly: Bool) -> [Device] {
        devices.filter {
            (category == nil || $0.category == category) && (!appleOnly || $0.isApple) && (!connectedOnly || $0.isConnected)
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // system_profiler und devicectl laufen parallel im Hintergrund.
        async let localResult = Self.background {
            let profile = try Shell.systemProfiler(["SPHardwareDataType", "SPPowerDataType", "SPStorageDataType",
                                                    "SPDisplaysDataType", "SPBluetoothDataType", "SPUSBHostDataType", "SPUSBDataType"])
            return [MacCollector.collect(profile: profile)]
                + PeripheralCollector.displays(profile: profile)
                + BluetoothCollector.collect(profile: profile)
                + PeripheralCollector.usb(profile: profile)
        }
        async let mobileResult = Self.background { try MobileDeviceCollector.collect() }

        var collected: [Device] = []
        var problems: [String] = []

        switch await localResult {
        case .success(let list): collected += list
        case .failure(let error):
            problems.append("Systeminformationen: \(error.localizedDescription)")
        }

        switch await mobileResult {
        case .success(let list): collected += list
        case .failure(let error):
            problems.append("iPhone/iPad (devicectl, benötigt Xcode): \(error.localizedDescription)")
        }

        devices = collected.sorted { lhs, rhs in
            if lhs.category != rhs.category {
                return DeviceCategory.allCases.firstIndex(of: lhs.category)! < DeviceCategory.allCases.firstIndex(of: rhs.category)!
            }
            if lhs.isConnected != rhs.isConnected { return lhs.isConnected }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        errors = problems
        lastRefresh = .now
        recordHistory()
    }

    func setAutoRefresh(interval: TimeInterval?) {
        autoRefreshTask?.cancel()
        guard let interval, interval > 0 else { return }
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    // MARK: - Verlauf

    private func recordHistory() {
        let now = Date.now
        for device in devices where device.isConnected {
            for battery in device.batteries {
                var samples = history[device.id, default: []]
                // Unveränderte Werte innerhalb von 5 Minuten nicht doppelt speichern.
                if let last = samples.last(where: { $0.label == battery.label }),
                   last.percent == battery.percent, now.timeIntervalSince(last.date) < 300 { continue }
                samples.append(BatterySample(date: now, label: battery.label, percent: battery.percent))
                history[device.id] = Array(samples.suffix(Self.maxSamplesPerDevice))
            }
        }
        Self.saveHistory(history)
    }

    func clearHistory() {
        history = [:]
        Self.saveHistory(history)
    }

    private static var historyURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DeviceStats", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("battery-history.json")
    }

    private static func loadHistory() -> [String: [BatterySample]] {
        guard let data = try? Data(contentsOf: historyURL) else { return [:] }
        return (try? JSONDecoder.iso.decode([String: [BatterySample]].self, from: data)) ?? [:]
    }

    private static func saveHistory(_ history: [String: [BatterySample]]) {
        guard let data = try? JSONEncoder.iso.encode(history) else { return }
        try? data.write(to: historyURL, options: .atomic)
    }

    // MARK: - Export

    struct Snapshot: Codable {
        var generatedAt: Date
        var host: String
        var devices: [Device]
    }

    func exportData(maskSensitive: Bool, appleOnly: Bool) throws -> Data {
        var list = devices.filter { !appleOnly || $0.isApple }
        if maskSensitive {
            list = list.map { device in
                var d = device
                d.sections = d.sections.map { section in
                    var s = section
                    s.items = s.items.map { item in
                        var i = item
                        if i.isSensitive { i.value = Privacy.mask(i.value) }
                        return i
                    }
                    return s
                }
                return d
            }
        }
        let snapshot = Snapshot(generatedAt: .now, host: maskSensitive ? "Mac" : (Host.current().localizedName ?? "Mac"), devices: list)
        return try JSONEncoder.iso.encode(snapshot)
    }

    // MARK: - Hilfen

    private nonisolated static func background<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async -> Result<T, Error> {
        await Task.detached(priority: .userInitiated) { Result { try work() } }.value
    }
}

extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}

extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
