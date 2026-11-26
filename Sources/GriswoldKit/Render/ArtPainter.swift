import CoreGraphics
import Foundation

/// Hand-built vector illustrations. Coordinates are points with the origin at
/// the top-left of each piece's design box (see `Art.size`).
enum ArtPainter {
    static func draw(_ art: Art, in c: CGContext) {
        switch art {
        case .sleigh: sleigh(c)
        case .reindeerStride: reindeer(c, gathered: false)
        case .reindeerGather: reindeer(c, gathered: true)
        case .presentRed: present(c, box: rgb(0xD9, 0x2B, 0x3A), ribbon: rgb(0xF6, 0xC9, 0x4E))
        case .presentGreen: present(c, box: rgb(0x1F, 0x8A, 0x4C), ribbon: rgb(0xF2, 0x3D, 0x4F))
        case .presentBlue: present(c, box: rgb(0x2D, 0x6C, 0xDF), ribbon: rgb(0xF4, 0xF7, 0xFB))
        case .snowman: snowman(c)
        case .splat: splat(c)
        case .squirrelStride: squirrel(c, gathered: false)
        case .squirrelGather: squirrel(c, gathered: true)
        case .sled: sled(c)
        }
    }

    // MARK: Helpers

    static func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
    }

    private static func fillEllipse(_ c: CGContext, _ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat,
                                    _ color: CGColor, rotate: CGFloat = 0) {
        c.saveGState()
        c.translateBy(x: cx, y: cy)
        c.rotate(by: rotate)
        c.setFillColor(color)
        c.fillEllipse(in: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
        c.restoreGState()
    }

    private static func stroke(_ c: CGContext, _ points: [CGPoint], _ color: CGColor, _ width: CGFloat) {
        guard let first = points.first else { return }
        c.setStrokeColor(color)
        c.setLineWidth(width)
        c.beginPath()
        c.move(to: first)
        for p in points.dropFirst() { c.addLine(to: p) }
        c.strokePath()
    }

    private static func roundRect(_ c: CGContext, _ rect: CGRect, _ radius: CGFloat, _ color: CGColor) {
        c.setFillColor(color)
        c.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        c.fillPath()
    }

    private static func gradientFill(_ c: CGContext, path: CGPath, colors: [CGColor],
                                     from: CGPoint, to: CGPoint) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil
        ) else { return }
        c.saveGState()
        c.addPath(path)
        c.clip()
        c.drawLinearGradient(gradient, start: from, end: to,
                             options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        c.restoreGState()
    }

    private static func snowball(_ c: CGContext, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [rgb(255, 255, 255), rgb(0xF1, 0xF6, 0xFC), rgb(0xC9, 0xD9, 0xEC)] as CFArray,
            locations: [0, 0.55, 1]
        ) else { return }
        c.saveGState()
        c.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        c.clip()
        c.drawRadialGradient(
            gradient,
            startCenter: CGPoint(x: cx - r * 0.32, y: cy - r * 0.36), startRadius: 0,
            endCenter: CGPoint(x: cx, y: cy), endRadius: r * 1.05,
            options: [.drawsAfterEndLocation]
        )
        c.restoreGState()
        c.setStrokeColor(rgb(0x9D, 0xB4, 0xCF, 0.75))
        c.setLineWidth(0.8)
        c.strokeEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    }

    // MARK: Reindeer (faces right)

    private static func reindeer(_ c: CGContext, gathered: Bool) {
        let coat = rgb(0x9A, 0x64, 0x34)
        let coatDark = rgb(0x6F, 0x45, 0x22)
        let hoof = rgb(0x2E, 0x1D, 0x12)

        // Legs behind the body. Far-side legs are darker to separate them.
        let far: [[CGPoint]]
        let near: [[CGPoint]]
        if gathered {
            far = [
                [CGPoint(x: 41, y: 37), CGPoint(x: 45, y: 46), CGPoint(x: 39, y: 50)],
                [CGPoint(x: 22, y: 37), CGPoint(x: 29, y: 45), CGPoint(x: 25, y: 51)],
            ]
            near = [
                [CGPoint(x: 43, y: 37), CGPoint(x: 49, y: 45), CGPoint(x: 44, y: 51)],
                [CGPoint(x: 19, y: 37), CGPoint(x: 25, y: 46), CGPoint(x: 20, y: 52)],
            ]
        } else {
            far = [
                [CGPoint(x: 41, y: 37), CGPoint(x: 50, y: 46), CGPoint(x: 57, y: 48)],
                [CGPoint(x: 21, y: 37), CGPoint(x: 14, y: 46), CGPoint(x: 8, y: 51)],
            ]
            near = [
                [CGPoint(x: 43, y: 36), CGPoint(x: 54, y: 43), CGPoint(x: 62, y: 42)],
                [CGPoint(x: 18, y: 36), CGPoint(x: 10, y: 43), CGPoint(x: 3, y: 46)],
            ]
        }
        for leg in far {
            stroke(c, leg, coatDark, 2.6)
            fillEllipse(c, leg[2].x, leg[2].y, 1.9, 1.6, hoof)
        }

        // Tail tuft.
        fillEllipse(c, 13.2, 28.5, 3.2, 2.4, rgb(0xF6, 0xEF, 0xE4))

        // Body with a paler belly.
        let body = CGPath(ellipseIn: CGRect(x: 14, y: 23.5, width: 32, height: 17), transform: nil)
        gradientFill(c, path: body, colors: [rgb(0xA9, 0x70, 0x3C), coat, rgb(0xC6, 0x98, 0x62)],
                     from: CGPoint(x: 30, y: 23), to: CGPoint(x: 30, y: 41))

        for leg in near {
            stroke(c, leg, coat, 2.9)
            fillEllipse(c, leg[2].x, leg[2].y, 2.0, 1.7, hoof)
        }

        // Neck.
        c.setFillColor(coat)
        c.beginPath()
        c.move(to: CGPoint(x: 39, y: 27))
        c.addQuadCurve(to: CGPoint(x: 50.5, y: 12.5), control: CGPoint(x: 43, y: 17))
        c.addLine(to: CGPoint(x: 56, y: 17.5))
        c.addQuadCurve(to: CGPoint(x: 47, y: 35), control: CGPoint(x: 51, y: 27))
        c.closePath()
        c.fillPath()
        // Chest ruff.
        fillEllipse(c, 46.5, 30.5, 3.4, 5.2, rgb(0xE9, 0xD9, 0xC0, 0.9), rotate: 0.35)

        // Antlers: far one darker.
        let antlerFar = rgb(0xA8, 0x84, 0x55)
        let antler = rgb(0xD9, 0xB8, 0x80)
        for (dx, color) in [(CGFloat(2.6), antlerFar), (CGFloat(0), antler)] {
            stroke(c, [CGPoint(x: 52 + dx, y: 10.5), CGPoint(x: 50 + dx, y: 5), CGPoint(x: 45.5 + dx, y: 1.6)], color, 1.5)
            stroke(c, [CGPoint(x: 50.3 + dx, y: 5.6), CGPoint(x: 53.6 + dx, y: 2)], color, 1.3)
            stroke(c, [CGPoint(x: 48.3 + dx, y: 3.6), CGPoint(x: 44 + dx, y: 5.4)], color, 1.3)
        }

        // Ear, head, snout.
        fillEllipse(c, 49.6, 11.2, 3.4, 1.7, coatDark, rotate: -0.5)
        fillEllipse(c, 55, 14.2, 6.8, 4.7, coat, rotate: 0.18)
        fillEllipse(c, 60.6, 15.8, 4.2, 3.1, rgb(0xB4, 0x7C, 0x48), rotate: 0.2)
        fillEllipse(c, 64.2, 15.3, 1.8, 1.6, hoof)
        fillEllipse(c, 56.6, 12.8, 0.95, 1.05, rgb(0x16, 0x0E, 0x08))
        fillEllipse(c, 56.9, 12.5, 0.32, 0.32, rgb(255, 255, 255))

        // Harness: collar with a bell and a girth strap.
        let red = rgb(0xD4, 0x20, 0x2F)
        stroke(c, [CGPoint(x: 40.5, y: 26), CGPoint(x: 47.5, y: 34.5)], red, 2.2)
        stroke(c, [CGPoint(x: 30, y: 23.8), CGPoint(x: 30, y: 40.2)], red, 2.0)
        fillEllipse(c, 45.6, 33.4, 1.5, 1.5, rgb(0xF6, 0xC9, 0x4E))
        fillEllipse(c, 30, 24.2, 1.2, 1.2, rgb(0xF6, 0xC9, 0x4E))
    }

    /// Nose position inside the reindeer box, for Rudolph's glow.
    static let reindeerNose = CGPoint(x: 64.2, y: 15.3)
    /// Where the harness meets the reins.
    static let reindeerHarness = CGPoint(x: 30, y: 24)

    // MARK: Sleigh and Santa (faces right)

    private static func sleigh(_ c: CGContext) {
        c.saveGState()
        c.translateBy(x: 0, y: 9)
        let gold = rgb(0xF2, 0xC1, 0x4B)
        let goldDark = rgb(0xB8, 0x86, 0x22)
        let red = rgb(0xD4, 0x20, 0x2F)

        // Sack of presents behind Santa.
        roundRect(c, CGRect(x: 17, y: -3, width: 9, height: 9), 1.2, rgb(0x2D, 0x6C, 0xDF))
        roundRect(c, CGRect(x: 30, y: -6, width: 10, height: 10), 1.2, rgb(0x1F, 0x8A, 0x4C))
        stroke(c, [CGPoint(x: 35, y: -6), CGPoint(x: 35, y: 4)], gold, 1.4)
        let sack = CGPath(ellipseIn: CGRect(x: 14, y: 2, width: 32, height: 34), transform: nil)
        gradientFill(c, path: sack, colors: [rgb(0xA8, 0x74, 0x42), rgb(0x76, 0x4B, 0x27)],
                     from: CGPoint(x: 20, y: 4), to: CGPoint(x: 42, y: 36))
        stroke(c, [CGPoint(x: 24, y: 6), CGPoint(x: 37, y: 5)], rgb(0x5A, 0x38, 0x1B), 1.6)

        // Santa: torso, belt, head, beard, hat, arm.
        fillEllipse(c, 58, 28, 12.5, 14, red)
        roundRect(c, CGRect(x: 46, y: 31, width: 24, height: 4), 1, rgb(0x1E, 0x1B, 0x1B))
        roundRect(c, CGRect(x: 61, y: 30.2, width: 5.6, height: 5.6), 1, gold)
        fillEllipse(c, 62, 10.5, 6.3, 6.3, rgb(0xF6, 0xCC, 0xAA))
        fillEllipse(c, 66.2, 11.6, 1.5, 1.4, rgb(0xEB, 0x9E, 0x8A))
        fillEllipse(c, 64.6, 9.2, 0.85, 0.95, rgb(0x1A, 0x14, 0x12))
        // Beard and moustache.
        fillEllipse(c, 63.6, 16.6, 6.6, 5.4, rgb(255, 255, 255))
        fillEllipse(c, 58.4, 13.2, 2.8, 4.6, rgb(255, 255, 255))
        fillEllipse(c, 66.4, 13.6, 2.9, 1.5, rgb(0xF4, 0xF7, 0xFB))
        // Hat: red cone blown back, white band and pompom.
        c.setFillColor(red)
        c.beginPath()
        c.move(to: CGPoint(x: 55.6, y: 6.6))
        c.addCurve(to: CGPoint(x: 44.5, y: 3.6), control1: CGPoint(x: 56, y: -3.4), control2: CGPoint(x: 47, y: -4.6))
        c.addCurve(to: CGPoint(x: 68.6, y: 6.4), control1: CGPoint(x: 52, y: 0.2), control2: CGPoint(x: 63, y: -2.2))
        c.closePath()
        c.fillPath()
        roundRect(c, CGRect(x: 54.6, y: 4.6, width: 15, height: 3.6), 1.8, rgb(255, 255, 255))
        fillEllipse(c, 44.6, 4.2, 2.7, 2.7, rgb(255, 255, 255))
        // Fur trim down the coat.
        stroke(c, [CGPoint(x: 62, y: 21), CGPoint(x: 62.4, y: 31)], rgb(255, 255, 255), 2.4)

        // Sleigh body.
        let body = CGMutablePath()
        body.move(to: CGPoint(x: 9, y: 20))
        body.addCurve(to: CGPoint(x: 22, y: 51), control1: CGPoint(x: 15, y: 28), control2: CGPoint(x: 14, y: 43))
        body.addLine(to: CGPoint(x: 76, y: 51))
        body.addCurve(to: CGPoint(x: 101, y: 28), control1: CGPoint(x: 92, y: 51), control2: CGPoint(x: 101, y: 41))
        body.addCurve(to: CGPoint(x: 93, y: 27.5), control1: CGPoint(x: 101, y: 21.5), control2: CGPoint(x: 93, y: 21.5))
        body.addCurve(to: CGPoint(x: 78, y: 38.5), control1: CGPoint(x: 93, y: 34), control2: CGPoint(x: 86, y: 38.5))
        body.addLine(to: CGPoint(x: 34, y: 38.5))
        body.addCurve(to: CGPoint(x: 16.5, y: 19), control1: CGPoint(x: 25, y: 38.5), control2: CGPoint(x: 20, y: 29))
        body.closeSubpath()
        gradientFill(c, path: body, colors: [rgb(0xE8, 0x2F, 0x40), rgb(0xA8, 0x14, 0x22)],
                     from: CGPoint(x: 50, y: 20), to: CGPoint(x: 50, y: 52))
        c.addPath(body)
        c.setStrokeColor(gold)
        c.setLineWidth(1.5)
        c.strokePath()
        // Side flourish.
        c.setStrokeColor(rgb(0xF2, 0xC1, 0x4B, 0.9))
        c.setLineWidth(1.2)
        c.beginPath()
        c.move(to: CGPoint(x: 28, y: 46))
        c.addCurve(to: CGPoint(x: 86, y: 41), control1: CGPoint(x: 48, y: 47.5), control2: CGPoint(x: 74, y: 48))
        c.strokePath()
        fillEllipse(c, 56, 44.6, 1.6, 1.6, gold)

        // Santa's arm reaches over the rail to the reins.
        stroke(c, [CGPoint(x: 60, y: 24), CGPoint(x: 70, y: 31), CGPoint(x: 80, y: 31.5)], rgb(0xBE, 0x1A, 0x29), 6)
        fillEllipse(c, 81.4, 31.6, 3.3, 3.5, rgb(255, 255, 255))
        fillEllipse(c, 85, 31.8, 2.7, 2.6, rgb(0x1E, 0x4D, 0x33))

        // Runners and struts.
        stroke(c, [CGPoint(x: 28, y: 51), CGPoint(x: 26, y: 61)], goldDark, 2)
        stroke(c, [CGPoint(x: 70, y: 51), CGPoint(x: 72, y: 61)], goldDark, 2)
        c.setStrokeColor(gold)
        c.setLineWidth(2.6)
        c.beginPath()
        c.move(to: CGPoint(x: 5, y: 54.5))
        c.addCurve(to: CGPoint(x: 9, y: 61.5), control1: CGPoint(x: 1.5, y: 56), control2: CGPoint(x: 3, y: 61.5))
        c.addLine(to: CGPoint(x: 90, y: 61.5))
        c.addCurve(to: CGPoint(x: 108, y: 46), control1: CGPoint(x: 102, y: 61.5), control2: CGPoint(x: 110, y: 54))
        c.addCurve(to: CGPoint(x: 100.5, y: 45.5), control1: CGPoint(x: 106.5, y: 40.5), control2: CGPoint(x: 99.5, y: 41))
        c.strokePath()
        c.restoreGState()
    }

    /// Santa's rein hand inside the sleigh box.
    static let sleighHand = CGPoint(x: 86, y: 40.8)

    // MARK: Present

    private static func present(_ c: CGContext, box: CGColor, ribbon: CGColor) {
        // Bow loops.
        fillEllipse(c, 10.6, 5.6, 4.8, 3.2, ribbon, rotate: 0.42)
        fillEllipse(c, 19.4, 5.6, 4.8, 3.2, ribbon, rotate: -0.42)
        fillEllipse(c, 10.8, 5.8, 2.2, 1.2, CGColor(gray: 0, alpha: 0.18), rotate: 0.42)
        fillEllipse(c, 19.2, 5.8, 2.2, 1.2, CGColor(gray: 0, alpha: 0.18), rotate: -0.42)

        roundRect(c, CGRect(x: 3, y: 12, width: 24, height: 18.5), 2, box)
        // Shade the right third so it reads as a box.
        roundRect(c, CGRect(x: 19, y: 12, width: 8, height: 18.5), 2, CGColor(gray: 0, alpha: 0.16))
        roundRect(c, CGRect(x: 13, y: 12, width: 4, height: 18.5), 0, ribbon)
        // Lid.
        roundRect(c, CGRect(x: 1.5, y: 8, width: 27, height: 5.8), 1.6, box)
        roundRect(c, CGRect(x: 1.5, y: 8, width: 27, height: 2.2), 1.2, CGColor(gray: 1, alpha: 0.22))
        roundRect(c, CGRect(x: 1.5, y: 12.4, width: 27, height: 1.4), 0.6, CGColor(gray: 0, alpha: 0.18))
        roundRect(c, CGRect(x: 12.6, y: 8, width: 4.8, height: 5.8), 0, ribbon)
        fillEllipse(c, 15, 7.2, 2.3, 2.1, ribbon)
        fillEllipse(c, 15, 7.2, 1.1, 1.0, CGColor(gray: 0, alpha: 0.14))
    }

    // MARK: Snowman

    private static func snowman(_ c: CGContext) {
        let twig = rgb(0x6B, 0x44, 0x23)
        let coal = rgb(0x1C, 0x1C, 0x22)

        // Arms.
        stroke(c, [CGPoint(x: 29, y: 60), CGPoint(x: 9, y: 46)], twig, 2.4)
        stroke(c, [CGPoint(x: 15, y: 50.2), CGPoint(x: 11, y: 41)], twig, 1.6)
        stroke(c, [CGPoint(x: 13, y: 48.8), CGPoint(x: 5, y: 51)], twig, 1.6)
        stroke(c, [CGPoint(x: 63, y: 60), CGPoint(x: 84, y: 40)], twig, 2.4)
        stroke(c, [CGPoint(x: 78, y: 45.6), CGPoint(x: 85, y: 49)], twig, 1.6)
        stroke(c, [CGPoint(x: 80, y: 43.6), CGPoint(x: 80, y: 35)], twig, 1.6)

        snowball(c, 46, 96, 29)
        snowball(c, 46, 61, 20.5)
        snowball(c, 46, 34, 14.5)

        // Scarf with a tail.
        let scarf = rgb(0xD4, 0x20, 0x2F)
        c.setFillColor(scarf)
        c.beginPath()
        c.move(to: CGPoint(x: 32.5, y: 42.5))
        c.addQuadCurve(to: CGPoint(x: 59.5, y: 42.5), control: CGPoint(x: 46, y: 51))
        c.addLine(to: CGPoint(x: 58.5, y: 48.5))
        c.addQuadCurve(to: CGPoint(x: 33.5, y: 48.5), control: CGPoint(x: 46, y: 57))
        c.closePath()
        c.fillPath()
        c.beginPath()
        c.move(to: CGPoint(x: 36, y: 49))
        c.addLine(to: CGPoint(x: 43, y: 51))
        c.addLine(to: CGPoint(x: 40, y: 69))
        c.addLine(to: CGPoint(x: 32.5, y: 67))
        c.closePath()
        c.fillPath()
        stroke(c, [CGPoint(x: 34.6, y: 59), CGPoint(x: 41.6, y: 61)], rgb(255, 255, 255, 0.9), 1.6)
        stroke(c, [CGPoint(x: 33.4, y: 64), CGPoint(x: 40.6, y: 66)], rgb(255, 255, 255, 0.9), 1.6)

        // Buttons.
        for y in [CGFloat(62), 71, 88, 98] {
            fillEllipse(c, 46, y, 2.2, 2.2, coal)
        }

        // Face.
        fillEllipse(c, 41, 30, 1.9, 2.1, coal)
        fillEllipse(c, 51, 30, 1.9, 2.1, coal)
        for (x, y) in [(39.5, 38.4), (42.6, 40.4), (46, 41.1), (49.4, 40.4), (52.5, 38.4)] {
            fillEllipse(c, CGFloat(x), CGFloat(y), 1.05, 1.05, coal)
        }
        c.setFillColor(rgb(0xF5, 0x8A, 0x1F))
        c.beginPath()
        c.move(to: CGPoint(x: 45, y: 32.6))
        c.addLine(to: CGPoint(x: 62, y: 36))
        c.addLine(to: CGPoint(x: 45.4, y: 37.4))
        c.closePath()
        c.fillPath()

        // Top hat, tipped a little.
        c.saveGState()
        c.translateBy(x: 46, y: 21.5)
        c.rotate(by: -0.14)
        roundRect(c, CGRect(x: -15, y: -1.6, width: 30, height: 3.6), 1.6, coal)
        roundRect(c, CGRect(x: -10, y: -18.5, width: 20, height: 18), 1.6, coal)
        roundRect(c, CGRect(x: -10, y: -6.6, width: 20, height: 4.4), 0, rgb(0xD4, 0x20, 0x2F))
        roundRect(c, CGRect(x: -8.4, y: -17.2, width: 3, height: 9.6), 1.2, CGColor(gray: 1, alpha: 0.16))
        c.restoreGState()
    }

    // MARK: Squirrel (faces right)

    private static func squirrel(_ c: CGContext, gathered: Bool) {
        let coat = rgb(0xB8, 0x64, 0x1E)
        let coatDark = rgb(0x84, 0x45, 0x12)
        let cream = rgb(0xF4, 0xE2, 0xC4)
        let ink = rgb(0x1B, 0x12, 0x0C)

        // The tail does most of the work of saying "squirrel": a fat plume
        // curling up and over the back.
        let tail = CGMutablePath()
        if gathered {
            tail.move(to: CGPoint(x: 19, y: 33))
            tail.addCurve(to: CGPoint(x: 9, y: 9), control1: CGPoint(x: 4, y: 33), control2: CGPoint(x: -1, y: 17))
            tail.addCurve(to: CGPoint(x: 27, y: 10), control1: CGPoint(x: 15, y: 1), control2: CGPoint(x: 27, y: 2))
            tail.addCurve(to: CGPoint(x: 20, y: 22), control1: CGPoint(x: 27, y: 17), control2: CGPoint(x: 20, y: 16))
            tail.addCurve(to: CGPoint(x: 25, y: 32), control1: CGPoint(x: 20, y: 28), control2: CGPoint(x: 23, y: 31))
        } else {
            tail.move(to: CGPoint(x: 20, y: 31))
            tail.addCurve(to: CGPoint(x: 1, y: 18), control1: CGPoint(x: 10, y: 34), control2: CGPoint(x: 0, y: 28))
            tail.addCurve(to: CGPoint(x: 15, y: 7), control1: CGPoint(x: 2, y: 10), control2: CGPoint(x: 9, y: 5))
            tail.addCurve(to: CGPoint(x: 15, y: 19), control1: CGPoint(x: 21, y: 9), control2: CGPoint(x: 14, y: 14))
            tail.addCurve(to: CGPoint(x: 25, y: 27), control1: CGPoint(x: 16, y: 24), control2: CGPoint(x: 21, y: 26))
        }
        tail.closeSubpath()
        gradientFill(c, path: tail, colors: [rgb(0xDD, 0x92, 0x44), coat, coatDark],
                     from: CGPoint(x: 4, y: 6), to: CGPoint(x: 24, y: 34))
        c.setStrokeColor(rgb(0xF1, 0xBE, 0x7C, 0.8))
        c.setLineWidth(1.4)
        c.beginPath()
        if gathered {
            c.move(to: CGPoint(x: 13, y: 28))
            c.addCurve(to: CGPoint(x: 20, y: 8), control1: CGPoint(x: 4, y: 20), control2: CGPoint(x: 10, y: 6))
        } else {
            c.move(to: CGPoint(x: 15, y: 28))
            c.addCurve(to: CGPoint(x: 12, y: 11), control1: CGPoint(x: 3, y: 26), control2: CGPoint(x: 4, y: 12))
        }
        c.strokePath()

        // Far-side legs.
        if gathered {
            stroke(c, [CGPoint(x: 40, y: 30), CGPoint(x: 41, y: 36), CGPoint(x: 38, y: 38)], coatDark, 2.4)
        } else {
            stroke(c, [CGPoint(x: 40, y: 29), CGPoint(x: 48, y: 33), CGPoint(x: 53, y: 32)], coatDark, 2.4)
            stroke(c, [CGPoint(x: 25, y: 30), CGPoint(x: 19, y: 35), CGPoint(x: 14, y: 37)], coatDark, 2.6)
        }

        // Body and belly.
        let body = CGMutablePath()
        body.addEllipse(in: CGRect(x: 20, y: gathered ? 20 : 21, width: 25, height: gathered ? 15 : 12.5))
        gradientFill(c, path: body, colors: [rgb(0xC8, 0x73, 0x2A), coat], from: CGPoint(x: 30, y: 20), to: CGPoint(x: 30, y: 35))
        fillEllipse(c, 34, gathered ? 32 : 30.5, 8.5, 3, cream, rotate: -0.08)

        // Near-side legs.
        if gathered {
            fillEllipse(c, 25, 31, 6, 5, coat)
            stroke(c, [CGPoint(x: 24, y: 36), CGPoint(x: 32, y: 38)], coat, 2.8)
            stroke(c, [CGPoint(x: 42, y: 30), CGPoint(x: 44, y: 36), CGPoint(x: 41, y: 38)], coat, 2.6)
        } else {
            stroke(c, [CGPoint(x: 42, y: 29), CGPoint(x: 51, y: 31), CGPoint(x: 57, y: 29)], coat, 2.6)
            stroke(c, [CGPoint(x: 23, y: 29), CGPoint(x: 16, y: 33), CGPoint(x: 10, y: 34)], coat, 2.8)
        }

        // Head.
        let hy: CGFloat = gathered ? 17 : 20
        fillEllipse(c, 44, hy - 6.5, 1.9, 3.4, coatDark, rotate: -0.25)
        fillEllipse(c, 47.4, hy - 6, 1.7, 3.0, coat, rotate: 0.1)
        fillEllipse(c, 47, hy, 6.4, 5.4, coat)
        fillEllipse(c, 52.4, hy + 1.6, 3.4, 2.7, rgb(0xCB, 0x7D, 0x36))
        fillEllipse(c, 49.5, hy + 2.8, 3.2, 2.2, cream)
        fillEllipse(c, 55.4, hy + 1, 1.05, 0.95, ink)
        fillEllipse(c, 48.6, hy - 1.3, 1.35, 1.45, ink)
        fillEllipse(c, 49.0, hy - 1.8, 0.45, 0.45, rgb(255, 255, 255))
    }

    // MARK: Saucer sled and rider (faces right)

    private static func sled(_ c: CGContext) {
        // Scarf streaming out behind.
        c.setStrokeColor(rgb(0xF6, 0xC9, 0x4E))
        c.setLineWidth(3.4)
        c.beginPath()
        c.move(to: CGPoint(x: 38, y: 17))
        c.addCurve(to: CGPoint(x: 6, y: 12), control1: CGPoint(x: 26, y: 9), control2: CGPoint(x: 18, y: 19))
        c.strokePath()
        c.setStrokeColor(rgb(0xD4, 0x20, 0x2F))
        c.setLineWidth(1.2)
        for x in [CGFloat(12), 18, 24, 30] {
            c.beginPath()
            c.move(to: CGPoint(x: x, y: 10.5))
            c.addLine(to: CGPoint(x: x + 1, y: 15.5))
            c.strokePath()
        }

        // The saucer, tipped back a little from the speed.
        c.saveGState()
        c.translateBy(x: 39, y: 40)
        c.rotate(by: -0.07)
        let dish = CGPath(ellipseIn: CGRect(x: -31, y: -6, width: 62, height: 12), transform: nil)
        gradientFill(c, path: dish, colors: [rgb(0xF2, 0xF6, 0xFB), rgb(0xA9, 0xB9, 0xCC), rgb(0x6F, 0x82, 0x9A)],
                     from: CGPoint(x: 0, y: -6), to: CGPoint(x: 0, y: 6))
        c.setStrokeColor(rgb(255, 255, 255, 0.85))
        c.setLineWidth(1.1)
        c.addEllipse(in: CGRect(x: -29, y: -5.2, width: 58, height: 7.6))
        c.strokePath()
        c.restoreGState()

        // Rider: bundled up, knees tucked, hanging on.
        let parka = rgb(0x1F, 0x7A, 0x52)
        let parkaDark = rgb(0x14, 0x56, 0x3A)
        fillEllipse(c, 52, 33, 7.5, 5, rgb(0x2B, 0x2E, 0x3A), rotate: 0.2)      // boots
        stroke(c, [CGPoint(x: 38, y: 33), CGPoint(x: 47, y: 30), CGPoint(x: 53, y: 33)], rgb(0x3A, 0x4A, 0x7A), 7)  // legs
        fillEllipse(c, 34, 27, 11.5, 11, parka)
        fillEllipse(c, 30, 30, 8, 7, parkaDark)
        stroke(c, [CGPoint(x: 36, y: 24), CGPoint(x: 44, y: 32), CGPoint(x: 55, y: 37)], parka, 5.2)                // arm
        fillEllipse(c, 56.4, 37.4, 3.1, 2.8, rgb(0xD4, 0x20, 0x2F))                                                  // mitten
        // Head, hat, and a face that knows this was a mistake.
        fillEllipse(c, 42, 13, 6.2, 6.2, rgb(0xF6, 0xCC, 0xAA))
        c.setFillColor(rgb(0xD4, 0x20, 0x2F))
        c.beginPath()
        c.move(to: CGPoint(x: 35.6, y: 11.6))
        c.addCurve(to: CGPoint(x: 23, y: 5), control1: CGPoint(x: 35, y: 3), control2: CGPoint(x: 28, y: 1))
        c.addCurve(to: CGPoint(x: 47.6, y: 9.4), control1: CGPoint(x: 32, y: 5), control2: CGPoint(x: 43, y: 2))
        c.closePath()
        c.fillPath()
        roundRect(c, CGRect(x: 34.6, y: 8.6, width: 14, height: 3.4), 1.7, rgb(255, 255, 255))
        fillEllipse(c, 22.6, 5.2, 2.6, 2.6, rgb(255, 255, 255))
        fillEllipse(c, 44.6, 12.2, 1.0, 1.25, rgb(0x1A, 0x14, 0x12))
        fillEllipse(c, 45.6, 16.2, 1.7, 2.1, rgb(0x5A, 0x1E, 0x1E))
        fillEllipse(c, 47.6, 13.8, 1.3, 1.2, rgb(0xEB, 0x9E, 0x8A))
    }

    // MARK: Snowball splat

    private static func splat(_ c: CGContext) {
        var rng = FastRNG(seed: 0xC0FFEE)
        let centre = CGPoint(x: 75, y: 66)
        // Each piece is filled on its own: one combined path would let
        // overlapping pieces with opposite winding punch holes in each other.
        var pieces: [CGPath] = []
        pieces.append(CGPath(ellipseIn: CGRect(x: centre.x - 30, y: centre.y - 28, width: 60, height: 56), transform: nil))
        // Lumpy rim.
        for i in 0..<22 {
            let angle = CGFloat(i) / 22 * .pi * 2 + CGFloat(rng.signed()) * 0.14
            let distance = CGFloat(rng.range(24, 36))
            let radius = CGFloat(rng.range(5, 11))
            pieces.append(CGPath(ellipseIn: CGRect(
                x: centre.x + cos(angle) * distance - radius,
                y: centre.y + sin(angle) * distance - radius,
                width: radius * 2, height: radius * 2
            ), transform: nil))
        }
        // Streaks thrown outward by the impact, each tapering to a point.
        for i in 0..<15 {
            let angle = CGFloat(i) / 15 * .pi * 2 + CGFloat(rng.signed()) * 0.18
            let inner = CGFloat(rng.range(22, 30))
            let outer = CGFloat(rng.range(42, 60))
            let spread = CGFloat(rng.range(0.08, 0.16))
            let streak = CGMutablePath()
            streak.move(to: CGPoint(x: centre.x + cos(angle - spread) * inner, y: centre.y + sin(angle - spread) * inner))
            streak.addLine(to: CGPoint(x: centre.x + cos(angle) * outer, y: centre.y + sin(angle) * outer * 0.92))
            streak.addLine(to: CGPoint(x: centre.x + cos(angle + spread) * inner, y: centre.y + sin(angle + spread) * inner))
            streak.closeSubpath()
            pieces.append(streak)
        }
        // Flung spatters.
        for i in 0..<11 {
            let angle = CGFloat(i) / 11 * .pi * 2 + CGFloat(rng.signed()) * 0.2
            let distance = CGFloat(rng.range(50, 68))
            let radius = CGFloat(rng.range(2.2, 5.0))
            pieces.append(CGPath(ellipseIn: CGRect(
                x: centre.x + cos(angle) * distance - radius,
                y: centre.y + sin(angle) * distance * 0.9 - radius,
                width: radius * 2, height: radius * 2.3
            ), transform: nil))
        }
        // Drips running down the glass: each narrows as it runs, then beads.
        for x in [CGFloat(57), 71, 88] {
            let length = CGFloat(rng.range(30, 86))
            let top = CGFloat(rng.range(4.5, 7))
            let tip = top * 0.42
            let start = centre.y + 16
            let drip = CGMutablePath()
            drip.move(to: CGPoint(x: x - top, y: start))
            drip.addQuadCurve(to: CGPoint(x: x - tip, y: start + length), control: CGPoint(x: x - tip, y: start + length * 0.35))
            drip.addLine(to: CGPoint(x: x + tip, y: start + length))
            drip.addQuadCurve(to: CGPoint(x: x + top, y: start), control: CGPoint(x: x + tip, y: start + length * 0.35))
            drip.closeSubpath()
            pieces.append(drip)
            let drop = tip * 1.9
            pieces.append(CGPath(ellipseIn: CGRect(x: x - drop, y: start + length - drop * 0.8,
                                                   width: drop * 2, height: drop * 2.4), transform: nil))
        }

        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [rgb(255, 255, 255), rgb(0xF2, 0xF7, 0xFD), rgb(0xD3, 0xE1, 0xF2)] as CFArray,
            locations: [0, 0.5, 1]
        ) else { return }
        c.saveGState()
        c.setAlpha(0.95)
        c.beginTransparencyLayer(auxiliaryInfo: nil)
        c.setFillColor(rgb(255, 255, 255))
        for piece in pieces {
            c.addPath(piece)
            c.fillPath()
        }
        // Shade what was just drawn, and only that.
        c.setBlendMode(.sourceIn)
        c.drawRadialGradient(
            gradient,
            startCenter: CGPoint(x: centre.x - 8, y: centre.y - 10), startRadius: 0,
            endCenter: centre, endRadius: 96,
            options: [.drawsAfterEndLocation]
        )
        c.endTransparencyLayer()
        c.restoreGState()
    }
}
