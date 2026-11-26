import AppKit
import CoreGraphics
import Foundation

/// Watches where other apps' windows are, so snow can land on them.
///
/// This only reads window rectangles from the window server. It never reads
/// window contents or titles, so it needs no Screen Recording permission.
public final class WindowTracker {
    public private(set) var windows: [WindowInfo] = []
    /// Bumped every time the list changes.
    public private(set) var generation = 0
    /// Set when the active Space changed since the last poll.
    public private(set) var spaceChangedAt: CFTimeInterval = 0

    private var timer: Timer?
    private var lastChange: CFTimeInterval = 0
    private var observers: [NSObjectProtocol] = []

    private static let idleInterval: TimeInterval = 0.4
    private static let activeInterval: TimeInterval = 1.0 / 30.0

    public init() {}

    public var isRunning: Bool { timer != nil }

    public func start() {
        guard timer == nil else { return }
        let centre = NSWorkspace.shared.notificationCenter
        observers.append(centre.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.spaceChangedAt = CACurrentMediaTime()
            self?.poll()
        })
        poll()
        schedule(WindowTracker.idleInterval)
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        let centre = NSWorkspace.shared.notificationCenter
        observers.forEach { centre.removeObserver($0) }
        observers.removeAll()
        if !windows.isEmpty {
            windows = []
            generation += 1
        }
    }

    private func schedule(_ interval: TimeInterval) {
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        poll()
        // Poll quickly while something is being dragged, slowly otherwise.
        let now = CACurrentMediaTime()
        let busy = NSEvent.pressedMouseButtons != 0 || now - lastChange < 0.6
        let wanted = busy ? WindowTracker.activeInterval : WindowTracker.idleInterval
        if let timer, abs(timer.timeInterval - wanted) > 0.001 {
            schedule(wanted)
        }
    }

    public func poll() {
        let next = WindowTracker.snapshot()
        if next != windows {
            windows = next
            generation += 1
            lastChange = CACurrentMediaTime()
        }
    }

    /// Ordinary application windows, front to back. The overlays themselves sit
    /// on a higher layer, so the layer test already leaves them out.
    static func snapshot() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var result: [WindowInfo] = []
        result.reserveCapacity(list.count)
        for entry in list {
            guard
                (entry[kCGWindowLayer as String] as? Int) == 0,
                let id = entry[kCGWindowNumber as String] as? UInt32,
                let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { continue }
            if let alpha = entry[kCGWindowAlpha as String] as? Double, alpha < 0.1 { continue }
            guard frame.width >= 120, frame.height >= 60 else { continue }
            result.append(WindowInfo(id: id, frame: frame))
        }
        return result
    }
}
