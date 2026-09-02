import AppKit
import Foundation

enum AppIconGenerator {
    static func writePNG(to url: URL) throws {
        let size = NSSize(width: 1024, height: 1024)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.clear.setFill()
            rect.fill()

            let outer = NSBezierPath(roundedRect: NSRect(x: 44, y: 44, width: 936, height: 936), xRadius: 220, yRadius: 220)
            let gradient = NSGradient(colors: [
                NSColor(red: 0.05, green: 0.30, blue: 0.95, alpha: 1),
                NSColor(red: 0.05, green: 0.63, blue: 0.92, alpha: 1)
            ])
            gradient?.draw(in: outer, angle: -55)

            NSGraphicsContext.current?.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
            shadow.shadowBlurRadius = 34
            shadow.shadowOffset = NSSize(width: 0, height: -18)
            shadow.set()
            NSColor.white.setFill()
            NSBezierPath(roundedRect: NSRect(x: 206, y: 190, width: 612, height: 644), xRadius: 64, yRadius: 64).fill()
            NSGraphicsContext.current?.restoreGraphicsState()

            let bottle = NSBezierPath(roundedRect: NSRect(x: 400, y: 330, width: 224, height: 330), xRadius: 72, yRadius: 72)
            NSColor(red: 0.04, green: 0.35, blue: 0.86, alpha: 1).setFill()
            bottle.fill()
            NSBezierPath(roundedRect: NSRect(x: 448, y: 652, width: 128, height: 78), xRadius: 22, yRadius: 22).fill()
            NSBezierPath(roundedRect: NSRect(x: 438, y: 716, width: 148, height: 34), xRadius: 12, yRadius: 12).fill()

            NSColor.white.withAlphaComponent(0.92).setFill()
            NSBezierPath(roundedRect: NSRect(x: 437, y: 436, width: 150, height: 100), xRadius: 18, yRadius: 18).fill()
            NSColor(red: 0.05, green: 0.45, blue: 0.92, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 466, y: 477, width: 92, height: 12), xRadius: 6, yRadius: 6).fill()

            let cropColor = NSColor.white.withAlphaComponent(0.92)
            cropColor.setStroke()
            drawCorner(from: CGPoint(x: 142, y: 276), horizontal: 76, vertical: 76)
            drawCorner(from: CGPoint(x: 882, y: 276), horizontal: -76, vertical: 76)
            drawCorner(from: CGPoint(x: 142, y: 862), horizontal: 76, vertical: -76)
            drawCorner(from: CGPoint(x: 882, y: 862), horizontal: -76, vertical: -76)
            return true
        }

        guard let data = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: data),
              let png = representation.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "WebsiteImagePrep", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create app icon PNG."])
        }
        try png.write(to: url, options: .atomic)
    }

    private static func drawCorner(from point: CGPoint, horizontal: CGFloat, vertical: CGFloat) {
        let path = NSBezierPath()
        path.lineWidth = 22
        path.lineCapStyle = .round
        path.move(to: CGPoint(x: point.x + horizontal, y: point.y))
        path.line(to: point)
        path.line(to: CGPoint(x: point.x, y: point.y + vertical))
        path.stroke()
    }
}
