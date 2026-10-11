import AppKit
import IconzCore

/// Draws a `PillLayout` into one image for the status item button.
@MainActor
struct PillRenderer {
    let config: Config
    let icons: IconCache

    var font: NSFont { .monospacedDigitSystemFont(ofSize: config.labelFontSize, weight: .medium) }

    func measure(_ text: String) -> Double {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    func layout(for groups: [WorkspaceGroup]) -> PillLayout {
        PillLayout(groups: groups, config: config.layout, measure: measure)
    }

    /// Placeholder shown while AeroSpace can't be reached.
    func unavailableLayout() -> PillLayout {
        layout(for: [WorkspaceGroup(name: "–", isFocused: false, isVisible: false, apps: [])])
    }

    func image(for layout: PillLayout, dimmed: Bool = false) -> NSImage {
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
                if pill.isFocused {
                    label.withAlphaComponent(config.focusedFillAlpha).setFill()
                    path.fill()
                } else if pill.isVisible {
                    label.withAlphaComponent(config.visibleStrokeAlpha).setStroke()
                    path.lineWidth = config.visibleStrokeWidth
                    path.stroke()
                }

                var x = frame.x + m.horizontalPadding
                x = drawText(pill.name, at: x, height: m.pillHeight, font: font, color: label)

                if !pill.icons.isEmpty { x += m.labelIconGap }
                for (iconIndex, icon) in images[index].enumerated() {
                    if iconIndex > 0 { x += m.iconGap }
                    let y = (m.pillHeight - m.iconSize) / 2
                    icon.draw(in: NSRect(x: x, y: y, width: m.iconSize, height: m.iconSize))
                    x += m.iconSize
                }

                if let overflow = pill.overflowLabel {
                    x += m.iconGap
                    _ = drawText(overflow, at: x, height: m.pillHeight, font: font,
                                 color: .secondaryLabelColor)
                }
            }
            return true
        }
        if dimmed {
            return NSImage(size: size, flipped: false) { rect in
                image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: config.unavailableAlpha)
                return true
            }
        }
        return image
    }

    /// Draws `text` vertically centered at `x`; returns the x just past it.
    private func drawText(_ text: String, at x: Double, height: Double, font: NSFont, color: NSColor) -> Double {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: x, y: (height - size.height) / 2), withAttributes: attributes)
        return x + ceil(size.width)
    }
}
