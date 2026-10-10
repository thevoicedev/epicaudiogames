// The Material pieces GameScreen.kt, HomeScreen.kt, Components.kt, StoreSheet.kt and MainActivity.kt use: icons
// (material-icons), the spinner, the download bar and the press ripple, drawn as Compose's material3 draws them.

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

    // The redesign's icons (docs/DESIGN.md), each with Android's: the game's circle badges, the cards, the store's
    // states. Their paths are material-icons' own (1.7.8), read from its classes.

    /// Icons.Outlined.Mic: the talking circle's badge while it waits for the player to talk.
    static let micOutlined = MaterialIcon(path: SVGPath(
        "M12,14c1.66,0 3,-1.34 3,-3V5c0,-1.66 -1.34,-3 -3,-3S9,3.34 9,5v6C9,12.66 10.34,14 12,14zM17,11c0,2.76 "
            + "-2.24,5 -5,5s-5,-2.24 -5,-5H5c0,3.53 2.61,6.43 6,6.92V21h2v-3.08c3.39,-0.49 6,-3.39 6,-6.92H17z"))
    /// Icons.Outlined.MicOff: the mic refused, or no speech recognition (the circle's badge and the mic button).
    static let micOffOutlined = MaterialIcon(path: SVGPath(
        "M10.8,4.9c0,-0.66 0.54,-1.2 1.2,-1.2s1.2,0.54 1.2,1.2l-0.01,3.91L15,10.6V5c0,-1.66 -1.34,-3 -3,-3c-1.54,0 "
            + "-2.79,1.16 -2.96,2.65l1.76,1.76V4.9zM19,11h-1.7c0,0.58 -0.1,1.13 -0.27,1.64l1.27,1.27c0.44,-0.88 "
            + "0.7,-1.87 0.7,-2.91zM4.41,2.86L3,4.27l6,6V11c0,1.66 1.34,3 3,3c0.23,0 0.44,-0.03 0.65,-0.08l1.66,1.66c"
            + "-0.71,0.33 -1.5,0.52 -2.31,0.52c-2.76,0 -5.3,-2.1 -5.3,-5.1H5c0,3.41 2.72,6.23 6,6.72V21h2v-3.28c0.91,"
            + "-0.13 1.77,-0.45 2.55,-0.9l4.2,4.2l1.41,-1.41L4.41,2.86z"))
    /// Icons.Default.SkipNext: the circle's badge while the game speaks.
    static let skipNext = MaterialIcon(path: SVGPath("M6,18l8.5,-6L6,6v12zM16,6v12h2V6h-2z"))
    /// Icons.Default.Stop: the mic button while it listens.
    static let stop = MaterialIcon(path: SVGPath("M6,6h12v12H6z"))
    /// Icons.Outlined.HourglassEmpty: the circle's badge before the question.
    static let hourglassEmpty = MaterialIcon(path: SVGPath(
        "M6,2v6h0.01L6,8.01L10,12l-4,4l0.01,0.01L6,16.01L6,22h12v-5.99h-0.01L18,16l-4,-4l4,-3.99l-0.01,-0.01L18,8L18,2"
            + "L6,2zM16,16.5L16,20L8,20v-3.5l4,-4l4,4zM12,11.5l-4,-4L8,4h8v3.5l-4,4z"))
    /// Icons.Default.CheckCircle: installed, all packs installed, bought, success.
    static let checkCircle = MaterialIcon(path: SVGPath(
        "M12,2C6.48,2 2,6.48 2,12s4.48,10 10,10 10,-4.48 10,-10S17.52,2 12,2zM10,17l-5,-5 1.41,-1.41L10,14.17l7.59,"
            + "-7.59L19,8l-9,9z"))
    /// Icons.Outlined.ErrorOutline: a failure, with its words.
    static let errorOutline = MaterialIcon(path: SVGPath(
        "M11,15h2v2h-2v-2zM11,7h2v6h-2L11,7zM11.99,2C6.47,2 2,6.48 2,12s4.47,10 9.99,10C17.52,22 22,17.52 22,12"
            + "S17.52,2 11.99,2zM12,20c-4.42,0 -8,-3.58 -8,-8s3.58,-8 8,-8 8,3.58 8,8 -3.58,8 -8,8z"))
    /// Icons.Outlined.Schedule: a payment pending, a download waiting.
    static let schedule = MaterialIcon(path: SVGPath(
        "M11.99,2C6.47,2 2,6.48 2,12s4.47,10 9.99,10C17.52,22 22,17.52 22,12S17.52,2 11.99,2zM12,20c-4.42,0 -8,-3.58 "
            + "-8,-8s3.58,-8 8,-8 8,3.58 8,8 -3.58,8 -8,8zM12.5,7L11,7v6l5.25,3.15 0.75,-1.23 -4.5,-2.67z"))
    /// Icons.Default.Download: a pack bought but not on this phone.
    static let download = MaterialIcon(path: SVGPath("M5,20h14v-2H5V20zM19,9h-4V3H9v6H5l7,7L19,9z"))
    /// Icons.Outlined.ShoppingBag: a pack's "Bought" (PackRows.kt's).
    static let shoppingBagOutlined = MaterialIcon(path: SVGPath(
        "M18,6h-2c0,-2.21 -1.79,-4 -4,-4S8,3.79 8,6H6C4.9,6 4,6.9 4,8v12c0,1.1 0.9,2 2,2h12c1.1,0 2,-0.9 2,-2V8C20,6.9 "
            + "19.1,6 18,6zM12,4c1.1,0 2,0.9 2,2h-4C10,4.9 10.9,4 12,4zM18,20H6V8h2v2c0,0.55 0.45,1 1,1s1,-0.45 1,-1V8h4v2"
            + "c0,0.55 0.45,1 1,1s1,-0.45 1,-1V8h2V20z"))
    /// Icons.Default.Add: a game card's "Get <pack>".
    static let add = MaterialIcon(path: SVGPath("M19,13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z"))
    /// Icons.Default.Bookmark: a game card's "In progress".
    static let bookmark = MaterialIcon(path: SVGPath(
        "M17,3H7c-1.1,0 -1.99,0.9 -1.99,2L5,21l7,-3 7,3V5c0,-1.1 -0.9,-2 -2,-2z"))
    /// Icons.AutoMirrored.Filled.KeyboardArrowRight: a game card's "Play ›".
    static let keyboardArrowRight = MaterialIcon(path: SVGPath(
        "M8.59,16.59L13.17,12 8.59,7.41 10,6l6,6 -6,6 -1.41,-1.41z"))
    /// Icons.AutoMirrored.Filled.OpenInNew: a link that opens the browser.
    static let openInNew = MaterialIcon(path: SVGPath(
        "M19,19H5V5h7V3H5c-1.11,0 -2,0.9 -2,2v14c0,1.1 0.89,2 2,2h14c1.1,0 2,-0.9 2,-2v-7h-2v7zM14,3v2h3.59l-9.83,"
            + "9.83 1.41,1.41L19,6.41V10h2V3h-7z"))
    /// Icons.Default.Pause: Listen while it reads (HelpScreen.kt's ListenButton).
    static let pause = MaterialIcon(path: SVGPath("M6,19h4L10,5L6,5v14zM14,5v14h4L18,5h-4z"))
    /// Icons.AutoMirrored.Filled.ArrowForward: onboarding's Next.
    static let arrowForward = MaterialIcon(path: SVGPath(
        "M12,4l-1.41,1.41L16.17,11H4v2h12.17l-5.58,5.59L12,20l8,-8z"))
}

/// An icon at [size] points in [color], white unless it says (Compose's Icon with its tint). Only a picture: what it
/// means is in the words beside it, or the button's name.
struct IconView: View {
    let icon: MaterialIcon
    var size: CGFloat = 24
    var color: Color = .white

    var body: some View {
        icon.fill(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
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
 * The download bar (docs/DESIGN.md's progress tokens; StoreSheet.kt's Downloading): 8 pt tall, the progress in
 * progressFill over progressTrack, square-ended, with a 2 pt edge where the track is the background's colour (the
 * contrast palettes). VoiceOver reads it as "Downloading" and its percent.
 */
struct LinearProgress: View {
    let progress: Double
    @Environment(\.epicColors) private var c

    private static let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                c.progressTrack
                c.progressFill
                    .frame(width: g.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 8)
        .clipShape(Self.shape)
        .overlay {
            if let edge = c.progressEdge { Self.shape.strokeBorder(edge, lineWidth: 2) }
        }
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
