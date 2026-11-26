import CoreGraphics
import Foundation

/// A half-open horizontal run, in points.
public struct Span: Equatable {
    public var lo: Float
    public var hi: Float

    public init(_ lo: Float, _ hi: Float) {
        self.lo = lo
        self.hi = hi
    }

    public var length: Float { hi - lo }
}

public enum SpanMath {
    /// Removes every `cover` from `base`, returning what is left, in order.
    public static func subtract(_ base: Span, covers: [Span], minimum: Float = 0) -> [Span] {
        var remaining = [base]
        for cover in covers where cover.hi > cover.lo {
            var next: [Span] = []
            next.reserveCapacity(remaining.count + 1)
            for span in remaining {
                if cover.hi <= span.lo || cover.lo >= span.hi {
                    next.append(span)
                    continue
                }
                if cover.lo > span.lo { next.append(Span(span.lo, cover.lo)) }
                if cover.hi < span.hi { next.append(Span(cover.hi, span.hi)) }
            }
            remaining = next
            if remaining.isEmpty { break }
        }
        return remaining.filter { $0.length >= minimum }
    }
}

/// A window as the snow sees it: an id and a rectangle in global display
/// coordinates (origin at the top-left of the main display, y pointing down).
public struct WindowInfo: Equatable {
    public var id: UInt32
    public var frame: CGRect

    public init(id: UInt32, frame: CGRect) {
        self.id = id
        self.frame = frame
    }
}

/// A stretch of some window's top edge that snow can land on.
public struct Ledge: Equatable {
    public var windowID: UInt32
    public var span: Span
    public var y: Float
    /// The window's own full extent, used to anchor its pile.
    public var windowSpan: Span
}

public enum LedgeFinder {
    /// Finds the visible parts of each window's top edge inside one screen.
    ///
    /// - Parameters:
    ///   - windows: front-to-back, in global coordinates.
    ///   - screen: the screen's rectangle in the same coordinates.
    ///   - topInset: height reserved at the top (menu bar); edges there are skipped.
    /// - Returns: ledges in screen-local coordinates.
    public static func ledges(windows: [WindowInfo], screen: CGRect, topInset: Float) -> [Ledge] {
        var result: [Ledge] = []
        let width = Float(screen.width)
        let height = Float(screen.height)
        let originX = Float(screen.minX)
        let originY = Float(screen.minY)

        for (index, window) in windows.enumerated() {
            let top = Float(window.frame.minY) - originY
            // Maximised and off-screen edges have nowhere for a pile to sit.
            guard top > topInset + 6, top < height - 8 else { continue }
            let left = Float(window.frame.minX) - originX
            let right = Float(window.frame.maxX) - originX
            let visibleLeft = max(left, 0)
            let visibleRight = min(right, width)
            guard visibleRight - visibleLeft >= 40 else { continue }

            // Anything in front that covers the strip just above this edge hides it.
            var covers: [Span] = []
            for front in windows[..<index] {
                let frontTop = Float(front.frame.minY) - originY
                let frontBottom = Float(front.frame.maxY) - originY
                if frontTop <= top - 3, frontBottom >= top {
                    covers.append(Span(Float(front.frame.minX) - originX, Float(front.frame.maxX) - originX))
                }
            }
            let spans = SpanMath.subtract(Span(visibleLeft, visibleRight), covers: covers, minimum: 24)
            for span in spans {
                result.append(Ledge(windowID: window.id, span: span, y: top, windowSpan: Span(left, right)))
            }
        }
        return result
    }

    /// True when some window fills the whole screen (a full-screen app or game).
    public static func hasFullscreenWindow(windows: [WindowInfo], screen: CGRect) -> Bool {
        windows.contains { window in
            abs(window.frame.minX - screen.minX) < 2 && abs(window.frame.minY - screen.minY) < 2
                && abs(window.frame.width - screen.width) < 2 && abs(window.frame.height - screen.height) < 2
        }
    }
}
