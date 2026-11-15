import SwiftUI

/// Phosphor regular, bundled as SVG and drawn as a template so it takes the surrounding colour.
struct PhosphorIcon: View {
    var name: String
    var size: CGFloat = 21

    var body: some View {
        PhosphorShape(name: name)
            .fill(Color.primary, style: FillStyle(eoFill: false))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct PhosphorShape: Shape {
    var name: String

    func path(in rect: CGRect) -> Path {
        let drawing = SVGPath.parse(PhosphorLibrary.commands(named: name))
        let scale = min(rect.width, rect.height) / 256
        return drawing.applying(CGAffineTransform(scaleX: scale, y: scale))
    }
}

enum PhosphorLibrary {
    static func commands(named name: String) -> String {
        if let path = cached[name], !path.isEmpty { return path }
        return ""
    }

    /// Inlined from the bundled SVGs so a missing resource lookup still draws.
    static let cached: [String: String] = PhosphorData.paths
}

enum SVGPath {
    static func parse(_ d: String) -> Path {
        var path = Path()
        var index = d.startIndex
        var command: Character = "M"
        var current = CGPoint.zero
        var start = CGPoint.zero
        var cubicControl = CGPoint.zero

        func skip() {
            while index < d.endIndex, d[index] == "," || d[index].isWhitespace { index = d.index(after: index) }
        }
        func number() -> CGFloat? {
            skip()
            guard index < d.endIndex else { return nil }
            let begin = index
            if d[index] == "+" || d[index] == "-" { index = d.index(after: index) }
            var saw = false
            while index < d.endIndex, d[index].isNumber || d[index] == "." {
                saw = true
                index = d.index(after: index)
            }
            if index < d.endIndex, (d[index] == "e" || d[index] == "E") {
                index = d.index(after: index)
                if index < d.endIndex, d[index] == "+" || d[index] == "-" { index = d.index(after: index) }
                while index < d.endIndex, d[index].isNumber { index = d.index(after: index) }
            }
            guard saw, let value = Double(d[begin..<index]) else { return nil }
            return CGFloat(value)
        }
        func point(relative: Bool) -> CGPoint? {
            guard let x = number(), let y = number() else { return nil }
            return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }
        func flag() -> Bool {
            skip()
            guard index < d.endIndex else { return false }
            let value = d[index] == "1"
            index = d.index(after: index)
            return value
        }

        while index < d.endIndex {
            skip()
            if index >= d.endIndex { break }
            if d[index].isLetter {
                command = d[index]
                index = d.index(after: index)
            }
            switch command {
            case "M", "m":
                let relative = command == "m"
                guard let next = point(relative: relative) else { return path }
                path.move(to: next)
                current = next
                start = next
                command = relative ? "l" : "L"
            case "L", "l":
                guard let next = point(relative: command == "l") else { return path }
                path.addLine(to: next)
                current = next
            case "H", "h":
                guard let x = number() else { return path }
                current.x = command == "h" ? current.x + x : x
                path.addLine(to: current)
            case "V", "v":
                guard let y = number() else { return path }
                current.y = command == "v" ? current.y + y : y
                path.addLine(to: current)
            case "C", "c":
                let relative = command == "c"
                guard let c1 = point(relative: relative), let c2 = point(relative: relative), let end = point(relative: relative) else { return path }
                path.addCurve(to: end, control1: c1, control2: c2)
                cubicControl = c2
                current = end
            case "S", "s":
                let relative = command == "s"
                let c1 = CGPoint(x: 2 * current.x - cubicControl.x, y: 2 * current.y - cubicControl.y)
                guard let c2 = point(relative: relative), let end = point(relative: relative) else { return path }
                path.addCurve(to: end, control1: c1, control2: c2)
                cubicControl = c2
                current = end
            case "A", "a":
                guard let rx = number(), let ry = number(), let angle = number() else { return path }
                let large = flag()
                let sweep = flag()
                guard let end = point(relative: command == "a") else { return path }
                addArc(path: &path, from: current, rx: rx, ry: ry, angle: angle, large: large, sweep: sweep, to: end)
                current = end
            case "Z", "z":
                path.closeSubpath()
                current = start
            default:
                return path
            }
        }
        return path
    }

    private static func addArc(path: inout Path, from p1: CGPoint, rx rxIn: CGFloat, ry ryIn: CGFloat, angle: CGFloat, large: Bool, sweep: Bool, to p2: CGPoint) {
        var rx = abs(rxIn)
        var ry = abs(ryIn)
        if rx == 0 || ry == 0 || p1 == p2 {
            path.addLine(to: p2)
            return
        }
        let phi = angle * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)
        let dx = (p1.x - p2.x) / 2
        let dy = (p1.y - p2.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy
        var rxsq = rx * rx
        var rysq = ry * ry
        let lambda = (x1p * x1p) / rxsq + (y1p * y1p) / rysq
        if lambda > 1 {
            let scale = sqrt(lambda)
            rx *= scale
            ry *= scale
            rxsq = rx * rx
            rysq = ry * ry
        }
        let sign: CGFloat = (large == sweep) ? -1 : 1
        let numerator = max(0, rxsq * rysq - rxsq * y1p * y1p - rysq * x1p * x1p)
        let denom = rxsq * y1p * y1p + rysq * x1p * x1p
        let coef = sign * sqrt(denom == 0 ? 0 : numerator / denom)
        let cxp = coef * rx * y1p / ry
        let cyp = coef * -ry * x1p / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (p1.x + p2.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p1.y + p2.y) / 2
        func vectorAngle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let lengths = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            var ang = acos(min(1, max(-1, lengths == 0 ? 0 : dot / lengths)))
            if ux * vy - uy * vx < 0 { ang = -ang }
            return ang
        }
        let theta1 = vectorAngle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = vectorAngle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep, delta > 0 { delta -= 2 * .pi }
        if sweep, delta < 0 { delta += 2 * .pi }
        let pieces = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(pieces)
        for piece in 0..<pieces {
            let t1 = theta1 + step * CGFloat(piece)
            let t2 = t1 + step
            let alpha = sin(step) * (sqrt(4 + 3 * pow(tan(step / 2), 2)) - 1) / 3
            func point(_ t: CGFloat) -> CGPoint {
                CGPoint(
                    x: cx + rx * cos(t) * cosPhi - ry * sin(t) * sinPhi,
                    y: cy + rx * cos(t) * sinPhi + ry * sin(t) * cosPhi
                )
            }
            func derivative(_ t: CGFloat) -> CGPoint {
                CGPoint(
                    x: -rx * sin(t) * cosPhi - ry * cos(t) * sinPhi,
                    y: -rx * sin(t) * sinPhi + ry * cos(t) * cosPhi
                )
            }
            let fromPoint = point(t1)
            let toPoint = point(t2)
            let d1 = derivative(t1)
            let d2 = derivative(t2)
            if piece == 0, hypot(fromPoint.x - p1.x, fromPoint.y - p1.y) > 0.01 {
                path.addLine(to: fromPoint)
            }
            path.addCurve(
                to: toPoint,
                control1: CGPoint(x: fromPoint.x + alpha * d1.x, y: fromPoint.y + alpha * d1.y),
                control2: CGPoint(x: toPoint.x - alpha * d2.x, y: toPoint.y - alpha * d2.y)
            )
        }
    }
}
