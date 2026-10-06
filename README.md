# DeviceStats

Eine native macOS-App (SwiftUI), die alle Statistiken deines Macs und der angeschlossenen bzw. gekoppelten (Apple-)Geräte ausliest und übersichtlich anzeigt.

## Was wird ausgelesen?

| Quelle | Geräte | Daten |
|---|---|---|
| **Dieser Mac** | MacBook, iMac, Mac mini … | Modell, Chip, Kerne, RAM-Auslastung, Speicherplatz, Laufzeit, Systemlast, thermischer Zustand, Akku (Ladestand, Zyklen, Zustand, max. Kapazität, mAh, Spannung, Stromstärke, Temperatur, Restlaufzeit), Netzteil |
| **devicectl** (Xcode) | iPhone, iPad, Apple Watch, Apple TV, Vision Pro | Modell, iOS-Version, Build, Verbindung (USB/WLAN), Kopplung, Entwicklermodus, zuletzt verbunden |
| **libimobiledevice** (optional) | per USB verbundene iPhones/iPads | Akkustand, Ladezustand, Speicherbelegung, Gerätefarbe, Region … |
| **Bluetooth** | AirPods, AirPods Max, Magic Keyboard/Mouse/Trackpad, Beats … | Akku (links/rechts/Case), Firmware, Modell, Signalstärke, Status |
| **USB** | alles am USB-Bus | Hersteller, Geschwindigkeit, Strombedarf, IDs |
| **Displays** | intern & extern (z. B. Studio Display) | Auflösung, Bildwiederholrate, Anschluss |

Außerdem:

- **Übersicht** mit Kennzahlen und allen Akkus auf einen Blick
- **Akkuverlauf** als Diagramm (6 Std. bis 30 Tage), lokal gespeichert
- **Menüleisten-Icon** mit allen Akkuständen
- **Datenschutzmodus**: Seriennummern, Adressen und UDIDs werden maskiert
- **Filter**: nur Apple-Geräte, nur verbundene Geräte
- **Automatische Aktualisierung** (30 s / 1 min / 5 min)
- **JSON-Export** (⌘E) – standardmäßig anonymisiert

## Voraussetzungen

- macOS 14 oder neuer
- Xcode (für `devicectl`, also iPhone/iPad/Watch) bzw. die Command Line Tools zum Bauen
- Optional für Akku & Speicher von iPhone/iPad: `brew install libimobiledevice`

## Bauen & Starten

```bash
./scripts/build-app.sh          # erzeugt build/DeviceStats.app
open build/DeviceStats.app
```

Zum Entwickeln reicht auch `swift run`.

Kommandozeile ohne Fenster:

```bash
.build/debug/DeviceStats --dump        # alle Daten als JSON (anonymisiert)
.build/debug/DeviceStats --dump --raw  # inkl. Seriennummern
```

## Hinweise

- Die App ist nicht sandboxed, weil sie `system_profiler`, `ioreg` und `xcrun devicectl` aufruft.
- iPhones/iPads müssen dem Mac einmal vertraut haben („Diesem Computer vertrauen?“).
- Die vorkompilierte App aus den Releases ist nur ad-hoc signiert. Beim ersten Start: Rechtsklick → „Öffnen“.
- Der Akkuverlauf liegt unter `~/Library/Application Support/DeviceStats/`. Es werden keine Daten ins Netz gesendet.

## Lizenz

MIT
