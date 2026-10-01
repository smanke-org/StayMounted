// Draws Resources/AppIcon.png: the same SF Symbol the menu bar shows when everything is
// mounted, white on a teal tile, so the app icon and the menu bar item read as one thing.
// Run via ./Tools/make_icns.sh.
import AppKit

let size = CGFloat(1024)
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let rect = NSRect(x: 0, y: 0, width: size, height: size)
let tile = NSBezierPath(roundedRect: rect, xRadius: size * 0.225, yRadius: size * 0.225)
NSGradient(colors: [
    NSColor(srgbRed: 0.16, green: 0.66, blue: 0.62, alpha: 1),
    NSColor(srgbRed: 0.05, green: 0.40, blue: 0.45, alpha: 1),
])?.draw(in: tile, angle: -90)

let config = NSImage.SymbolConfiguration(pointSize: size * 0.46, weight: .regular)
    .applying(.init(paletteColors: [.white]))
guard let symbol = NSImage(systemSymbolName: "externaldrive.connected.to.line.below.fill",
                           accessibilityDescription: nil)?.withSymbolConfiguration(config)
else { fatalError("Symbol missing") }
let symbolSize = symbol.size
symbol.draw(in: NSRect(x: (size - symbolSize.width) / 2, y: (size - symbolSize.height) / 2 - size * 0.01,
                       width: symbolSize.width, height: symbolSize.height))
image.unlockFocus()

// lockFocus renders at the display's backing scale; read back whatever came out and let
// sips downsample.
guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:])
else { fatalError("Could not render the icon.") }
try! png.write(to: URL(fileURLWithPath: "Resources/AppIcon.png"))
print("Wrote Resources/AppIcon.png at \(bitmap.pixelsWide)x\(bitmap.pixelsHigh)")
