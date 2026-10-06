import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct DeviceStatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = DeviceStore()
    @AppStorage("hideSensitive") private var hideSensitive = true
    @AppStorage("appleOnly") private var appleOnly = false

    init() {
        // `DeviceStats --dump [--raw]` gibt alle Daten als JSON aus, ohne Fenster zu öffnen.
        if CommandLine.arguments.contains("--dump") {
            CommandLineDump.run(maskSensitive: !CommandLine.arguments.contains("--raw"))
        }
    }

    var body: some Scene {
        WindowGroup("DeviceStats", id: "main") {
            ContentView()
                .environment(store)
                .frame(minWidth: 820, minHeight: 520)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Aktualisieren") { Task { await store.refresh() } }
                    .keyboardShortcut("r")
                Button("Als JSON exportieren …") { Exporter.export(store: store, maskSensitive: hideSensitive, appleOnly: appleOnly) }
                    .keyboardShortcut("e")
            }
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(store)
        } label: {
            Image(systemName: "battery.75percent")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Wird als nacktes Binary (swift run) gestartet → trotzdem als normale App mit Dock-Icon auftreten.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@MainActor
enum Exporter {
    static func export(store: DeviceStore, maskSensitive: Bool, appleOnly: Bool) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "DeviceStats-\(Date.now.formatted(.iso8601.year().month().day())).json"
        panel.message = maskSensitive
            ? "Seriennummern, Adressen und UDIDs werden maskiert."
            : "Achtung: Der Export enthält Seriennummern, Adressen und UDIDs."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportData(maskSensitive: maskSensitive, appleOnly: appleOnly).write(to: url, options: .atomic)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

enum CommandLineDump {
    static func run(maskSensitive: Bool) -> Never {
        let semaphore = DispatchSemaphore(value: 0)
        Task { @MainActor in
            let store = DeviceStore()
            await store.refresh()
            for error in store.errors { FileHandle.standardError.write(Data("⚠︎ \(error)\n".utf8)) }
            if let data = try? store.exportData(maskSensitive: maskSensitive, appleOnly: false) {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
            semaphore.signal()
        }
        // Main-Thread nicht blockieren: RunLoop laufen lassen, bis der Task fertig ist.
        while semaphore.wait(timeout: .now()) == .timedOut {
            RunLoop.main.run(until: .now + 0.05)
        }
        exit(0)
    }
}
