// Rendert das App-Icon (1024×1024 PNG): swift scripts/make-icon.swift <ausgabe.png>
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let rect = NSRect(x: 100, y: 100, width: 824, height: 824)
let path = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(red: 0.20, green: 0.55, blue: 1.0, alpha: 1), NSColor(red: 0.42, green: 0.25, blue: 0.95, alpha: 1)])!
    .draw(in: path, angle: -60)

let config = NSImage.SymbolConfiguration(pointSize: 420, weight: .medium)
    .applying(.init(paletteColors: [.white]))
if let symbol = NSImage(systemSymbolName: "macbook.and.iphone", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
    let s = symbol.size
    symbol.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
}
image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
