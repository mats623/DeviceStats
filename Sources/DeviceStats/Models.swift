import Foundation

enum DeviceCategory: String, CaseIterable, Codable, Identifiable {
    case thisMac, mobile, bluetooth, usb, display

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thisMac: "Dieser Mac"
        case .mobile: "iPhone, iPad & Watch"
        case .bluetooth: "Bluetooth"
        case .usb: "USB"
        case .display: "Displays"
        }
    }
}

struct BatteryReading: Codable, Hashable, Identifiable {
    var label: String
    var percent: Int
    var isCharging: Bool?

    var id: String { label }
}

struct StatItem: Codable, Hashable, Identifiable {
    var label: String
    var value: String
    /// Seriennummern, Adressen, UDIDs usw. – werden im Datenschutzmodus maskiert.
    var isSensitive: Bool = false

    var id: String { label }
}

struct StatSection: Codable, Hashable, Identifiable {
    var title: String
    var items: [StatItem]

    var id: String { title }
}

struct Device: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var category: DeviceCategory
    var symbol: String
    var subtitle: String
    var isApple: Bool
    var isConnected: Bool
    var batteries: [BatteryReading] = []
    var sections: [StatSection] = []

    /// Kleinste Akkuanzeige – für Listen und Menüleiste.
    var lowestBattery: BatteryReading? {
        batteries.min { $0.percent < $1.percent }
    }
}

struct BatterySample: Codable, Hashable {
    var date: Date
    var label: String
    var percent: Int
}

enum Privacy {
    static func mask(_ value: String) -> String {
        guard value.count > 4 else { return String(repeating: "•", count: value.count) }
        return String(repeating: "•", count: min(value.count - 4, 12)) + value.suffix(4)
    }
}

extension Array where Element == StatItem {
    /// Fügt nur nicht-leere Werte hinzu.
    mutating func add(_ label: String, _ value: String?, sensitive: Bool = false) {
        guard let value, !value.isEmpty else { return }
        append(StatItem(label: label, value: value, isSensitive: sensitive))
    }
}
