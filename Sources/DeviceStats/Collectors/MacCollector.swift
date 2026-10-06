import Foundation
import Darwin

enum MacCollector {
    static func collect(profile: [String: Any]) -> Device {
        let hw = profile.array("SPHardwareDataType").first ?? [:]
        let power = profile.array("SPPowerDataType")
        let batteryInfo = power.first { $0.string("_name") == "spbattery_information" }
        let smartBattery = readSmartBattery()

        var sections: [StatSection] = []

        // Hardware
        var hardware: [StatItem] = []
        hardware.add("Modell", hw.string("machine_name"))
        hardware.add("Modell-ID", hw.string("machine_model"))
        hardware.add("Chip", hw.string("chip_type") ?? hw.string("cpu_type"))
        hardware.add("Kerne", cores(hw.string("number_processors")))
        hardware.add("Arbeitsspeicher", hw.string("physical_memory"))
        hardware.add("Modellnummer", hw.string("model_number"))
        hardware.add("Firmware", hw.string("boot_rom_version"))
        hardware.add("Seriennummer", hw.string("serial_number"), sensitive: true)
        sections.append(StatSection(title: "Hardware", items: hardware))

        // System
        let info = ProcessInfo.processInfo
        var system: [StatItem] = []
        system.add("macOS", info.operatingSystemVersionString)
        system.add("Hostname", Host.current().localizedName, sensitive: true)
        system.add("Laufzeit seit Start", Format.duration(info.systemUptime))
        system.add("Thermischer Zustand", thermal(info.thermalState))
        system.add("Low-Power-Modus", Format.yesNo(info.isLowPowerModeEnabled))
        var load = [Double](repeating: 0, count: 3)
        if getloadavg(&load, 3) == 3 {
            system.add("Auslastung (1/5/15 min)", load.map { String(format: "%.2f", $0) }.joined(separator: " / "))
        }
        sections.append(StatSection(title: "System", items: system))

        // Arbeitsspeicher
        if let mem = memoryUsage() {
            let total = Int64(info.physicalMemory)
            var memory: [StatItem] = []
            memory.add("Belegt", "\(Format.memory(mem.used)) von \(Format.memory(total)) (\(Int(Double(mem.used) / Double(total) * 100)) %)")
            memory.add("Aktiv", Format.memory(mem.active))
            memory.add("Reserviert (wired)", Format.memory(mem.wired))
            memory.add("Komprimiert", Format.memory(mem.compressed))
            memory.add("Frei", Format.memory(mem.free))
            sections.append(StatSection(title: "Arbeitsspeicher", items: memory))
        }

        // Speicher
        var storage: [StatItem] = []
        for volume in profile.array("SPStorageDataType") {
            guard let name = volume.string("_name"),
                  let size = volume.int("size_in_bytes"), size > 1_000_000_000,
                  let free = volume.int("free_space_in_bytes") else { continue }
            let used = size - free
            storage.add(name, "\(Format.bytes(Int64(used))) belegt von \(Format.bytes(Int64(size))) – \(Format.bytes(Int64(free))) frei")
        }
        if !storage.isEmpty { sections.append(StatSection(title: "Speicher", items: storage)) }

        // Akku
        var batteries: [BatteryReading] = []
        if let batteryInfo {
            let charge = batteryInfo.dict("sppower_battery_charge_info") ?? [:]
            let health = batteryInfo.dict("sppower_battery_health_info") ?? [:]
            let percent = charge.int("sppower_battery_state_of_charge") ?? smartBattery.int("CurrentCapacity")
            let charging = charge.bool("sppower_battery_is_charging")
            if let percent { batteries.append(BatteryReading(label: "Akku", percent: percent, isCharging: charging)) }

            var battery: [StatItem] = []
            battery.add("Ladestand", percent.map { "\($0) %" })
            battery.add("Lädt", Format.yesNo(charging))
            battery.add("Vollständig geladen", Format.yesNo(charge.bool("sppower_battery_fully_charged")))
            battery.add("Ladezyklen", health.int("sppower_battery_cycle_count").map { cycles in
                let design = smartBattery.int("DesignCycleCount9C")
                return design.map { "\(cycles) von \($0)" } ?? "\(cycles)"
            })
            battery.add("Zustand", health.string("sppower_battery_health"))
            battery.add("Maximale Kapazität", health.string("sppower_battery_health_maximum_capacity"))
            if let mv = smartBattery.int("Voltage") { battery.add("Spannung", String(format: "%.2f V", Double(mv) / 1000)) }
            if let ma = smartBattery.int("InstantAmperage") {
                // ioreg liefert negative Werte als großen vorzeichenlosen Integer.
                let signed = ma > Int(Int32.max) ? ma - Int(UInt64.max) - 1 : ma
                battery.add("Stromstärke", "\(signed) mA")
            }
            if let t = smartBattery.int("Temperature") ?? smartBattery.int("VirtualTemperature"), t > 0 {
                battery.add("Temperatur", String(format: "%.1f °C", Double(t) / 100))
            }
            if let design = smartBattery.int("DesignCapacity"), let raw = smartBattery.int("AppleRawMaxCapacity") ?? smartBattery.int("NominalChargeCapacity") {
                battery.add("Kapazität (mAh)", "\(raw) von \(design) mAh")
            }
            if let minutes = smartBattery.int("TimeRemaining"), minutes > 0, minutes < 65535 {
                battery.add(charging == true ? "Voll in" : "Restlaufzeit", Format.duration(TimeInterval(minutes * 60)))
            }
            battery.add("Seriennummer", (batteryInfo.dict("sppower_battery_model_info") ?? [:]).string("sppower_battery_serial_number"), sensitive: true)
            sections.append(StatSection(title: "Akku", items: battery))
        }

        if let adapter = smartBattery.dict("AdapterDetails"), smartBattery.bool("ExternalConnected") == true {
            var items: [StatItem] = []
            items.add("Netzteil", adapter.string("Name"))
            items.add("Leistung", adapter.int("Watts").map { "\($0) W" })
            items.add("Hersteller", adapter.string("Manufacturer"))
            items.add("Seriennummer", adapter.string("SerialString"), sensitive: true)
            if !items.isEmpty { sections.append(StatSection(title: "Stromversorgung", items: items)) }
        }

        let name = Host.current().localizedName ?? hw.string("machine_name") ?? "Mac"
        let subtitle = [hw.string("machine_name"), hw.string("chip_type")].compactMap { $0 }.joined(separator: " · ")
        return Device(
            id: "this-mac",
            name: name,
            category: .thisMac,
            symbol: symbol(for: hw.string("machine_name") ?? ""),
            subtitle: subtitle,
            isApple: true,
            isConnected: true,
            batteries: batteries,
            sections: sections
        )
    }

