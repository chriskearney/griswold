import Combine
import Foundation

public enum BulbStyle: String, Codable, CaseIterable, Identifiable {
    case c9, mini, globe, icicle, star
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .c9: return "C9 Classic"
        case .mini: return "Mini"
        case .globe: return "Globe"
        case .icicle: return "Icicle"
        case .star: return "Star"
        }
    }
}

public enum LightPalette: String, Codable, CaseIterable, Identifiable {
    case classic, warmWhite, coolWhite, redGreen, candyCane, icy, gold, retro, pastel, rainbow, custom
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .classic: return "Classic Multicolor"
        case .warmWhite: return "Warm White"
        case .coolWhite: return "Cool White"
        case .redGreen: return "Red & Green"
        case .candyCane: return "Candy Cane"
        case .icy: return "Icy Blue"
        case .gold: return "Gold"
        case .retro: return "Retro Ceramic"
        case .pastel: return "Pastel"
        case .rainbow: return "Rainbow"
        case .custom: return "Custom Color"
        }
    }
}

public enum LightPattern: String, Codable, CaseIterable, Identifiable {
    case steady, twinkle, chase, wave, breathe, alternate, sparkle, meteor, channelFade, showtime
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .steady: return "Steady"
        case .twinkle: return "Twinkle"
        case .chase: return "Chase"
        case .wave: return "Wave"
        case .breathe: return "Breathe"
        case .alternate: return "Alternate"
        case .sparkle: return "Sparkle"
        case .meteor: return "Meteor"
        case .channelFade: return "Channel Fade"
        case .showtime: return "Showtime (all of them)"
        }
    }
}

public enum Accumulation: String, Codable, CaseIterable, Identifiable {
    case off, dusting, drifts, deep
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .off: return "Off"
        case .dusting: return "Dusting"
        case .drifts: return "Drifts"
        case .deep: return "Deep"
        }
    }
    /// Tallest a pile on a window may grow, in points.
    public var maxHeight: Float {
        switch self {
        case .off: return 0
        case .dusting: return 7
        case .drifts: return 15
        case .deep: return 28
        }
    }
}

public enum SurpriseFrequency: String, Codable, CaseIterable, Identifiable {
    case off, rare, sometimes, often
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .off: return "Never"
        case .rare: return "Rarely"
        case .sometimes: return "Sometimes"
        case .often: return "Often"
        }
    }
    /// Seconds between surprises, as a range to pick from.
    public var interval: ClosedRange<Double>? {
        switch self {
        case .off: return nil
        case .rare: return 600...1200
        case .sometimes: return 210...480
        case .often: return 60...150
        }
    }
}

public enum FrameRateMode: String, Codable, CaseIterable, Identifiable {
    case auto, smooth, efficient
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .auto: return "Automatic"
        case .smooth: return "Smooth (60 fps)"
        case .efficient: return "Efficient (30 fps)"
        }
    }
}

public enum SurpriseKind: String, Codable, CaseIterable, Identifiable {
    case santa, shootingStar, gust, presents, aurora, griswold, snowman, snowball, fireworks
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .santa: return "Santa's Sleigh"
        case .shootingStar: return "Shooting Star"
        case .gust: return "Gust of Wind"
        case .presents: return "Falling Presents"
        case .aurora: return "Northern Lights"
        case .griswold: return "The Griswold Moment"
        case .snowman: return "Snowman"
        case .snowball: return "Snowball"
        case .fireworks: return "Fireworks"
        }
    }
    public var symbol: String {
        switch self {
        case .santa: return "gift"
        case .shootingStar: return "star"
        case .gust: return "wind"
        case .presents: return "shippingbox"
        case .aurora: return "sparkles"
        case .griswold: return "bolt"
        case .snowman: return "snowflake"
        case .snowball: return "circle.fill"
        case .fireworks: return "fireworks"
        }
    }
}

/// Every user-facing option. Stored as one JSON blob so presets, defaults and
/// future additions stay in a single place.
public struct Config: Codable, Equatable {
    public var enabled = true

    public var snowEnabled = true
    public var snowIntensity: Double = 0.42
    public var flakeSize: Double = 1.0
    public var wind: Double = 0.35
    public var accumulation: Accumulation = .drifts
    public var groundSnow = true
    public var depthBehindWindows = true
    public var cursorPlay = true

    public var lightsEnabled = true
    public var bulbStyle: BulbStyle = .c9
    public var palette: LightPalette = .classic
    public var customColorHex = "FF453A"
    public var pattern: LightPattern = .twinkle
    public var lightSpeed: Double = 0.5
    public var brightness: Double = 0.85
    public var bulbScale: Double = 1.0
    public var spacing: Double = 1.0
    public var glow: Double = 0.7
    public var edgeTop = true
    public var edgeLeft = true
    public var edgeRight = true
    public var edgeBottom = false
    public var belowMenuBar = true

    public var surpriseFrequency: SurpriseFrequency = .sometimes
    public var disabledSurprises: [String] = []
    public var soundEnabled = false
    public var volume: Double = 0.5

    public var frameRate: FrameRateMode = .auto
    public var showOverFullscreen = false
    public var mainDisplayOnly = false
    public var checkForUpdates = true

    public init() {}

    public func isSurpriseEnabled(_ kind: SurpriseKind) -> Bool {
        !disabledSurprises.contains(kind.rawValue)
    }

    public mutating func setSurprise(_ kind: SurpriseKind, enabled: Bool) {
        disabledSurprises.removeAll { $0 == kind.rawValue }
        if !enabled { disabledSurprises.append(kind.rawValue) }
    }

