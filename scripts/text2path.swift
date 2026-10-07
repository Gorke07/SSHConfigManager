import CoreText
// Converts text to SVG path data with CoreText (icon layers must not contain <text>).
import Foundation
// usage: text2path <fontName> <size> <x> <y> <text>  -> prints SVG path d (y-down)
let a = CommandLine.arguments
let font = CTFontCreateWithName(a[1] as CFString, CGFloat(Double(a[2])!), nil)
let ox = Double(a[3])!, oy = Double(a[4])!
let str = NSAttributedString(string: a[5], attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
let line = CTLineCreateWithAttributedString(str)
var d = ""
func f(_ v: Double) -> String { String(format: "%.2f", v) }
for run in CTLineGetGlyphRuns(line) as! [CTRun] {
    let n = CTRunGetGlyphCount(run)
    var glyphs = [CGGlyph](repeating: 0, count: n); var pos = [CGPoint](repeating: .zero, count: n)
    CTRunGetGlyphs(run, CFRange(location: 0, length: n), &glyphs); CTRunGetPositions(run, CFRange(location: 0, length: n), &pos)
    for i in 0..<n {
        guard let p = CTFontCreatePathForGlyph(font, glyphs[i], nil) else { continue }
        let gx = ox + pos[i].x, gy = oy
        p.applyWithBlock { e in
            let pts = e.pointee.points
            func P(_ k: Int) -> String { "\(f(gx + pts[k].x)),\(f(gy - pts[k].y))" }
            switch e.pointee.type {
            case .moveToPoint: d += "M\(P(0))"
            case .addLineToPoint: d += "L\(P(0))"
            case .addQuadCurveToPoint: d += "Q\(P(0)) \(P(1))"
            case .addCurveToPoint: d += "C\(P(0)) \(P(1)) \(P(2))"
            case .closeSubpath: d += "Z"
            @unknown default: break
            }
        }
    }
}
print(d)
