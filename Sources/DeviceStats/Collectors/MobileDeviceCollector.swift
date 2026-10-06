import Foundation

/// iPhone, iPad, Apple Watch, Apple TV & Vision Pro über `xcrun devicectl` (Teil von Xcode).
/// Ist libimobiledevice installiert (`brew install libimobiledevice`), werden für per USB
/// verbundene Geräte zusätzlich Akku und Speicher gelesen.
enum MobileDeviceCollector {
    static func collect() throws -> [Device] {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("devicestats-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: output) }
        _ = try Shell.run("/usr/bin/xcrun", ["devicectl", "list", "devices", "--quiet", "--json-output", output.path], timeout: 45)

        let data = try Data(contentsOf: output)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root.dict("result") else { return [] }

        let ideviceinfo = Shell.find("ideviceinfo")
        return result.array("devices").compactMap { device(from: $0, ideviceinfo: ideviceinfo) }
    }

    private static func device(from raw: [String: Any], ideviceinfo: String?) -> Device? {
        let props = raw.dict("properties") ?? [:]
        let hardware = props.dict("hardware") ?? raw.dict("hardwareProperties") ?? [:]
        let state = props.dict("state") ?? [:]
        let connection = props.dict("connection") ?? [:]
        let legacyDevice = raw.dict("deviceProperties") ?? [:]
        let legacyConnection = raw.dict("connectionProperties") ?? [:]
        let software = props.dict("software") ?? [:]

        guard hardware.string("reality") != "virtual" else { return nil }

        let name = state.string("name") ?? legacyDevice.string("name") ?? "Unbekanntes Gerät"
        let type = hardware.string("deviceType") ?? "Gerät"
        let platform = hardware.string("platform") ?? ""
        let osVersion = software.dict("osVersionNumber")?.string("stringValue") ?? legacyDevice.string("osVersionNumber")
        let connectionState = connection.string("state") ?? legacyConnection.string("tunnelState")
        let transport = connection.string("transportType") ?? legacyConnection.string("transportType")
        // devicectl baut den Tunnel nur bei Bedarf auf – ein Gerät mit Transportweg gilt als erreichbar ("available").
        let isConnected = connectionState == "connected" || transport != nil
        let udid = hardware.string("udid")

        var general: [StatItem] = []
        general.add("Modell", hardware.string("marketingName"))
        general.add("Produkttyp", hardware.string("productType"))
        general.add("Hardware-Modell", hardware.string("hardwareModel"))
        general.add("Betriebssystem", [platform, osVersion].compactMap { $0 }.joined(separator: " "))
        general.add("Build", legacyDevice.string("osBuildUpdate"))
        general.add("Status", state.string("bootState").map { $0 == "booted" ? "Eingeschaltet" : $0 })
        general.add("Entwicklermodus", legacyDevice.string("developerModeStatus").map { $0 == "enabled" ? "Aktiviert" : "Deaktiviert" })
        general.add("Seriennummer", hardware.string("serialNumber"), sensitive: true)
        general.add("UDID", udid, sensitive: true)
        general.add("ECID", hardware.string("ecid"), sensitive: true)

        var conn: [StatItem] = []
        conn.add("Verbindung", connectionState == "connected" ? "Verbunden (Tunnel aktiv)" : isConnected ? "Erreichbar" : "Nicht verbunden")
        conn.add("Übertragung", transport.map(transportName))
        conn.add("Kopplung", (connection.string("pairingState") ?? legacyConnection.string("pairingState")).map { $0 == "paired" ? "Gekoppelt" : $0 })
        conn.add("Zuletzt verbunden", legacyConnection.string("lastConnectionDate").flatMap(formatDate))

        var sections = [StatSection(title: "Allgemein", items: general), StatSection(title: "Verbindung", items: conn)]
        var batteries: [BatteryReading] = []

        if let ideviceinfo, let udid, isConnected, transport == "wired" {
            let extra = enrich(udid: udid, tool: ideviceinfo)
            batteries = extra.batteries
            sections.append(contentsOf: extra.sections)
        }

        return Device(
            id: "mobile-\(raw.string("identifier") ?? udid ?? name)",
            name: name,
            category: .mobile,
            symbol: symbol(for: type),
            subtitle: [hardware.string("marketingName"), osVersion.map { "\(platform) \($0)" }].compactMap { $0 }.joined(separator: " · "),
            isApple: true,
            isConnected: isConnected,
            batteries: batteries,
            sections: sections
        )
    }

    private static func enrich(udid: String, tool: String) -> (batteries: [BatteryReading], sections: [StatSection]) {
        func query(_ domain: String?) -> [String: Any] {
            var args = ["-u", udid, "-x"]
            if let domain { args += ["-q", domain] }
            return (try? Shell.plist(tool, args, timeout: 15)) as? [String: Any] ?? [:]
        }

        var batteries: [BatteryReading] = []
        var sections: [StatSection] = []

        let battery = query("com.apple.mobile.battery")
        if let percent = battery.int("BatteryCurrentCapacity") {
            let charging = battery.bool("BatteryIsCharging")
            batteries.append(BatteryReading(label: "Akku", percent: percent, isCharging: charging))
            var items: [StatItem] = []
            items.add("Ladestand", "\(percent) %")
            items.add("Lädt", Format.yesNo(charging))
            items.add("Externe Stromversorgung", Format.yesNo(battery.bool("ExternalConnected")))
            items.add("Vollständig geladen", Format.yesNo(battery.bool("FullyCharged")))
            sections.append(StatSection(title: "Akku", items: items))
        }

        if let diagnostics = Shell.find("idevicediagnostics") {
            let health = batteryHealth(udid: udid, tool: diagnostics)
            if !health.isEmpty { sections.append(StatSection(title: "Akkuzustand", items: health)) }
        }

        let disk = query("com.apple.disk_usage")
        if let total = disk.int("TotalDataCapacity"), let free = disk.int("TotalDataAvailable") {
            var items: [StatItem] = []
            items.add("Gesamtkapazität", disk.int("TotalDiskCapacity").map { Format.bytes(Int64($0)) })
            items.add("Datenpartition", "\(Format.bytes(Int64(total - free))) belegt von \(Format.bytes(Int64(total)))")
            items.add("Frei", Format.bytes(Int64(free)))
            sections.append(StatSection(title: "Speicher", items: items))
        }

        let base = query(nil)
        var device: [StatItem] = []
        device.add("Region", base.string("RegionInfo"))
        device.add("Baseband", base.string("BasebandVersion"))
        device.add("Aktivierung", base.string("ActivationState"))
        device.add("WLAN-Adresse", base.string("WiFiAddress"), sensitive: true)
        device.add("Bluetooth-Adresse", base.string("BluetoothAddress"), sensitive: true)
        device.add("Telefonnummer", base.string("PhoneNumber"), sensitive: true)
        if !device.isEmpty { sections.append(StatSection(title: "Gerät", items: device)) }

        return (batteries, sections)
    }

    /// Ladezyklen, Kapazität usw. aus dem IORegistry-Eintrag AppleSmartBattery des Geräts (diagnostics_relay).
    private static func batteryHealth(udid: String, tool: String) -> [StatItem] {
        guard let root = (try? Shell.plist(tool, ["-u", udid, "ioregentry", "AppleSmartBattery"], timeout: 15)) as? [String: Any],
              var reg = root.dict("IORegistry") else { return [] }
        if let nested = reg.dict("BatteryData") {
            for (key, value) in nested where reg[key] == nil { reg[key] = value }
        }

        var items: [StatItem] = []
        let design = reg.int("DesignCapacity")
        let nominal = reg.int("NominalChargeCapacity") ?? reg.int("AppleRawMaxCapacity")
        if let design, let nominal, design > 0 {
            // Entspricht "Maximale Kapazität" in den iOS-Einstellungen.
            items.add("Maximale Kapazität", "\(Int((Double(nominal) / Double(design) * 100).rounded())) %")
        }
        items.add("Ladezyklen", reg.int("CycleCount").map(String.init))
        if let design, let nominal { items.add("Kapazität", "\(nominal) von \(design) mAh") }
        items.add("Vollladekapazität", reg.int("FullChargeCapacity").map { "\($0) mAh" })
        items.add("Aktuelle Ladung", (reg.int("RemainingCapacity") ?? reg.int("AppleRawCurrentCapacity")).map { "\($0) mAh" })
        if let mv = reg.int("Voltage") { items.add("Spannung", String(format: "%.2f V", Double(mv) / 1000)) }
        if let ma = reg.int("InstantAmperage") {
            let signed = ma > Int(Int32.max) ? ma - Int(UInt64.max) - 1 : ma
            items.add("Stromstärke", "\(signed) mA")
        }
        if let t = reg.int("Temperature") ?? reg.int("VirtualTemperature"), t > 0 {
            items.add("Temperatur", String(format: "%.1f °C", Double(t) / 100))
        }
        if reg.bool("ExternalConnected") != true, let minutes = reg.int("AvgTimeToEmpty"), minutes > 0, minutes < 65535 {
            items.add("Restlaufzeit (geschätzt)", Format.duration(TimeInterval(minutes * 60)))
        }
        if reg.bool("ExternalConnected") == true, let adapter = reg.dict("AdapterDetails") {
            let name = adapter.string("Name") ?? adapter.string("Description")
            let watts = adapter.int("Watts").map { "\($0) W" }
            items.add("Netzteil", [name, watts].compactMap { $0 }.joined(separator: " · "))
        }
        return items
    }

    private static func transportName(_ raw: String) -> String {
        switch raw {
        case "wired": "USB-Kabel"
        case "localNetwork": "WLAN / lokales Netzwerk"
        default: raw
        }
    }

    private static func formatDate(_ iso: String) -> String? {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return iso }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func symbol(for type: String) -> String {
        switch type.lowercased() {
        case let t where t.contains("ipad"): "ipad"
        case let t where t.contains("watch"): "applewatch"
        case let t where t.contains("tv"): "appletv"
        case let t where t.contains("vision") || t.contains("reality"): "visionpro"
        default: "iphone"
        }
    }
}
