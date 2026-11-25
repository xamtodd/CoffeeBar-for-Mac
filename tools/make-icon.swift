// Erzeugt Resources/AppIcon.png (1024 px): weiße Kaffeetasse auf braunem Verlauf
import AppKit
let size = 1024.0
let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
    let path = NSBezierPath(roundedRect: r.insetBy(dx: 100, dy: 100), xRadius: 185, yRadius: 185)
    NSGradient(starting: NSColor(red: 0.78, green: 0.52, blue: 0.30, alpha: 1),
               ending: NSColor(red: 0.36, green: 0.20, blue: 0.11, alpha: 1))!.draw(in: path, angle: -90)
    let cfg = NSImage.SymbolConfiguration(pointSize: 470, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    let cup = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil)!
        .withSymbolConfiguration(cfg)!
    let s = cup.size
    cup.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2 - 10, width: s.width, height: s.height))
    return true
}
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
