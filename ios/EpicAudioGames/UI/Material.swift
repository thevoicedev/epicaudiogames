// The Material pieces GameScreen.kt, Theme.kt, StoreSheet.kt and MainActivity.kt use: icons (material-icons), the
// spinner, the progress bar and the press ripple, drawn as Compose's material3 1.3 draws them.

import SwiftUI

/**
 * A Material icon: its path on the 24 × 24 grid of Compose's Icons, scaled to the frame it's given (Compose's Icon
 * is 24 dp unless sized). Filled with the foreground style.
 */
nonisolated struct MaterialIcon: Shape {
    let path: SVGPath

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let x = rect.minX + (rect.width - 24 * scale) / 2
        let y = rect.minY + (rect.height - 24 * scale) / 2
        return path.path.applying(CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: x, ty: y))
    }

    /// Icons.Default.PlayArrow.
    static let playArrow = MaterialIcon(path: SVGPath("M8,5v14l11,-7z"))
    /// Icons.AutoMirrored.Filled.Send.
    static let send = MaterialIcon(path: SVGPath("M2.01,21L23,12 2.01,3 2,10l15,2 -15,2z"))
    /// Icons.Default.MoreVert.
    static let moreVert = MaterialIcon(path: SVGPath(
        "M12,8c1.1,0 2,-0.9 2,-2s-0.9,-2 -2,-2 -2,0.9 -2,2 0.9,2 2,2zM12,10c-1.1,0 -2,0.9 -2,2s0.9,2 2,2 2,-0.9 2,-2 "
            + "-0.9,-2 -2,-2zM12,16c-1.1,0 -2,0.9 -2,2s0.9,2 2,2 2,-0.9 2,-2 -0.9,-2 -2,-2z"))
    /// Icons.AutoMirrored.Filled.ArrowBack.
    static let arrowBack = MaterialIcon(path: SVGPath(
        "M20,11H7.83l5.59,-5.59L12,4l-8,8 8,8 1.41,-1.41L7.83,13H20v-2z"))
    /// Icons.Default.Mic.
    static let mic = MaterialIcon(path: SVGPath(
        "M12,14c1.66,0 2.99,-1.34 2.99,-3L15,5c0,-1.66 -1.34,-3 -3,-3S9,3.34 9,5v6c0,1.66 1.34,3 3,3zM17.3,11c0,3 "
            + "-2.54,5.1 -5.3,5.1S6.7,14 6.7,11H5c0,3.41 2.72,6.23 6,6.72V21h2v-3.28c3.28,-0.48 6,-3.3 6,-6.72h-1.7z"))
    /// Icons.Default.MicOff.
    static let micOff = MaterialIcon(path: SVGPath(
        "M19,11h-1.7c0,0.74 -0.16,1.43 -0.43,2.05l1.23,1.23c0.56,-0.98 0.9,-2.09 0.9,-3.28zM14.98,11.17c0,-0.06 "
            + "0.02,-0.11 0.02,-0.17V5c0,-1.66 -1.34,-3 -3,-3S9,3.34 9,5v0.18l5.98,5.99zM4.27,3L3,4.27l6.01,6.01V11c0,"
            + "1.66 1.33,3 2.99,3 0.22,0 0.44,-0.03 0.65,-0.08l1.66,1.66c-0.71,0.33 -1.5,0.52 -2.31,0.52 -2.76,0 "
            + "-5.3,-2.1 -5.3,-5.1H5c0,3.41 2.72,6.23 6,6.72V21h2v-3.28c0.91,-0.13 1.77,-0.45 2.54,-0.9L19.73,21 "
            + "21,19.73 4.27,3z"))
}

/// An icon at [size] points in [color], white unless it says (Compose's Icon with its tint).
struct IconView: View {
    let icon: MaterialIcon
    var size: CGFloat = 24
    var color: Color = .white

    var body: some View {
        icon.fill(color).frame(width: size, height: size)
    }
}

/**
 * Android's vector path data (the SVG path syntax): moves, lines, cubic curves (and their smooth form) and closes,
 * absolute and relative, with a command repeated by giving more numbers. Enough for the material icons.
 */
