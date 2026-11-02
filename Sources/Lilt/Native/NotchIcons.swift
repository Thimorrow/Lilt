import SwiftUI

/// The study's SVG symbols, drawn from their original path data (24-unit view box unless stated).
enum NotchIcon {
    case play, pause, next, previous, music, focus, shelf, file, folder, reset, chevronDown, settings, plus, trash, more
    // Settings window symbols from the former settings.html.
    case wordmark, navMusic, navFocus, navShelf, navNotifications, navGeneral, check, chevron, arrow, spotify, appleMusic, meld, brain, error

    fileprivate struct Part {
        /// `cutout` strokes use the icon's cutout colour (the Spotify grooves).
        enum Kind { case fill, stroke(CGFloat), cutout(CGFloat) }
        var path: Path
        var kind: Kind
    }

    var viewBox: CGSize {
        switch self {
        case .wordmark: return CGSize(width: 152, height: 100)
        case .spotify, .appleMusic, .meld: return CGSize(width: 32, height: 32)
        default: return CGSize(width: 24, height: 24)
        }
    }

    fileprivate var parts: [Part] {
        let s = { (d: String, w: CGFloat) in Part(path: SVGPath.parse(d), kind: .stroke(w)) }
        let f = { (d: String) in Part(path: SVGPath.parse(d), kind: .fill) }
        switch self {
        case .play: return [f("M8 5.5v13a1 1 0 0 0 1.5.86l10.4-6.5a1 1 0 0 0 0-1.72L9.5 4.64A1 1 0 0 0 8 5.5Z")]
        case .pause:
            return [Part(path: Path(roundedRect: CGRect(x: 6.5, y: 5, width: 4, height: 14), cornerRadius: 1.4), kind: .fill),
                    Part(path: Path(roundedRect: CGRect(x: 13.5, y: 5, width: 4, height: 14), cornerRadius: 1.4), kind: .fill)]
        case .next, .previous:
            return [f("M5 6.6v10.8a.9.9 0 0 0 1.4.75l8.1-5.4a.9.9 0 0 0 0-1.5L6.4 5.85A.9.9 0 0 0 5 6.6Z"),
                    Part(path: Path(roundedRect: CGRect(x: 16.6, y: 5.5, width: 2.6, height: 13), cornerRadius: 1.3), kind: .fill)]
        case .music:
            return [s("M9 18V6l10-2v12", 1.9), Part(path: circle(6.5, 18, 2.5), kind: .stroke(1.9)), Part(path: circle(16.5, 16, 2.5), kind: .stroke(1.9))]
        case .focus: return [Part(path: circle(12, 13.5, 7.5), kind: .stroke(1.9)), s("M12 9.5v4l2.6 1.6M9.5 3h5", 1.9)]
        case .shelf:
            return [s("M3.5 13.5 6 6.5A2 2 0 0 1 7.9 5h8.2A2 2 0 0 1 18 6.5l2.5 7v4A1.5 1.5 0 0 1 19 19H5a1.5 1.5 0 0 1-1.5-1.5Z", 1.9),
                    s("M3.5 13.5H8l1.5 2h5l1.5-2h4.5", 1.9)]
        case .file: return [s("M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8Z", 1.9), s("M14 3v5h5", 1.9)]
        case .folder: return [s("M3.5 7.5a2 2 0 0 1 2-2h3.6l2 2h7.4a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2Z", 1.9)]
        case .reset: return [s("M4.5 12a7.5 7.5 0 1 0 2.2-5.3", 1.9), s("M4.5 4.5v4h4", 1.9)]
        // The web chevron is the "up" symbol rotated by 180 degrees.
        case .chevronDown: return [s("M6 9l6 6 6-6", 2.1)]
        case .settings:
            return [s("m9.3 3-.5 2-1.4.8-2-.5-2.7 4.6 1.6 1.5v1.6l-1.6 1.5 2.7 4.6 2-.5 1.4.8.5 2h5.4l.5-2 1.4-.8 2 .5 2.7-4.6-1.6-1.5v-1.6l1.6-1.5-2.7-4.6-2 .5-1.4-.8-.5-2Z", 1.7),
                    Part(path: circle(12, 12.2, 3), kind: .stroke(1.7))]
        case .plus: return [s("M12 5v14M5 12h14", 2)]
        case .trash: return [s("M4.5 7h15M9.5 7V5.5a1 1 0 0 1 1-1h3a1 1 0 0 1 1 1V7M6.5 7l.8 11.1a1.5 1.5 0 0 0 1.5 1.4h6.4a1.5 1.5 0 0 0 1.5-1.4L17.5 7", 1.8)]
        case .more: return [6, 12, 18].map { Part(path: circle($0, 12, 1.6), kind: .fill) }
        case .wordmark:
            return [s("M11 12V86M45 54V86M79 12V86M113 24V68Q113 86 131 86M101 48H137", 22), f("M30 2H60V18A8 8 0 0 1 52 26H38A8 8 0 0 1 30 18Z")]
        case .navMusic:
            return [s("M9 18V6l10-2v12", 1.7), Part(path: circle(6.5, 18, 2.5), kind: .stroke(1.7)), Part(path: circle(16.5, 16, 2.5), kind: .stroke(1.7))]
        case .navFocus: return [Part(path: circle(12, 13.5, 7.5), kind: .stroke(1.7)), s("M12 9.5v4l2.6 1.6M9.5 3h5", 1.7)]
        case .navShelf: return [s("M4 5h16v14H4zM4 14h5l1.5 2h3l1.5-2h5", 1.7)]
        case .navNotifications: return [s("M6.5 16.5v-5a5.5 5.5 0 0 1 11 0v5l1.5 2h-14Z", 1.7), s("M10 21h4", 1.7)]
        case .navGeneral:
            return [s("M4 7h9m4 0h3M4 17h3m4 0h9", 1.7), Part(path: circle(15, 7, 2), kind: .stroke(1.7)), Part(path: circle(9, 17, 2), kind: .stroke(1.7))]
        case .check: return [s("m6 12 4 4 8-8", 2)]
        case .chevron: return [s("m7 10 5 5 5-5", 1.8)]
        case .arrow: return [s("M5 12h14m-6-6 6 6-6 6", 1.7)]
        case .spotify:
            return [Part(path: circle(16, 16, 13), kind: .fill),
                    Part(path: SVGPath.parse("M8.5 12.1c5.5-1.6 10.8-1.1 15.4 1.5"), kind: .cutout(2.2)),
                    Part(path: SVGPath.parse("M9.6 16.2c4.5-1.3 8.8-.8 12.8 1.2"), kind: .cutout(1.9)),
                    Part(path: SVGPath.parse("M10.7 20.1c3.7-.9 6.9-.6 10.1 1"), kind: .cutout(1.6))]
        case .appleMusic:
            let note = "M24.4 4.7v17c0 2.2-1.5 3.7-3.8 4.1-2.2.4-4-.6-4-2.3 0-1.6 1.2-2.8 3.3-3.2l2-.4V11l-11.3 2.4v11c0 2.2-1.6 3.8-3.9 4.1-2.2.4-4-.6-4-2.3 0-1.6 1.3-2.8 3.4-3.2l2-.4V9.3c0-.7.4-1.2 1.1-1.3l13.7-2.9c.8-.2 1.5-.1 1.5-.4Z"
            return [Part(path: SVGPath.parse(note).offsetBy(dx: 2, dy: -1), kind: .fill)]
        case .meld: return [s("M5 23V10a2 2 0 0 1 3.5-1.3L16 17l7.5-8.3A2 2 0 0 1 27 10v13", 2.4), s("m10 23 6-6 6 6", 2.4)]
        case .brain:
            return [s("M12 20V5a3 3 0 0 0-5.7-1.3 3.5 3.5 0 0 0-3 5.5A4 4 0 0 0 5 16.8 3.5 3.5 0 0 0 12 20Zm0 0V5a3 3 0 0 1 5.7-1.3 3.5 3.5 0 0 1 3 5.5 4 4 0 0 1-1.7 7.6A3.5 3.5 0 0 1 12 20Z", 1.6),
                    s("M7 8c3 0 3 4 0 4m10-4c-3 0-3 4 0 4M7 17h1m8 0h1", 1.6)]
        case .error: return [Part(path: circle(12, 12, 8.5), kind: .stroke(1.7)), s("M12 7.5v5m0 3.5v.1", 1.9)]
        }
    }

