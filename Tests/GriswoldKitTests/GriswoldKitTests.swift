import CoreGraphics
import XCTest
@testable import GriswoldKit

final class SpanMathTests: XCTestCase {
    func testSubtractSplitsAroundACover() {
        let left = SpanMath.subtract(Span(0, 100), covers: [Span(40, 60)])
        XCTAssertEqual(left, [Span(0, 40), Span(60, 100)])
    }

    func testSubtractDropsFullyCoveredSpans() {
        XCTAssertTrue(SpanMath.subtract(Span(10, 20), covers: [Span(0, 30)]).isEmpty)
    }

    func testSubtractIgnoresCoversThatMiss() {
        XCTAssertEqual(SpanMath.subtract(Span(0, 50), covers: [Span(60, 80), Span(-20, -5)]), [Span(0, 50)])
    }

    func testSubtractRespectsMinimumLength() {
        let left = SpanMath.subtract(Span(0, 100), covers: [Span(10, 95)], minimum: 24)
        XCTAssertTrue(left.isEmpty)
    }
}

final class LedgeFinderTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testSingleWindowGetsAFullLedge() {
        let windows = [WindowInfo(id: 1, frame: CGRect(x: 100, y: 200, width: 600, height: 400))]
        let ledges = LedgeFinder.ledges(windows: windows, screen: screen, topInset: 25)
        XCTAssertEqual(ledges.count, 1)
        XCTAssertEqual(ledges[0].span, Span(100, 700))
        XCTAssertEqual(ledges[0].y, 200)
    }

    func testFrontWindowHidesPartOfTheEdgeBehindIt() {
        let windows = [
            WindowInfo(id: 2, frame: CGRect(x: 400, y: 100, width: 400, height: 500)),
            WindowInfo(id: 1, frame: CGRect(x: 100, y: 200, width: 600, height: 400)),
        ]
        let ledges = LedgeFinder.ledges(windows: windows, screen: screen, topInset: 25)
        let back = ledges.filter { $0.windowID == 1 }
        XCTAssertEqual(back.map(\.span), [Span(100, 400)])
        XCTAssertEqual(ledges.filter { $0.windowID == 2 }.map(\.span), [Span(400, 800)])
    }

    func testWindowBelowAnotherIsNotHidden() {
        // The front window ends above the back window's top edge, so it covers nothing.
        let windows = [
            WindowInfo(id: 2, frame: CGRect(x: 100, y: 50, width: 600, height: 100)),
            WindowInfo(id: 1, frame: CGRect(x: 100, y: 300, width: 600, height: 400)),
        ]
        let ledges = LedgeFinder.ledges(windows: windows, screen: screen, topInset: 25)
        XCTAssertEqual(ledges.filter { $0.windowID == 1 }.map(\.span), [Span(100, 700)])
    }

    func testMaximisedWindowHasNoLedge() {
        let windows = [WindowInfo(id: 1, frame: CGRect(x: 0, y: 25, width: 1440, height: 875))]
        XCTAssertTrue(LedgeFinder.ledges(windows: windows, screen: screen, topInset: 25).isEmpty)
    }

    func testLedgesAreLocalToASecondScreen() {
        let second = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let windows = [WindowInfo(id: 1, frame: CGRect(x: 1640, y: 300, width: 500, height: 300))]
        let ledges = LedgeFinder.ledges(windows: windows, screen: second, topInset: 25)
        XCTAssertEqual(ledges.map(\.span), [Span(200, 700)])
    }

    func testFullscreenDetection() {
        let full = [WindowInfo(id: 1, frame: screen)]
        let normal = [WindowInfo(id: 1, frame: CGRect(x: 0, y: 25, width: 1440, height: 875))]
        XCTAssertTrue(LedgeFinder.hasFullscreenWindow(windows: full, screen: screen))
        XCTAssertFalse(LedgeFinder.hasFullscreenWindow(windows: normal, screen: screen))
    }
}

final class SnowPileTests: XCTestCase {
    private func pile(width: Float = 600, max: Float = 20) -> SnowPile {
        SnowPile(id: 7, originX: 100, width: width, y: 300, maxHeight: max, tapered: true)
    }

