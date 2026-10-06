import Foundation

/// AirPods, Apple Watch, Magic Keyboard/Mouse/Trackpad usw. über system_profiler und ioreg.
enum BluetoothCollector {
    static func collect(profile: [String: Any]) -> [Device] {
        guard let root = profile.array("SPBluetoothDataType").first else { return [] }
        let hidBatteries = readHIDBatteries()

        var devices: [Device] = []
        for (key, connected) in [("device_connected", true), ("device_not_connected", false)] {
            for entry in root.array(key) {
                for (name, value) in entry {
                    guard let props = value as? [String: Any] else { continue }
                    devices.append(device(name: name, props: props, connected: connected, hid: hidBatteries[name]))
                }
            }
        }
        return devices
    }

    private static func device(name rawName: String, props: [String: Any], connected: Bool, hid: Int?) -> Device {
        // Gerätenamen enthalten oft geschützte Leerzeichen ("Apple\u{00A0}Watch").
        let name = rawName.replacingOccurrences(of: "\u{00A0}", with: " ")
        let vendor = props.string("device_vendorID")?.lowercased()
        let minorType = props.string("device_minorType") ?? ""
        let isApple = vendor == "0x004c" || looksApple(name)
        let productID = props.string("device_productID")?.lowercased()
        let model = productID.flatMap { airPodsModels[$0] }

        // Akkuwerte: device_batteryLevelLeft/Right/Case/Main → "85%"
        var batteries: [BatteryReading] = []
        for (key, label) in [("device_batteryLevelMain", "Akku"), ("device_batteryLevelLeft", "Links"),
                             ("device_batteryLevelRight", "Rechts"), ("device_batteryLevelCase", "Case")] {
            if let percent = props.int(key) { batteries.append(BatteryReading(label: label, percent: percent)) }
        }
        if batteries.isEmpty, let hid { batteries.append(BatteryReading(label: "Akku", percent: hid)) }

        var general: [StatItem] = []
        general.add("Modell", model)
        general.add("Gerätetyp", minorType.isEmpty ? nil : minorType)
        general.add("Status", connected ? "Verbunden" : "Nicht verbunden")
        general.add("Signalstärke (RSSI)", props.string("device_rssi").map { "\($0) dBm" })
        general.add("Firmware", props.string("device_firmwareVersion"))
        general.add("Case-Firmware", props.string("device_caseVersion"))
        general.add("Hersteller-ID", props.string("device_vendorID"))
        general.add("Produkt-ID", props.string("device_productID"))
        general.add("Dienste", props.string("device_services").map(services))
        general.add("Adresse", props.string("device_address"), sensitive: true)
        general.add("Seriennummer", props.string("device_serialNumber"), sensitive: true)
        general.add("Seriennummer links", props.string("device_serialNumberLeft"), sensitive: true)
        general.add("Seriennummer rechts", props.string("device_serialNumberRight"), sensitive: true)

        var sections = [StatSection(title: "Bluetooth", items: general)]
        if !batteries.isEmpty {
            sections.insert(StatSection(title: "Akku", items: batteries.map { StatItem(label: $0.label, value: "\($0.percent) %") }), at: 0)
        }

        // Alle übrigen Schlüssel, damit nichts verloren geht.
        let known: Set<String> = ["device_vendorID", "device_minorType", "device_productID", "device_rssi", "device_firmwareVersion",
                                  "device_caseVersion", "device_services", "device_address", "device_serialNumber",
                                  "device_serialNumberLeft", "device_serialNumberRight"]
        var other: [StatItem] = []
        for key in props.keys.sorted() where !known.contains(key) && !key.contains("batteryLevel") {
            other.add(Format.prettyKey(key), props.string(key).map(Format.prettyValue))
        }
        if !other.isEmpty { sections.append(StatSection(title: "Weitere Daten", items: other)) }

        return Device(
            id: "bt-\(props.string("device_address") ?? name)",
            name: name,
            category: .bluetooth,
            symbol: symbol(name: name, minorType: minorType, productID: productID),
            subtitle: [model ?? (minorType.isEmpty ? nil : minorType), connected ? "Verbunden" : "Nicht verbunden"].compactMap { $0 }.joined(separator: " · "),
            isApple: isApple,
            isConnected: connected,
            batteries: batteries,
            sections: sections
        )
    }

    /// Magic Keyboard/Mouse/Trackpad melden ihren Akku über IOKit (HID).
    private static func readHIDBatteries() -> [String: Int] {
        guard let list = try? Shell.plist("/usr/sbin/ioreg", ["-r", "-k", "BatteryPercent", "-a"]) as? [[String: Any]] else { return [:] }
        var result: [String: Int] = [:]
        for entry in list {
            if let name = entry.string("Product"), let percent = entry.int("BatteryPercent") { result[name] = percent }
        }
        return result
    }

    private static func services(_ raw: String) -> String {
        // "0x400000 < BLE >" → "BLE"
        guard let start = raw.firstIndex(of: "<"), let end = raw.lastIndex(of: ">") else { return raw }
        return raw[raw.index(after: start)..<end].trimmingCharacters(in: .whitespaces).split(separator: " ").joined(separator: ", ")
    }

    private static func looksApple(_ name: String) -> Bool {
        ["airpods", "iphone", "ipad", "apple watch", "magic", "macbook", "imac", "mac mini", "mac studio", "beats", "homepod", "apple tv", "appletv", "vision pro"]
            .contains { name.lowercased().contains($0) }
    }

    private static let airPodsModels: [String: String] = [
        "0x2002": "AirPods (1. Gen.)", "0x200f": "AirPods (2. Gen.)", "0x2013": "AirPods (3. Gen.)",
        "0x2019": "AirPods 4", "0x201b": "AirPods 4 (ANC)",
        "0x200e": "AirPods Pro", "0x2014": "AirPods Pro (2. Gen.)", "0x2024": "AirPods Pro (2. Gen., USB-C)",
        "0x2027": "AirPods Pro 3", "0x200a": "AirPods Max", "0x201f": "AirPods Max (USB-C)",
        "0x2006": "Beats Solo³", "0x2009": "Beats Studio³", "0x200b": "Powerbeats Pro", "0x2011": "Beats Studio Buds",
    ]

    private static func symbol(name: String, minorType: String, productID: String?) -> String {
        let n = name.lowercased(), t = minorType.lowercased()
        if n.contains("airpods max") || productID == "0x200a" || productID == "0x201f" { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("watch") { return "applewatch" }
        if n.contains("iphone") { return "iphone" }
        if n.contains("ipad") { return "ipad" }
        if n.contains("macbook") { return "laptopcomputer" }
        if n.contains("homepod") { return "homepod" }
        if n.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
        if t.contains("keyboard") || n.contains("keyboard") { return "keyboard" }
        if t.contains("mouse") || n.contains("mouse") { return "computermouse" }
        if t.contains("headphones") || t.contains("headset") { return "headphones" }
        if t.contains("speaker") { return "hifispeaker" }
        if t.contains("gamepad") || t.contains("joystick") { return "gamecontroller" }
        return "wave.3.right"
    }
}