    private func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }
}

struct IconView: View {
    let icon: NotchIcon
    var size: CGFloat = 22
    var cutout = Color.black

    var body: some View {
        let box = icon.viewBox
        Canvas { context, canvasSize in
            let scale = canvasSize.width / box.width
            context.scaleBy(x: scale, y: scale)
            if icon == .previous { context.translateBy(x: 24, y: 0); context.scaleBy(x: -1, y: 1) }
            for part in icon.parts {
                switch part.kind {
                case .fill: context.fill(part.path, with: .foreground)
                case .stroke(let width):
                    context.stroke(part.path, with: .foreground, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                case .cutout(let width):
                    context.stroke(part.path, with: .color(cutout), style: StrokeStyle(lineWidth: width, lineCap: .round))
                }
            }
        }
        .frame(width: size, height: size * box.height / box.width)
        .accessibilityHidden(true)
    }
}

/// Minimal SVG path parser for the bundled icon data (M L H V Q A C Z, absolute and relative).
enum SVGPath {
    static func parse(_ data: String) -> Path {
        var path = Path()
        var scanner = Tokens(data)
        var command: Character = "M"
        var current = CGPoint.zero, start = CGPoint.zero
        while let next = scanner.nextCommandOrNumber() {
            if case .command(let c) = next { command = c } else { scanner.pushBack() }
            let relative = command.isLowercase
            let base = relative ? current : .zero
            switch command.uppercased().first! {
            case "M":
                current = CGPoint(x: base.x + scanner.number(), y: base.y + scanner.number())
                start = current
                path.move(to: current)
                command = relative ? "l" : "L"
            case "L":
                current = CGPoint(x: base.x + scanner.number(), y: base.y + scanner.number())
                path.addLine(to: current)
            case "H":
                current.x = (relative ? current.x : 0) + scanner.number()
                path.addLine(to: current)
            case "V":
                current.y = (relative ? current.y : 0) + scanner.number()
                path.addLine(to: current)
            case "Q":
                let control = CGPoint(x: base.x + scanner.number(), y: base.y + scanner.number())
                current = CGPoint(x: base.x + scanner.number(), y: base.y + scanner.number())
                path.addQuadCurve(to: current, control: control)
            case "C":
                let c1 = CGPoint(x: base.x + scanner.number(), y: base.y + scanner.number())
                let c2 = CGPoint(x: base.x + scanner.number(), y: base.y + scanner.number())
                current = CGPoint(x: base.x + scanner.number(), y: base.y + scanner.number())
                path.addCurve(to: current, control1: c1, control2: c2)
            case "A":
                let rx = scanner.number(), ry = scanner.number(), rotation = scanner.number()
                let large = scanner.flag(), sweep = scanner.flag()
                let end = CGPoint(x: base.x + scanner.number(), y: base.y + scanner.number())
                addArc(&path, from: current, to: end, rx: rx, ry: ry, rotation: rotation, large: large, sweep: sweep)
                current = end
            case "Z":
                path.closeSubpath()
                current = start
            default:
                return path
            }
        }
        return path
    }

