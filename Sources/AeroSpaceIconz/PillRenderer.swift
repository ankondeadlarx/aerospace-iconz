import AppKit
import IconzCore

/// Draws a `PillLayout` into one image for the status item button. All positions come
/// from the layout; this only paints.
@MainActor
struct PillRenderer {
    let config: Config
    let icons: IconCache

    var font: NSFont {
        .monospacedDigitSystemFont(ofSize: config.labelFontSize, weight: NSFont.Weight(config.labelFontWeight))
    }

    func measure(_ text: String) -> Double {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    func layout(for state: BarState) -> PillLayout {
        PillLayout(state: state, config: config.layout, measure: measure)
    }

    func image(for layout: PillLayout) -> NSImage {
        let m = config.layout.metrics
        let size = NSSize(width: max(layout.totalWidth, 1), height: m.pillHeight)
        let images = layout.pills.map { $0.icons.map(icons.icon(for:)) }
        let font = font
        let config = config

        // The handler runs at draw time, so system colors resolve against the menu bar's
        // current appearance (light, dark, or tinted).
        let image = NSImage(size: size, flipped: false) { _ in
            let label = NSColor.labelColor
            for (index, pill) in layout.pills.enumerated() {
                let frame = layout.frames[index]
                let rect = NSRect(x: frame.x, y: 0, width: frame.width, height: m.pillHeight)
                let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                                        xRadius: m.cornerRadius, yRadius: m.cornerRadius)
                switch pill.emphasis {
                case .fill:
                    label.withAlphaComponent(config.focusedFillAlpha).setFill()
                    path.fill()
                case .outline:
                    label.withAlphaComponent(config.visibleStrokeAlpha).setStroke()
                    path.lineWidth = config.visibleStrokeWidth
                    path.stroke()
                case .none:
                    break
                }

                drawText(pill.label, at: frame.labelX, height: m.pillHeight, font: font, color: label)
                for (icon, x) in zip(images[index], frame.iconXs) {
                    let y = (m.pillHeight - m.iconSize) / 2
                    icon.draw(in: NSRect(x: x, y: y, width: m.iconSize, height: m.iconSize))
                }
                if let overflow = pill.overflowLabel, let x = frame.overflowX {
                    drawText(overflow, at: x, height: m.pillHeight, font: font,
                             color: label.withAlphaComponent(config.overflowLabelAlpha))
                }
            }
            return true
        }
        guard layout.isDimmed else { return image }
        return NSImage(size: size, flipped: false) { rect in
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: config.unavailableAlpha)
            return true
        }
    }
}

/// Draws `text` vertically centered in a row of `height`, starting at `x`.
private func drawText(_ text: String, at x: Double, height: Double, font: NSFont, color: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let size = (text as NSString).size(withAttributes: attributes)
    (text as NSString).draw(at: NSPoint(x: x, y: (height - size.height) / 2), withAttributes: attributes)
}
