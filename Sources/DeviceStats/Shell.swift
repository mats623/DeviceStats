import Foundation

enum Shell {
    struct Failure: Error, LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    /// Führt ein Programm aus und liefert stdout. Läuft blockierend – nur außerhalb des Main-Threads aufrufen.
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 30) throws -> Data {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw Failure(message: "\(executable) nicht gefunden")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()

        let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        // Erst lesen, dann warten – sonst blockiert ein voller Pipe-Puffer den Prozess.
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timer.cancel()

        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw Failure(message: "\(executable) \(arguments.first ?? "") fehlgeschlagen (\(process.terminationStatus))")
        }
        return data
    }

    static func json(_ executable: String, _ arguments: [String], timeout: TimeInterval = 30) throws -> [String: Any] {
        let data = try run(executable, arguments, timeout: timeout)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure(message: "Unerwartete Ausgabe von \(executable)")
        }
        return object
    }

    static func plist(_ executable: String, _ arguments: [String], timeout: TimeInterval = 30) throws -> Any {
        let data = try run(executable, arguments, timeout: timeout)
        return try PropertyListSerialization.propertyList(from: data, format: nil)
    }

    static func systemProfiler(_ types: [String]) throws -> [String: Any] {
        try json("/usr/sbin/system_profiler", types + ["-json", "-detailLevel", "full"], timeout: 60)
    }

    /// Sucht ein optionales Hilfsprogramm (z. B. aus Homebrew).
    static func find(_ name: String) -> String? {
        ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
            .map { "\($0)/\(name)" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

// MARK: - Helfer für lose typisierte JSON-/Plist-Daten

extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? {
        switch self[key] {
        case let s as String: s
        case let n as NSNumber: n.stringValue
        default: nil
        }
    }

    func int(_ key: String) -> Int? {
        switch self[key] {
        case let n as NSNumber: n.intValue
        case let s as String: Int(s.filter { $0.isNumber || $0 == "-" })
        default: nil
        }
    }

    func bool(_ key: String) -> Bool? {
        switch self[key] {
        case let b as Bool: b
        case let n as NSNumber: n.boolValue
        case let s as String: ["true", "yes", "1", "attrib_yes", "attrib_on"].contains(s.lowercased())
        default: nil
        }
    }

    func dict(_ key: String) -> [String: Any]? { self[key] as? [String: Any] }
    func array(_ key: String) -> [[String: Any]] { self[key] as? [[String: Any]] ?? [] }
}

enum Format {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func memory(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .memory)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = seconds >= 86_400 ? [.day, .hour, .minute] : [.hour, .minute]
        f.unitsStyle = .abbreviated
        return f.string(from: seconds) ?? "–"
    }

    static func yesNo(_ value: Bool?) -> String? {
        value.map { $0 ? "Ja" : "Nein" }
    }

    /// "spdisplays_resolution" → "Resolution", "device_firmwareVersion" → "Firmware Version"
    static func prettyKey(_ key: String) -> String {
        var k = key
        for prefix in ["_spdisplays_", "spdisplays_", "sppower_", "device_", "USBDeviceKey", "USBKey", "_"] where k.hasPrefix(prefix) {
            k.removeFirst(prefix.count)
        }
        var out = ""
        for (i, ch) in k.enumerated() {
            if ch == "_" { out.append(" "); continue }
            if ch.isUppercase, i > 0, let last = out.last, last.isLowercase { out.append(" ") }
            out.append(ch)
        }
        return out.prefix(1).uppercased() + out.dropFirst()
    }

    /// system_profiler liefert Werte wie "attrib_on" oder "spdisplays_yes".
    static func prettyValue(_ value: String) -> String {
        var v = value
        for prefix in ["attrib_", "spdisplays_", "sppci_", "ppci_"] where v.hasPrefix(prefix) {
            v.removeFirst(prefix.count)
        }
        switch v.lowercased() {
        case "yes", "on", "true": return "Ja"
        case "no", "off", "false": return "Nein"
        default: return v.replacingOccurrences(of: "_", with: " ")
        }
    }
}