    func testDepositRaisesTheSurfaceWhereItLands() {
        let pile = pile()
        XCTAssertEqual(pile.height(atX: 400), 0)
        XCTAssertTrue(pile.deposit(x: 400, amount: 30))
        XCTAssertGreaterThan(pile.height(atX: 400), 0)
        XCTAssertEqual(pile.height(atX: 150), 0, accuracy: 0.001)
    }

    func testDepositConservesVolume() {
        let pile = pile()
        pile.deposit(x: 400, amount: 30)
        XCTAssertEqual(pile.volume, 30, accuracy: 0.01)
    }

    func testDepositOutsideThePileIsRejected() {
        let pile = pile()
        XCTAssertFalse(pile.deposit(x: 50, amount: 30))
        XCTAssertFalse(pile.deposit(x: 900, amount: 30))
        XCTAssertEqual(pile.volume, 0)
    }

    func testPileStopsGrowingAtItsLimit() {
        let pile = pile(max: 10)
        var accepted = 0
        for _ in 0..<2000 where pile.deposit(x: 400, amount: 20) { accepted += 1 }
        XCTAssertLessThan(accepted, 2000)
        for _ in 0..<400 { pile.relax() }
        XCTAssertLessThan(pile.height(atX: 400), 10 * 1.6)
    }

    func testRelaxSpreadsASpikeWithoutLosingSnow() {
        let pile = pile(max: 200)
        for _ in 0..<40 { pile.deposit(x: 400, amount: 30, force: true) }
        let before = pile.volume
        let peak = pile.height(atX: 400)
        for _ in 0..<600 { pile.relax() }
        XCTAssertEqual(pile.volume, before, accuracy: before * 0.001)
        XCTAssertLessThan(pile.height(atX: 400), peak)
    }

    func testShedEmptiesThePileAndReturnsItsSnow() {
        let pile = pile()
        var rng = FastRNG(seed: 3)
        for _ in 0..<300 { pile.deposit(x: rng.range(150, 650), amount: 12) }
        let before = pile.volume
        let chunks = pile.shed()
        XCTAssertTrue(pile.isEmpty)
        XCTAssertFalse(chunks.isEmpty)
        // Tiny scraps are dropped, so allow a little loss but nothing gained.
        let shed = chunks.reduce(Float(0)) { $0 + $1.amount }
        XCTAssertLessThanOrEqual(shed, before + 0.01)
        XCTAssertGreaterThan(shed, before * 0.8)
    }

    func testReshapeKeepsSnowInPlaceWhenTheWindowGrowsLeft() {
        let pile = pile()
        pile.deposit(x: 400, amount: 60, force: true)
        let before = pile.height(atX: 400)
        pile.reshape(originX: 40, width: 660)
        XCTAssertEqual(pile.height(atX: 400), before, accuracy: 0.01)
    }

    func testMeltReachesZeroAndStops() {
        let pile = pile()
        pile.deposit(x: 400, amount: 30)
        for _ in 0..<100 { pile.melt(0.5) }
        XCTAssertTrue(pile.isEmpty)
        XCTAssertEqual(pile.volume, 0)
    }
}

final class SnowSystemTests: XCTestCase {
    func testTargetCountScalesWithIntensityAndIsBounded() {
        let size = SIMD2<Float>(1440, 900)
        XCTAssertEqual(SnowSystem.targetCount(intensity: 0, size: size), 0)
        let light = SnowSystem.targetCount(intensity: 0.2, size: size)
        let heavy = SnowSystem.targetCount(intensity: 1, size: size)
        XCTAssertGreaterThan(heavy, light)
        XCTAssertLessThanOrEqual(SnowSystem.targetCount(intensity: 1, size: SIMD2(7680, 4320)), 5200)
    }

    func testFlakesFillAndThenDrainWhenSwitchedOff() {
        let snow = SnowSystem(seed: 1)
        var env = SnowEnvironment(size: SIMD2(800, 600), wind: 0, time: 0)
        snow.target = 200
        snow.update(dt: 1.0 / 60, env: env)
        XCTAssertEqual(snow.count, 200)
        snow.target = 0
        for step in 0..<(60 * 60) {
            env.time = Float(step) / 60
            snow.update(dt: 1.0 / 60, env: env)
        }
        XCTAssertTrue(snow.isIdle)
    }

