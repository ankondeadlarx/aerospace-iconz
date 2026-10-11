// Draws the app icon into an .iconset: swift scripts/make-app-icon.swift <out.iconset>
// Then: iconutil -c icns <out.iconset> -o Resources/AppIcon.icns  (see `make icon`).
//
// The focused workspace pill "2" with three app tiles, floating on a Sequoia-style gradient.
// Geometry is the menu bar pill spec (DESIGN.md › Visual style) scaled by k canvas px per pt,
// on Apple's 1024 icon grid (824 body). Chosen in the prototype on branch prototype/app-icon.
import AppKit
import CoreText

let canvas: CGFloat = 1024
let k: CGFloat = 9.5          // canvas px per menu bar pt
let labelScale: CGFloat = 1.45 // label drawn larger than the bar's 11 pt so it reads at icon size

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

func gradient(_ a: CGColor, _ b: CGColor) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [a, b] as CFArray, locations: [0, 1])!
}

// Superellipse (n = 5) approximating the continuous-corner icon shape: 824 body centred in 1024.
func squircle() -> CGPath {
    let path = CGMutablePath(), n: CGFloat = 5, c: CGFloat = 512, r: CGFloat = 412, steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let p = CGPoint(x: c + r * (ct < 0 ? -1 : 1) * pow(abs(ct), 2 / n),
                        y: c + r * (st < 0 ? -1 : 1) * pow(abs(st), 2 / n))
        i == 0 ? path.move(to: p) : path.addLine(to: p)
    }
    path.closeSubpath()
    return path
}

// Draws in a y-down 1024 × 1024 space, like the SVG prototype.
func draw(in ctx: CGContext) {
    let shape = squircle()

    // Drop shadow under the body. Shadow offset and blur are in device space (y-up, unscaled).
    let s = ctx.userSpaceToDeviceSpaceTransform.a
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12 * s), blur: 24 * s, color: rgb(0x000000, 0.28))
    ctx.addPath(shape); ctx.setFillColor(rgb(0x000000)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()

    // Background: diagonal navy → plum, coral glow bottom right, blue glow top left.
    ctx.drawLinearGradient(gradient(rgb(0x0a1a52), rgb(0x5a1f6e)),
                           start: .zero, end: CGPoint(x: canvas, y: canvas), options: [])
    for (cx, cy, r, color, alpha) in [(0.85, 0.95, 0.75, 0xff5e7a as UInt32, 0.8), (0.0, 0.2, 0.6, 0x2f7bff, 0.6)] {
        let centre = CGPoint(x: cx * canvas, y: cy * canvas)
        ctx.drawRadialGradient(gradient(rgb(color, alpha), rgb(color, 0)), startCenter: centre, startRadius: 0,
                               endCenter: centre, endRadius: r * canvas, options: [])
    }

    // The focused pill, centred. Neighbouring pills would start outside the body, so they're omitted.
    let pillH = 20 * k, tile = 16 * k, gap = 2 * k, labelToIcon = 4 * k, pad = 5 * k
    let fontSize = 11 * k * labelScale, labelW = 0.6 * fontSize
    let pillW = pad + labelW + labelToIcon + 3 * tile + 2 * gap + pad
    let x0 = (canvas - pillW) / 2, y0 = (canvas - pillH) / 2
    ctx.addPath(CGPath(roundedRect: CGRect(x: x0, y: y0, width: pillW, height: pillH),
                       cornerWidth: 5 * k, cornerHeight: 5 * k, transform: nil))
    ctx.setFillColor(rgb(0xffffff, 0.24)); ctx.fillPath()

    // Label "2": baseline sits a little below the pill's centre line.
    let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "2", attributes: [
        .font: font, .foregroundColor: NSColor.white]))
    ctx.saveGState()
    ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    ctx.textPosition = CGPoint(x: x0 + pad, y: canvas / 2 + fontSize * 0.36)
    CTLineDraw(line, ctx)
    ctx.restoreGState()

    // App tiles: orange, blue, purple, each a top-to-bottom gradient.
    let tiles: [(UInt32, UInt32)] = [(0xff9a5a, 0xf2542d), (0x4aa3ff, 0x1f5fe0), (0xb48cff, 0x6a3fe0)]
    for (i, (top, bottom)) in tiles.enumerated() {
        let rect = CGRect(x: x0 + pad + labelW + labelToIcon + CGFloat(i) * (tile + gap), y: y0 + 2 * k,
                          width: tile, height: tile)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: tile * 0.23, cornerHeight: tile * 0.23, transform: nil))
        ctx.clip()
        ctx.drawLinearGradient(gradient(rgb(top), rgb(bottom)), start: CGPoint(x: rect.midX, y: rect.minY),
                               end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
        ctx.restoreGState()
    }
    ctx.restoreGState()

    // Hairline edge.
    ctx.addPath(shape); ctx.setStrokeColor(rgb(0x000000, 0.12)); ctx.setLineWidth(2); ctx.strokePath()
}

func png(size px: Int, to url: URL) throws {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(px) / canvas
    ctx.translateBy(x: 0, y: CGFloat(px)); ctx.scaleBy(x: s, y: -s) // y-down, 1024 units
    draw(in: ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: make-app-icon.swift <out.iconset>\n".data(using: .utf8)!)
    exit(2)
}
let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(size: base, to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(size: base * 2, to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print(out.path)
