import Foundation

/// USB-Geräte und Displays aus system_profiler.
enum PeripheralCollector {
    static func usb(profile: [String: Any]) -> [Device] {
        let buses = profile.array("SPUSBHostDataType") + profile.array("SPUSBDataType")
        var devices: [Device] = []
        // Die oberste Ebene sind Busse/Controller, Geräte stecken (ggf. verschachtelt) in _items.
        for bus in buses { walk(bus.array("_items"), into: &devices) }
        return devices
    }

    private static func walk(_ items: [[String: Any]], into devices: inout [Device]) {
        for item in items {
            if let device = usbDevice(item) { devices.append(device) }
            walk(item.array("_items"), into: &devices)
        }
    }

    private static func usbDevice(_ raw: [String: Any]) -> Device? {
        guard let name = raw.string("_name") else { return nil }
        let vendorName = raw.string("USBDeviceKeyVendorName") ?? raw.string("manufacturer")
        let vendorID = (raw.string("USBDeviceKeyVendorID") ?? raw.string("vendor_id"))?.lowercased()
        let isApple = vendorID?.contains("0x05ac") == true || vendorName?.lowercased().contains("apple") == true
        let speed = raw.string("USBDeviceKeyLinkSpeed") ?? raw.string("device_speed")

        var items: [StatItem] = []
        items.add("Hersteller", vendorName)
        items.add("Geschwindigkeit", speed)
        items.add("Strom (zugewiesen)", raw.string("USBDeviceKeyPowerAllocation") ?? raw.string("bus_power_used").map { "\($0) mA" })
        items.add("Strom (Bedarf)", raw.string("USBDeviceKeyPowerSinkCapability"))
        items.add("Hersteller-ID", raw.string("USBDeviceKeyVendorID") ?? raw.string("vendor_id"))
        items.add("Produkt-ID", raw.string("USBDeviceKeyProductID") ?? raw.string("product_id"))
        items.add("Version", raw.string("USBDeviceKeyProductVersion") ?? raw.string("bcd_device"))
        items.add("Typ", raw.string("USBKeyHardwareType").map { $0 == "Built-in" ? "Integriert" : $0 == "Removable" ? "Wechselbar" : $0 })
        items.add("Location-ID", raw.string("USBKeyLocationID") ?? raw.string("location_id"))
        items.add("Seriennummer", raw.string("USBDeviceKeySerialNumber") ?? raw.string("serial_num"), sensitive: true)

        let lower = name.lowercased()
        let symbol = lower.contains("iphone") ? "iphone" : lower.contains("ipad") ? "ipad" : lower.contains("keyboard") ? "keyboard"
            : lower.contains("mouse") ? "computermouse" : lower.contains("hub") ? "point.3.connected.trianglepath.dotted" : "cable.connector"

        return Device(
            id: "usb-\(raw.string("USBKeyLocationID") ?? raw.string("location_id") ?? name)",
            name: name,
            category: .usb,
            symbol: symbol,
            subtitle: [vendorName, speed].compactMap { $0 }.joined(separator: " · "),
            isApple: isApple,
            isConnected: true,
            sections: [StatSection(title: "USB", items: items)]
        )
    }

    static func displays(profile: [String: Any]) -> [Device] {
        var devices: [Device] = []
        for gpu in profile.array("SPDisplaysDataType") {
            for display in gpu.array("spdisplays_ndrvs") {
                guard let name = display.string("_name") else { continue }
                let isInternal = display.string("spdisplays_connection_type") == "spdisplays_internal"
                let resolution = display.string("_spdisplays_resolution") ?? display.string("spdisplays_resolution")

                var items: [StatItem] = []
                items.add("Grafik", gpu.string("sppci_model"))
                items.add("Auflösung", resolution.map(Format.prettyValue))
                items.add("Pixel", display.string("_spdisplays_pixels"))
                items.add("Anschluss", isInternal ? "Intern" : "Extern")
                var serials: [StatItem] = []
                for key in display.keys.sorted() where !["_name", "_spdisplays_resolution", "_spdisplays_pixels", "spdisplays_connection_type"].contains(key) {
                    let sensitive = key.lowercased().contains("serial")
                    guard let value = display.string(key) else { continue }
                    if sensitive {
                        serials.add(Format.prettyKey(key), value, sensitive: true)
                    } else {
                        items.add(Format.prettyKey(key), Format.prettyValue(value))
                    }
                }
                items += serials

                let vendor = display.string("_spdisplays_display-vendor-id")?.lowercased()
                devices.append(Device(
                    id: "display-\(display.string("_spdisplays_displayID") ?? name)",
                    name: name,
                    category: .display,
                    symbol: isInternal ? "laptopcomputer" : "display",
                    subtitle: [isInternal ? "Intern" : "Extern", resolution.map(Format.prettyValue)].compactMap { $0 }.joined(separator: " · "),
                    isApple: isInternal || vendor == "610" || name.lowercased().contains("apple") || name.lowercased().contains("studio display") || name.lowercased().contains("pro display"),
                    isConnected: true,
                    sections: [StatSection(title: "Display", items: items)]
                ))
            }
        }
        return devices
    }
}
