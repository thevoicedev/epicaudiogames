// Draws the app icon from android/app/src/main/res/drawable/ic_launcher_foreground.xml (Android's adaptive icon).
//
// The foreground's 108x108 viewport is drawn on the launcher background colour (values/colors.xml), cropped to the
// middle 72x72 that every launcher shows (viewport 18...90), into an opaque square PNG (iOS rounds the corners).
// It reads the vector's <group> transforms and <path>s: fill and stroke colours, stroke width and cap, and path data
// with the commands M L H V C S Q T A Z (and their lower-case relative forms).
//
// Usage (from the repo root): swift ios/scripts/render_icon.swift [out.png] [size]
// Default: ios/EpicAudioGames/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png at 1024 px.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()
let res = repo.appendingPathComponent("android/app/src/main/res")
let args = CommandLine.arguments
let out = args.count > 1 ? URL(fileURLWithPath: args[1])
    : repo.appendingPathComponent("ios/EpicAudioGames/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let size = args.count > 2 ? Int(args[2])! : 1024
let crop = (origin: 18.0, side: 72.0)

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("render_icon: " + message + "\n").data(using: .utf8)!)
    exit(1)
}

/// An Android colour: #RGB, #ARGB, #RRGGBB or #AARRGGBB.
func colour(_ text: String) -> CGColor? {
    var hex = text.trimmingCharacters(in: .whitespaces)
    guard hex.hasPrefix("#") else { return nil }
    hex.removeFirst()
    if hex.count <= 4 { hex = String(hex.flatMap { [$0, $0] }) }
    if hex.count == 6 { hex = "FF" + hex }
    guard hex.count == 8, let v = UInt32(hex, radix: 16) else { return nil }
    let c = { (shift: UInt32) in CGFloat((v >> shift) & 0xFF) / 255 }
    let a = c(24)
    return a == 0 ? nil : CGColor(srgbRed: c(16), green: c(8), blue: c(0), alpha: a)
}