    /// True when there is anything at all to draw.
    public var hasVisibleEffects: Bool {
        enabled && (snowEnabled || lightsEnabled || surpriseFrequency != .off)
    }
}

public struct Preset: Identifiable {
    public let id: String
    public let title: String
    public let blurb: String
    public let apply: (inout Config) -> Void

    public static let all: [Preset] = [
        Preset(id: "griswold", title: "Classic Griswold", blurb: "Big multicolor bulbs, steady snowfall") { c in
            c.snowEnabled = true; c.snowIntensity = 0.42; c.wind = 0.35; c.accumulation = .drifts
            c.lightsEnabled = true; c.bulbStyle = .c9; c.palette = .classic; c.pattern = .twinkle
            c.brightness = 0.9; c.glow = 0.75; c.bulbScale = 1.0; c.spacing = 1.0; c.lightSpeed = 0.5
        },
        Preset(id: "silent", title: "Silent Night", blurb: "Warm white minis, a few quiet flurries") { c in
            c.snowEnabled = true; c.snowIntensity = 0.18; c.wind = 0.15; c.accumulation = .dusting
            c.lightsEnabled = true; c.bulbStyle = .mini; c.palette = .warmWhite; c.pattern = .breathe
            c.brightness = 0.7; c.glow = 0.6; c.bulbScale = 1.0; c.spacing = 0.8; c.lightSpeed = 0.3
        },
        Preset(id: "wonderland", title: "Winter Wonderland", blurb: "Icicle lights and deep, drifting snow") { c in
            c.snowEnabled = true; c.snowIntensity = 0.7; c.wind = 0.4; c.accumulation = .deep
            c.lightsEnabled = true; c.bulbStyle = .icicle; c.palette = .icy; c.pattern = .sparkle
            c.brightness = 0.85; c.glow = 0.8; c.bulbScale = 1.0; c.spacing = 1.0; c.lightSpeed = 0.45
        },
        Preset(id: "candy", title: "Candy Cane Lane", blurb: "Red and white globes on the run") { c in
            c.snowEnabled = true; c.snowIntensity = 0.35; c.wind = 0.3; c.accumulation = .drifts
            c.lightsEnabled = true; c.bulbStyle = .globe; c.palette = .candyCane; c.pattern = .chase
            c.brightness = 0.9; c.glow = 0.7; c.bulbScale = 1.0; c.spacing = 1.0; c.lightSpeed = 0.55
        },
        Preset(id: "retro", title: "Retro '89", blurb: "Ceramic colors fading channel by channel") { c in
            c.snowEnabled = true; c.snowIntensity = 0.3; c.wind = 0.25; c.accumulation = .drifts
            c.lightsEnabled = true; c.bulbStyle = .c9; c.palette = .retro; c.pattern = .channelFade
            c.brightness = 0.85; c.glow = 0.65; c.bulbScale = 1.15; c.spacing = 1.15; c.lightSpeed = 0.4
        },
        Preset(id: "blizzard", title: "Blizzard", blurb: "Lights off. Everything else on.") { c in
            c.snowEnabled = true; c.snowIntensity = 1.0; c.wind = 0.95; c.accumulation = .deep
            c.lightsEnabled = false
        },
        Preset(id: "lights", title: "Just the Lights", blurb: "Gold stars, no weather") { c in
            c.snowEnabled = false
            c.lightsEnabled = true; c.bulbStyle = .star; c.palette = .gold; c.pattern = .wave
            c.brightness = 0.85; c.glow = 0.7; c.bulbScale = 1.0; c.spacing = 1.0; c.lightSpeed = 0.45
        },
    ]
}

/// Observable wrapper that persists `Config` to UserDefaults.
public final class Settings: ObservableObject {
    public static let shared = Settings()

    private static let storageKey = "config.v1"
    private let defaults: UserDefaults
    private var saveWork: DispatchWorkItem?

    @Published public var config: Config {
        didSet {
            guard config != oldValue else { return }
            scheduleSave()
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        config = Settings.load(from: defaults)
    }

    /// Decodes stored settings on top of the defaults, so options added in a
    /// later version pick up their default instead of failing the whole decode.
    static func load(from defaults: UserDefaults) -> Config {
        guard let stored = defaults.data(forKey: storageKey) else { return Config() }
        return decode(stored) ?? Config()
    }

    static func decode(_ stored: Data) -> Config? {
        guard
            let baseData = try? JSONEncoder().encode(Config()),
            var base = (try? JSONSerialization.jsonObject(with: baseData)) as? [String: Any],
            let overlay = (try? JSONSerialization.jsonObject(with: stored)) as? [String: Any]
        else { return nil }
        for (key, value) in overlay where base[key] != nil {
            base[key] = value
        }
        guard let merged = try? JSONSerialization.data(withJSONObject: base) else { return nil }
        if let config = try? JSONDecoder().decode(Config.self, from: merged) { return config }
        // One bad value (an enum case that no longer exists) should not cost the
        // user every other setting: drop keys one at a time until it decodes.
        for key in overlay.keys {
            var trimmed = base
            if let original = (try? JSONSerialization.jsonObject(with: baseData)) as? [String: Any] {
                trimmed[key] = original[key]
            }
            if let data = try? JSONSerialization.data(withJSONObject: trimmed),
               let config = try? JSONDecoder().decode(Config.self, from: data) {
                return config
            }
        }
        return nil
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let snapshot = config
        let work = DispatchWorkItem { [defaults] in
            if let data = try? JSONEncoder().encode(snapshot) {
                defaults.set(data, forKey: Settings.storageKey)
            }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    public func apply(_ preset: Preset) {
        var next = config
        next.enabled = true
        preset.apply(&next)
        config = next
    }

    public func resetToDefaults() {
        config = Config()
    }
}