    func testSnowLandsOnASurface() {
        let snow = SnowSystem(seed: 2)
        let pile = SnowPile(id: 1, originX: 0, width: 800, y: 300, maxHeight: 20, tapered: false)
        let map = SurfaceMap(width: 800)
        map.add(SurfaceMap.Entry(lo: 0, hi: 800, y: 300, pile: pile))
        var env = SnowEnvironment(size: SIMD2(800, 600), wind: 0, time: 0)
        env.surfaces = map
        snow.target = 600
        for step in 0..<(60 * 30) {
            env.time = Float(step) / 60
            snow.update(dt: 1.0 / 60, env: env)
        }
        XCTAssertGreaterThan(pile.volume, 0)
    }
}

final class SettingsTests: XCTestCase {
    func testDefaultsRoundTrip() throws {
        let data = try JSONEncoder().encode(Config())
        XCTAssertEqual(Settings.decode(data), Config())
    }

    func testMissingKeysFallBackToDefaults() throws {
        // What an older version would have saved: only some of today's keys.
        let stored = try JSONSerialization.data(withJSONObject: ["snowIntensity": 0.9, "bulbStyle": "globe"])
        let config = try XCTUnwrap(Settings.decode(stored))
        XCTAssertEqual(config.snowIntensity, 0.9)
        XCTAssertEqual(config.bulbStyle, .globe)
        XCTAssertEqual(config.pattern, Config().pattern)
    }

    func testOneUnknownEnumValueDoesNotLoseEverythingElse() throws {
        let stored = try JSONSerialization.data(withJSONObject: ["snowIntensity": 0.9, "bulbStyle": "laser"])
        let config = try XCTUnwrap(Settings.decode(stored))
        XCTAssertEqual(config.snowIntensity, 0.9)
        XCTAssertEqual(config.bulbStyle, Config().bulbStyle)
    }

    func testPresetsTurnTheAppOn() {
        let defaults = UserDefaults(suiteName: "griswold.tests.\(UUID().uuidString)")!
        let settings = Settings(defaults: defaults)
        settings.config.enabled = false
        settings.apply(Preset.all[0])
        XCTAssertTrue(settings.config.enabled)
    }

    func testSurpriseToggles() {
        var config = Config()
        XCTAssertTrue(config.isSurpriseEnabled(.santa))
        config.setSurprise(.santa, enabled: false)
        XCTAssertFalse(config.isSurpriseEnabled(.santa))
        config.setSurprise(.santa, enabled: true)
        XCTAssertTrue(config.isSurpriseEnabled(.santa))
        XCTAssertTrue(config.disabledSurprises.isEmpty)
    }
}

final class LightTests: XCTestCase {
    func testEveryPatternStaysInASaneRange() {
        for pattern in LightPattern.allCases {
            for index in 0..<120 {
                for step in 0..<200 {
                    let sample = LightPatterns.sample(
                        pattern, index: index, count: 120, slot: index % 5, slots: 5,
                        time: Float(step) * 0.173, seed: Float(index) / 120
                    )
                    XCTAssertTrue(sample.level.isFinite, "\(pattern)")
                    XCTAssertGreaterThanOrEqual(sample.level, 0, "\(pattern)")
                    XCTAssertLessThanOrEqual(sample.level, 1.7, "\(pattern)")
                    XCTAssertGreaterThanOrEqual(sample.white, 0, "\(pattern)")
                    XCTAssertLessThanOrEqual(sample.white, 1, "\(pattern)")
                }
            }
        }
    }

    func testEveryPaletteHasColours() {
        for palette in LightPalette.allCases {
            XCTAssertFalse(Palettes.colors(for: palette, customHex: "33AAFF").isEmpty, "\(palette)")
        }
    }