/// The launcher background, from values/colors.xml.
func background() -> CGColor {
    guard let xml = try? String(contentsOf: res.appendingPathComponent("values/colors.xml"), encoding: .utf8),
          let range = xml.range(of: #"<color name="ic_launcher_background">([^<]+)</color>"#, options: .regularExpression)
    else { fail("no ic_launcher_background in values/colors.xml") }
    let tag = String(xml[range])
    let value = tag.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    guard let c = colour(value) else { fail("can't read the colour \(value)") }
    return c
}

// ----- Path data -----

struct PathData {
    let path = CGMutablePath()
    var chars: [Character]
    var i = 0
    var current = CGPoint.zero
    var start = CGPoint.zero
    var lastControl: CGPoint?          // for S and T
    var lastCommand: Character = " "

    init(_ text: String) { chars = Array(text) }

    mutating func skipSeparators() {
        while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i] == "\n" || chars[i] == "\t" || chars[i] == "\r" { i += 1 }
    }

    mutating func number() -> CGFloat {
        skipSeparators()
        var s = ""
        if i < chars.count, chars[i] == "-" || chars[i] == "+" { s.append(chars[i]); i += 1 }
        var seenDot = false, seenExp = false
        while i < chars.count {
            let c = chars[i]
            if c.isNumber { s.append(c) } else if c == ".", !seenDot, !seenExp { seenDot = true; s.append(c) }
            else if c == "e" || c == "E", !seenExp { seenExp = true; s.append(c)
                if i + 1 < chars.count, chars[i + 1] == "-" || chars[i + 1] == "+" { i += 1; s.append(chars[i]) }
            } else { break }
            i += 1
        }
        guard let d = Double(s) else { fail("bad number at \(i) in the path data") }
        return CGFloat(d)
    }

    /// An arc flag: a single 0 or 1, which may run into the next number.
    mutating func flag() -> Bool {
        skipSeparators()
        guard i < chars.count, chars[i] == "0" || chars[i] == "1" else { fail("bad arc flag at \(i)") }
        defer { i += 1 }
        return chars[i] == "1"
    }

    mutating func hasNumber() -> Bool {
        skipSeparators()
        guard i < chars.count else { return false }
        let c = chars[i]
        return c.isNumber || c == "-" || c == "+" || c == "."
    }

    mutating func parse() -> CGPath {
        while true {
            skipSeparators()
            guard i < chars.count else { break }
            var command = chars[i]
            if command.isLetter {
                i += 1
            } else {
                // A number with no command repeats the last one (a moveto's extra pairs are linetos).
                command = lastCommand == "M" ? "L" : lastCommand == "m" ? "l" : lastCommand
            }
            run(command)
            lastCommand = command
        }
        return path
    }

    mutating func point(_ relative: Bool) -> CGPoint {
        let x = number(), y = number()
        return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
    }

    mutating func run(_ command: Character) {
        let rel = command.isLowercase
        switch command.uppercased() {
        case "M":
            current = point(rel); start = current
            path.move(to: current)
            lastControl = nil
        case "L":
            current = point(rel); path.addLine(to: current); lastControl = nil
        case "H":
            let x = number(); current.x = rel ? current.x + x : x; path.addLine(to: current); lastControl = nil
        case "V":
            let y = number(); current.y = rel ? current.y + y : y; path.addLine(to: current); lastControl = nil
        case "C":
            let c1 = point(rel), c2 = point(rel), end = point(rel)
            path.addCurve(to: end, control1: c1, control2: c2)
            lastControl = c2; current = end
        case "S":
            let c1 = reflected(), c2 = point(rel), end = point(rel)
            path.addCurve(to: end, control1: c1, control2: c2)
            lastControl = c2; current = end
        case "Q":
            let c = point(rel), end = point(rel)
            path.addQuadCurve(to: end, control: c)
            lastControl = c; current = end
        case "T":
            let c = reflected(), end = point(rel)
            path.addQuadCurve(to: end, control: c)
            lastControl = c; current = end
        case "A":
            let rx = number(), ry = number(), rotation = number()
            let large = flag(), sweep = flag()
            let end = point(rel)
            arc(to: end, rx: rx, ry: ry, degrees: rotation, large: large, sweep: sweep)
            current = end; lastControl = nil
        case "Z":
            path.closeSubpath(); current = start; lastControl = nil
        default:
            fail("unknown path command \(command)")
        }
    }

    func reflected() -> CGPoint {
        guard let c = lastControl else { return current }
        return CGPoint(x: 2 * current.x - c.x, y: 2 * current.y - c.y)
    }

    /// An SVG elliptical arc, as cubic Béziers of at most 90° each (SVG 1.1, appendix F.6.5).
    func arc(to end: CGPoint, rx rx0: CGFloat, ry ry0: CGFloat, degrees: CGFloat, large: Bool, sweep: Bool) {
        let p0 = current
        if p0 == end { return }
        var rx = abs(rx0), ry = abs(ry0)
        if rx == 0 || ry == 0 { path.addLine(to: end); return }
        let phi = degrees * .pi / 180, cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p0.x - end.x) / 2, dy = (p0.y - end.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy, y1 = -sinPhi * dx + cosPhi * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 { rx *= lambda.squareRoot(); ry *= lambda.squareRoot() }
        let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var k = (max(0, num) / den).squareRoot()
        if large == sweep { k = -k }
        let cx1 = k * rx * y1 / ry, cy1 = -k * ry * x1 / rx
        let cx = cosPhi * cx1 - sinPhi * cy1 + (p0.x + end.x) / 2
        let cy = sinPhi * cx1 + cosPhi * cy1 + (p0.y + end.y) / 2
        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            return a
        }
        let theta1 = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }
        let segments = max(1, Int((abs(delta) / (.pi / 2)).rounded(.up)))
        let step = delta / CGFloat(segments)
        let t = 4.0 / 3.0 * tan(step / 4)
        func on(_ a: CGFloat) -> CGPoint {
            let x = rx * cos(a), y = ry * sin(a)
            return CGPoint(x: cx + cosPhi * x - sinPhi * y, y: cy + sinPhi * x + cosPhi * y)
        }
        func tangent(_ a: CGFloat) -> CGPoint {
            let x = -rx * sin(a), y = ry * cos(a)
            return CGPoint(x: cosPhi * x - sinPhi * y, y: sinPhi * x + cosPhi * y)
        }
        var a = theta1
        for _ in 0..<segments {
            let b = a + step
            let pa = on(a), pb = on(b), ta = tangent(a), tb = tangent(b)
            path.addCurve(to: pb, control1: CGPoint(x: pa.x + t * ta.x, y: pa.y + t * ta.y),
                          control2: CGPoint(x: pb.x - t * tb.x, y: pb.y - t * tb.y))
            a = b
        }
    }
}