    // MARK: - Helfer

    private static func readSmartBattery() -> [String: Any] {
        guard let list = try? Shell.plist("/usr/sbin/ioreg", ["-rn", "AppleSmartBattery", "-a"]) as? [[String: Any]],
              var top = list.first else { return [:] }
        // Einige Werte liegen nur im verschachtelten BatteryData-Dictionary.
        if let nested = top.dict("BatteryData") {
            for (key, value) in nested where top[key] == nil { top[key] = value }
        }
        return top
    }

    private static func cores(_ raw: String?) -> String? {
        // Format: "proc 8:4:4" bzw. "proc 8:0:4:4" → gesamt:…:Performance:Effizienz
        guard let raw, raw.hasPrefix("proc ") else { return raw }
        let parts = raw.dropFirst(5).split(separator: ":").compactMap { Int($0) }
        guard let total = parts.first else { return raw }
        if parts.count >= 3 {
            return "\(total) (\(parts[parts.count - 2]) Performance, \(parts[parts.count - 1]) Effizienz)"
        }
        return "\(total)"
    }

    private static func thermal(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "Normal"
        case .fair: "Leicht erhöht"
        case .serious: "Hoch"
        case .critical: "Kritisch"
        @unknown default: "Unbekannt"
        }
    }

    static func symbol(for model: String) -> String {
        let m = model.lowercased()
        if m.contains("macbook") { return "laptopcomputer" }
        if m.contains("imac") { return "desktopcomputer" }
        if m.contains("mac mini") { return "macmini" }
        if m.contains("studio") { return "macstudio" }
        if m.contains("pro") { return "macpro.gen3" }
        return "desktopcomputer"
    }

    private struct Memory { var used, active, wired, compressed, free: Int64 }

    private static func memoryUsage() -> Memory? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = Int64(vm_kernel_page_size)
        let active = Int64(stats.active_count) * page
        let wired = Int64(stats.wire_count) * page
        let compressed = Int64(stats.compressor_page_count) * page
        let free = Int64(stats.free_count) * page
        // Entspricht ungefähr "Belegter Speicher" in der Aktivitätsanzeige.
        let appMemory = Int64(stats.internal_page_count - stats.purgeable_count) * page
        return Memory(used: appMemory + wired + compressed, active: active, wired: wired, compressed: compressed, free: free)
    }
}
