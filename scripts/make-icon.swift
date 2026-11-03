// Draws the app icon: a real QR code inside viewfinder brackets, crossed by a glowing scan line,
// on a deep blue tile.
//   swift scripts/make-icon.swift <out.png>   renders the 1024x1024 master
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

let size = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

/// Module matrix of a real QR code (true = dark), quiet zone trimmed.
func qrModules(_ text: String) -> [[Bool]] {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(text.utf8)
    filter.correctionLevel = "L"
    let image = filter.outputImage!
    let w = Int(image.extent.width), h = Int(image.extent.height)
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    CIContext().render(image, toBitmap: &pixels, rowBytes: w * 4, bounds: image.extent,
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
    // render(toBitmap:) writes the top row first, so row 0 is already the top.
    let grid = (0..<h).map { y in (0..<w).map { x in pixels[(y * w + x) * 4] < 128 } }
    let rows = grid.indices.filter { grid[$0].contains(true) }
    let cols = (0..<w).filter { x in grid.contains { $0[x] } }
    return rows.map { y in cols.map { grid[y][$0] } }
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
// Top-left origin, y growing down, like the coordinates below.
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 1, y: -1)

let space = CGColorSpaceCreateDeviceRGB()
func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
func gradient(_ colors: [CGColor], _ stops: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: stops)!
}

// Tile: the macOS icon grid keeps a 100pt margin around an 824pt rounded square.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: rgb(0x000000, 0.35))
ctx.addPath(tilePath)
ctx.setFillColor(rgb(0x14204A))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0x2B3F8C), rgb(0x0E1633)], [0, 1]),
                       start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
// Soft green glow where the scan line passes.
ctx.drawRadialGradient(gradient([rgb(0x34E89E, 0.22), rgb(0x34E89E, 0)], [0, 1]),
                       startCenter: CGPoint(x: 512, y: 560), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 560), endRadius: 430, options: [])
ctx.restoreGState()

// QR code: white modules, with the three finder patterns drawn as solid rounded squares.
let modules = qrModules("QR Reader")
let n = modules.count
let qrRect = CGRect(x: 297, y: 297, width: 430, height: 430)
let cell = qrRect.width / CGFloat(n)
let finders = [(0, 0), (n - 7, 0), (0, n - 7)]
func inFinder(_ x: Int, _ y: Int) -> Bool {
    finders.contains { x >= $0.0 && x < $0.0 + 7 && y >= $0.1 && y < $0.1 + 7 }
}
func cellRect(_ x: Int, _ y: Int, _ w: Int = 1, _ h: Int = 1) -> CGRect {
    CGRect(x: qrRect.minX + CGFloat(x) * cell, y: qrRect.minY + CGFloat(y) * cell,
           width: CGFloat(w) * cell, height: CGFloat(h) * cell)
}
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 4), blur: 8, color: rgb(0x000000, 0.35))
ctx.setFillColor(rgb(0xF4F7FF))
for (y, row) in modules.enumerated() {
    for (x, dark) in row.enumerated() where dark && !inFinder(x, y) {
        let r = cellRect(x, y).insetBy(dx: cell * 0.05, dy: cell * 0.05)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: cell * 0.22, cornerHeight: cell * 0.22, transform: nil))
    }
}
ctx.fillPath()
for (fx, fy) in finders {
    // Outer ring (7x7 minus 5x5), then the 3x3 eye.
    let outer = cellRect(fx, fy, 7, 7), inner = cellRect(fx + 1, fy + 1, 5, 5)
    ctx.addPath(CGPath(roundedRect: outer, cornerWidth: cell * 1.8, cornerHeight: cell * 1.8, transform: nil))
    ctx.addPath(CGPath(roundedRect: inner, cornerWidth: cell * 1.1, cornerHeight: cell * 1.1, transform: nil))
    ctx.fillPath(using: .evenOdd)
    ctx.addPath(CGPath(roundedRect: cellRect(fx + 2, fy + 2, 3, 3), cornerWidth: cell * 0.8, cornerHeight: cell * 0.8, transform: nil))
    ctx.fillPath()
}
ctx.restoreGState()

// Viewfinder corner brackets.
let frame = CGRect(x: 215, y: 215, width: 594, height: 594)
let arm: CGFloat = 130
ctx.setLineWidth(38)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.setStrokeColor(rgb(0xFFFFFF))
for (corner, dx, dy) in [(CGPoint(x: frame.minX, y: frame.minY), 1.0, 1.0), (CGPoint(x: frame.maxX, y: frame.minY), -1.0, 1.0),
                         (CGPoint(x: frame.minX, y: frame.maxY), 1.0, -1.0), (CGPoint(x: frame.maxX, y: frame.maxY), -1.0, -1.0)] {
    ctx.move(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
    ctx.addLine(to: corner)
    ctx.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
}
ctx.strokePath()

// Scan line with glow, fading at both ends.
let lineY: CGFloat = 560
let line = CGRect(x: 180, y: lineY - 9, width: 664, height: 18)
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 36, color: rgb(0x34E89E, 0.9))
ctx.addPath(CGPath(roundedRect: line, cornerWidth: 9, cornerHeight: 9, transform: nil))
ctx.setFillColor(rgb(0x34E89E))
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: line, cornerWidth: 9, cornerHeight: 9, transform: nil))
ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0x34E89E, 0.2), rgb(0xB8FFE0), rgb(0x34E89E, 0.2)], [0, 0.5, 1]),
                       start: CGPoint(x: line.minX, y: lineY), end: CGPoint(x: line.maxX, y: lineY), options: [])
ctx.restoreGState()

NSGraphicsContext.current = nil
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