// ----- The vector -----

final class Vector: NSObject, XMLParserDelegate {
    let context: CGContext
    var saved = 0

    init(context: CGContext) { self.context = context }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        func value(_ key: String) -> String? { attributes["android:" + key] ?? attributes[key] }
        func number(_ key: String, _ otherwise: CGFloat) -> CGFloat { value(key).flatMap { Double($0) }.map { CGFloat($0) } ?? otherwise }
        switch name {
        case "group":
            context.saveGState(); saved += 1
            let px = number("pivotX", 0), py = number("pivotY", 0)
            context.translateBy(x: px + number("translateX", 0), y: py + number("translateY", 0))
            context.rotate(by: number("rotation", 0) * .pi / 180)
            context.scaleBy(x: number("scaleX", 1), y: number("scaleY", 1))
            context.translateBy(x: -px, y: -py)
        case "path":
            guard let data = value("pathData") else { return }
            var parser = PathData(data)
            let path = parser.parse()
            if let fill = value("fillColor").flatMap(colour) {
                context.addPath(path)
                context.setFillColor(fill)
                context.fillPath(using: value("fillType") == "evenOdd" ? .evenOdd : .winding)
            }
            if let stroke = value("strokeColor").flatMap(colour), number("strokeWidth", 0) > 0 {
                context.addPath(path)
                context.setStrokeColor(stroke)
                context.setLineWidth(number("strokeWidth", 0))
                context.setLineCap(["round": .round, "square": .square][value("strokeLineCap") ?? ""] ?? .butt)
                context.setLineJoin(["round": .round, "bevel": .bevel][value("strokeLineJoin") ?? ""] ?? .miter)
                context.setMiterLimit(number("strokeMiterLimit", 4))
                context.strokePath()
            }
        case "clip-path":
            fail("clip-path isn't supported")
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "group" { context.restoreGState(); saved -= 1 }
    }
}

let source = res.appendingPathComponent("drawable/ic_launcher_foreground.xml")
guard let xml = XMLParser(contentsOf: source) else { fail("can't open \(source.path)") }
guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
else { fail("no bitmap context") }
context.setShouldAntialias(true)
context.interpolationQuality = .high
context.setFillColor(background())
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
// Android draws y downwards: flip, then fit the visible 72x72 of the viewport to the image.
context.translateBy(x: 0, y: CGFloat(size))
context.scaleBy(x: 1, y: -1)
context.scaleBy(x: CGFloat(size) / crop.side, y: CGFloat(size) / crop.side)
context.translateBy(x: -crop.origin, y: -crop.origin)

let vector = Vector(context: context)
xml.delegate = vector
guard xml.parse() else { fail("can't read \(source.path): \(xml.parserError.map { "\($0)" } ?? "?")") }

try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
guard let image = context.makeImage(),
      let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fail("can't write \(out.path)") }
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fail("can't write \(out.path)") }
print("\(out.path): \(size)x\(size)")
