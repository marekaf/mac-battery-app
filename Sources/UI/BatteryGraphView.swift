import AppKit

class BatteryGraphView: NSView {
    var readings: [BatteryReading] = []
    private let graphWidth: CGFloat = 200
    private let graphHeight: CGFloat = 40
    private let padding: CGFloat = 8

    override var intrinsicContentSize: NSSize {
        NSSize(width: graphWidth + padding * 2, height: graphHeight + padding * 2 + 16)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard readings.count >= 2 else {
            drawNoDataLabel()
            return
        }

        let graphRect = NSRect(x: padding, y: padding, width: graphWidth, height: graphHeight)

        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: graphRect, xRadius: 4, yRadius: 4).fill()

        NSColor.separatorColor.setStroke()
        for pct in [0.25, 0.5, 0.75] {
            let y = graphRect.minY + graphRect.height * CGFloat(pct)
            let line = NSBezierPath()
            line.move(to: NSPoint(x: graphRect.minX, y: y))
            line.line(to: NSPoint(x: graphRect.maxX, y: y))
            line.lineWidth = 0.5
            line.stroke()
        }

        let path = NSBezierPath()
        let timeRange = readings.last!.timestamp.timeIntervalSince(readings.first!.timestamp)
        guard timeRange > 0 else { return }

        for (i, reading) in readings.enumerated() {
            let x = graphRect.minX + graphRect.width * CGFloat(reading.timestamp.timeIntervalSince(readings.first!.timestamp) / timeRange)
            let y = graphRect.minY + graphRect.height * CGFloat(reading.level) / 100.0
            if i == 0 { path.move(to: NSPoint(x: x, y: y)) }
            else { path.line(to: NSPoint(x: x, y: y)) }
        }

        NSColor.systemBlue.setStroke()
        path.lineWidth = 1.5
        path.stroke()

        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let label = "\(formatter.string(from: readings.first!.timestamp)) – \(formatter.string(from: readings.last!.timestamp))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        (label as NSString).draw(at: NSPoint(x: padding, y: graphRect.maxY + 2), withAttributes: attrs)
    }

    private func drawNoDataLabel() {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        ("Not enough data" as NSString).draw(at: NSPoint(x: padding, y: padding), withAttributes: attrs)
    }
}