    /// SVG endpoint-to-center arc conversion (SVG 1.1, appendix F.6.5), approximated by cubic segments.
    private static func addArc(_ path: inout Path, from p0: CGPoint, to p1: CGPoint, rx rx0: CGFloat, ry ry0: CGFloat,
                               rotation: CGFloat, large: Bool, sweep: Bool) {
        guard p0 != p1 else { return }
        var rx = abs(rx0), ry = abs(ry0)
        guard rx > 0, ry > 0 else { path.addLine(to: p1); return }
        let phi = rotation * .pi / 180, cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy, y1 = -sinPhi * dx + cosPhi * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }
        let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var factor = sqrt(max(0, numerator / denominator))
        if large == sweep { factor = -factor }
        let cx1 = factor * rx * y1 / ry, cy1 = -factor * ry * x1 / rx
        let cx = cosPhi * cx1 - sinPhi * cy1 + (p0.x + p1.x) / 2
        let cy = sinPhi * cx1 + cosPhi * cy1 + (p0.y + p1.y) / 2
        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let sign: CGFloat = ux * vy - uy * vx < 0 ? -1 : 1
            let dot = (ux * vx + uy * vy) / (hypot(ux, uy) * hypot(vx, vy))
            return sign * acos(min(1, max(-1, dot)))
        }
        let theta = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep, delta > 0 { delta -= 2 * .pi } else if sweep, delta < 0 { delta += 2 * .pi }
        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(segments)
        let k = 4 / 3 * tan(step / 4)
        func point(_ t: CGFloat) -> CGPoint {
            CGPoint(x: cx + rx * cos(t) * cosPhi - ry * sin(t) * sinPhi, y: cy + rx * cos(t) * sinPhi + ry * sin(t) * cosPhi)
        }
        func derivative(_ t: CGFloat) -> CGPoint {
            CGPoint(x: -rx * sin(t) * cosPhi - ry * cos(t) * sinPhi, y: -rx * sin(t) * sinPhi + ry * cos(t) * cosPhi)
        }
        var t = theta
        for _ in 0..<segments {
            let a = point(t), b = point(t + step), da = derivative(t), db = derivative(t + step)
            path.addCurve(to: b, control1: CGPoint(x: a.x + k * da.x, y: a.y + k * da.y),
                          control2: CGPoint(x: b.x - k * db.x, y: b.y - k * db.y))
            t += step
        }
    }

    private struct Tokens {
        enum Token { case command(Character), number(CGFloat) }
        private let chars: [Character]
        private var index = 0
        private var previous = 0

        init(_ text: String) { chars = Array(text) }

        private mutating func skipSeparators() {
            while index < chars.count, chars[index] == " " || chars[index] == "," { index += 1 }
        }

        mutating func pushBack() { index = previous }

        mutating func nextCommandOrNumber() -> Token? {
            skipSeparators()
            previous = index
            guard index < chars.count else { return nil }
            let c = chars[index]
            if c.isLetter { index += 1; return .command(c) }
            return .number(number())
        }

        /// Arc flags may be written without separators, as in `a1 1 0 0 0`.
        mutating func flag() -> Bool {
            skipSeparators()
            guard index < chars.count else { return false }
            defer { index += 1 }
            return chars[index] == "1"
        }

        mutating func number() -> CGFloat {
            skipSeparators()
            let begin = index
            if index < chars.count, chars[index] == "-" || chars[index] == "+" { index += 1 }
            var seenDot = false, seenExponent = false
            while index < chars.count {
                let c = chars[index]
                if c.isNumber { index += 1 }
                else if c == ".", !seenDot, !seenExponent { seenDot = true; index += 1 }
                else if c == "e" || c == "E", !seenExponent {
                    seenExponent = true; index += 1
                    if index < chars.count, chars[index] == "-" || chars[index] == "+" { index += 1 }
                } else { break }
            }
            return CGFloat(Double(String(chars[begin..<index])) ?? 0)
        }
    }
}