nonisolated struct SVGPath: Sendable {
    let path: Path

    init(_ data: String) {
        var p = Path()
        var numbers: [CGFloat] = []
        var command: Character = "M"
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastControl: CGPoint?

        func flush() {
            var i = 0
            let relative = command.isLowercase
            func point(_ k: Int) -> CGPoint {
                let pt = CGPoint(x: numbers[i + k], y: numbers[i + k + 1])
                return relative ? CGPoint(x: current.x + pt.x, y: current.y + pt.y) : pt
            }
            let lower = Character(command.lowercased())
            if lower == "z" {
                p.closeSubpath()
                current = start
                lastControl = nil
                return
            }
            let arity: Int = switch lower {
            case "m", "l": 2
            case "h", "v": 1
            case "c": 6
            case "s": 4
            default: 0
            }
            guard arity > 0 else { return }
            var first = true
            while i + arity <= numbers.count {
                switch lower {
                case "m":
                    let pt = point(0)
                    if first {
                        p.move(to: pt)
                        start = pt
                    } else {
                        p.addLine(to: pt)       // more pairs after a move are lines
                    }
                    current = pt
                    lastControl = nil
                case "l":
                    current = point(0)
                    p.addLine(to: current)
                    lastControl = nil
                case "h":
                    current = CGPoint(x: relative ? current.x + numbers[i] : numbers[i], y: current.y)
                    p.addLine(to: current)
                    lastControl = nil
                case "v":
                    current = CGPoint(x: current.x, y: relative ? current.y + numbers[i] : numbers[i])
                    p.addLine(to: current)
                    lastControl = nil
                case "c":
                    let c1 = point(0)
                    let c2 = point(2)
                    let end = point(4)
                    p.addCurve(to: end, control1: c1, control2: c2)
                    lastControl = c2
                    current = end
                case "s":
                    let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                    let c2 = point(0)
                    let end = point(2)
                    p.addCurve(to: end, control1: c1, control2: c2)
                    lastControl = c2
                    current = end
                default:
                    break
                }
                first = false
                i += arity
            }
        }

        var token = ""
        func endNumber() {
            if !token.isEmpty, let v = Double(token) { numbers.append(CGFloat(v)) }
            token = ""
        }
        for ch in data {
            if ch.isLetter && ch != "e" && ch != "E" {
                endNumber()
                flush()
                numbers = []
                command = ch
            } else if ch == "," || ch == " " {
                endNumber()
            } else if ch == "-" && !token.isEmpty && token.last != "e" && token.last != "E" {
                endNumber()
                token = "-"
            } else if ch == "." && token.contains(".") {
                endNumber()
                token = "."
            } else {
                token.append(ch)
            }
        }
        endNumber()
        flush()
        path = p
    }
}

/**
 * Material 3's indeterminate CircularProgressIndicator: a 40 pt ring drawn 4 pt wide with square ends, whose arc
 * grows and shrinks while it turns (head and tail 666 ms each, eased; the base turning 286° each 1332 ms, plus 216°
 * more each cycle).
 */
struct RingSpinner: View {
    var color: Color = .white
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { context in
            let ms = max(context.date.timeIntervalSince(start), 0) * 1000
            let arc = Self.arc(at: ms)
            Circle()
                .inset(by: 2)
                .trim(from: 0, to: arc.sweep / 360)
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .square))
                .rotationEffect(.degrees(arc.start))
        }
        .frame(width: 40, height: 40)
        .accessibilityLabel("Loading")
    }

    /// Where the arc starts (degrees clockwise from 3 o'clock) and how far it goes, [ms] into the animation.
    static func arc(at ms: Double) -> (start: Double, sweep: Double) {
        let cycle = 1332.0
        let half = 666.0
        let t = ms.truncatingRemainder(dividingBy: cycle)
        let rotation = Double(Int(ms.truncatingRemainder(dividingBy: cycle * 5) / cycle))
        let base = 286 * t / cycle
        let head = t < half ? 290 * Pulse.ease(t / half) : 290
        let tail = t < half ? 0 : 290 * Pulse.ease((t - half) / half)
        let sweep = max(abs(head - tail), 0.1)
        // The square end reaches back half the stroke width: moved forward by as much (4 pt on a 20 pt radius).
        let capOffset = 180 / Double.pi * (4.0 / 20) / 2
        let offset = -90 + (rotation * 216).truncatingRemainder(dividingBy: 360) + base
        return (tail + offset + capOffset, sweep)
    }
}

/**
 * Material 3's LinearProgressIndicator (1.3): a 4 pt bar, round-ended, the progress in [color], then a 4 pt gap, the
 * rest of the track in the colour scheme's secondaryContainer, and a 4 pt stop dot at its end.
 */
struct LinearProgress: View {
    let progress: Double
    var color: Color = Palette.yes
    var track = Color(hex: 0xE8DEF8)

    var body: some View {
        Canvas { context, size in
            let h = size.height
            let w = size.width
            let r = h / 2
            let done = w * min(max(progress, 0), 1)
            let gap: CGFloat = 4
            func bar(_ from: CGFloat, _ to: CGFloat, _ colour: Color) {
                guard to - from > 0 else { return }
                context.fill(Path(roundedRect: CGRect(x: from, y: 0, width: to - from, height: h), cornerRadius: r),
                             with: .color(colour))
            }
            let trackStart = done > 0 ? done + gap : 0
            bar(trackStart, w, track)
            bar(0, done, color)
            if done < w - h {
                context.fill(Path(ellipseIn: CGRect(x: w - h, y: 0, width: h, height: h)), with: .color(color))
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityLabel("Downloading")
        .accessibilityValue("\(Int((progress * 100).rounded())) percent")
    }
}

/// Compose's ripple, as a pressed state: [shape] darkened by black at 10% while held (material3's pressed alpha).
struct RippleStyle<S: Shape>: ButtonStyle {
    let shape: S

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                shape.fill(Color.black.opacity(configuration.isPressed ? 0.1 : 0))
                    .allowsHitTesting(false)
            }
    }
}