    func testHexParsing() {
        XCTAssertEqual(Palettes.color(hex: "#FF0000"), SIMD3<Float>(1, 0, 0))
        XCTAssertNil(Palettes.color(hex: "nope"))
        XCTAssertEqual(Palettes.colors(for: .custom, customHex: "00FF00"), [SIMD3<Float>(0, 1, 0)])
    }

    func testLayoutHangsBulbsOnlyOnChosenEdges() {
        var config = Config()
        config.edgeTop = true
        config.edgeLeft = false
        config.edgeRight = false
        config.edgeBottom = false
        let size = SIMD2<Float>(1440, 900)
        let topOnly = LightString(layout: LightString.Layout(size: size, topInset: 25, config: config))
        config.edgeLeft = true
        config.edgeRight = true
        let threeSides = LightString(layout: LightString.Layout(size: size, topInset: 25, config: config))
        XCTAssertGreaterThan(topOnly.bulbCount, 10)
        XCTAssertGreaterThan(threeSides.bulbCount, topOnly.bulbCount)
        config.edgeTop = false
        config.edgeLeft = false
        config.edgeRight = false
        XCTAssertEqual(LightString(layout: LightString.Layout(size: size, topInset: 25, config: config)).bulbCount, 0)
    }
}

final class AppLogicTests: XCTestCase {
    func testVersionComparison() {
        XCTAssertTrue(UpdateChecker.isNewer("1.0.1", than: "1.0.0"))
        XCTAssertTrue(UpdateChecker.isNewer("1.10.0", than: "1.9.9"))
        XCTAssertTrue(UpdateChecker.isNewer("2.0", than: "1.9.9"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0.0", than: "1.0.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0", than: "1.0.0"))
        XCTAssertFalse(UpdateChecker.isNewer("0.9.9", than: "1.0.0"))
    }

    func testCountdown() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func day(_ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
        }
        XCTAssertEqual(AppModel.countdown(from: day(11, 26), calendar: calendar), "29 days until Christmas")
        XCTAssertEqual(AppModel.countdown(from: day(12, 23), calendar: calendar), "2 days until Christmas")
        XCTAssertEqual(AppModel.countdown(from: day(12, 24), calendar: calendar), "It's Christmas Eve")
        XCTAssertEqual(AppModel.countdown(from: day(12, 25), calendar: calendar), "Merry Christmas!")
        XCTAssertEqual(AppModel.countdown(from: day(12, 28), calendar: calendar), "Happy holidays")
    }

    func testSantaCrossesTheWholeDesktop() {
        let director = Director()
        let bounds = CGRect(x: 0, y: 0, width: 3360, height: 1080)
        director.desktopBounds = { bounds }
        let config = Config()
        director.advance(now: 0, config: config)
        director.trigger(.santa, now: 0, config: config)
        let flight = try? XCTUnwrap(director.world.santa)
        XCTAssertNotNil(flight)
        guard let flight else { return }
        // Starts off one side and ends with the whole train off the other.
        XCTAssertTrue(flight.startX < 0 || flight.startX > 3360)
        XCTAssertGreaterThan(abs(flight.endX - flight.startX), 3360)
        var now = 0.0
        while now < Double(flight.duration) + 1 {
            now += 0.05
            director.advance(now: now, config: config)
        }
        XCTAssertNil(director.world.santa)
    }

    func testGriswoldMomentGoesDarkThenBlazes() {
        let director = Director()
        var config = Config()
        config.surpriseFrequency = .off
        director.advance(now: 0, config: config)
        director.trigger(.griswold, now: 0, config: config)
        director.advance(now: 2.5, config: config)
        XCTAssertEqual(director.world.boost.level, 0)
        let serial = director.world.blazeSerial
        director.advance(now: 2.6, config: config)
        var now = 2.6
        while now < 4.0 {
            now += 0.05
            director.advance(now: now, config: config)
        }
        XCTAssertGreaterThan(director.world.boost.level, 1.5)
        XCTAssertEqual(director.world.blazeSerial, serial + 1)
        while now < 13 {
            now += 0.05
            director.advance(now: now, config: config)
        }
        XCTAssertEqual(director.world.boost.level, 1)
    }
}
