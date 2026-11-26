import CoreGraphics
import Foundation

/// Command-line front end for `Snapshot`.
public enum SnapshotCommand {
    private static let flags = ["--snapshot", "--dump-atlas", "--dump-art", "--icon", "--dmg-background", "--link-preview", "--demo-video"]

    public static func handles(_ arguments: [String]) -> Bool {
        flags.contains { arguments.contains($0) }
    }

    public static func run(_ arguments: [String]) -> Int32 {
        func value(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }

        if let path = value("--dump-atlas") {
            guard let image = Snapshot.atlasImage(), Snapshot.write(image, to: URL(fileURLWithPath: path)) else {
                FileHandle.standardError.write(Data("could not render the atlas\n".utf8))
                return 1
            }
            return 0
        }

        if let directory = value("--dump-art") {
            let images = Snapshot.artImages()
            guard !images.isEmpty else { return 1 }
            for (name, image) in images {
                Snapshot.write(image, to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
            }
            return 0
        }

        if let path = value("--link-preview") {
            let scale = value("--scale").flatMap(Double.init) ?? 2
            guard let image = BrandArt.linkPreview(scale: CGFloat(scale)),
                  Snapshot.write(image, to: URL(fileURLWithPath: path)) else {
                FileHandle.standardError.write(Data("could not render the link preview\n".utf8))
                return 1
            }
            return 0
        }

        if let path = value("--demo-video") {
            let fps = value("--fps").flatMap(Int.init) ?? 60
            let limit = value("--seconds").flatMap(Double.init)
            let ok = DemoVideo.render(
                to: URL(fileURLWithPath: path), framesPerSecond: fps, limit: limit,
                pixelsPerPoint: value("--scale").flatMap(Double.init) ?? 1.5,
                bitRate: value("--bitrate").flatMap(Int.init) ?? 8_000_000,
                poster: value("--poster").map { URL(fileURLWithPath: $0) }
            ) { done in
                FileHandle.standardError.write(Data(String(format: "\rrendering %3.0f%%", done * 100).utf8))
            }
            FileHandle.standardError.write(Data("\n".utf8))
            return ok ? 0 : 1
        }

        if let path = value("--icon") {
            guard let image = BrandArt.icon(), Snapshot.write(image, to: URL(fileURLWithPath: path)) else {
                FileHandle.standardError.write(Data("could not render the icon\n".utf8))
                return 1
            }
            return 0
        }

        if let path = value("--dmg-background") {
            let scale = value("--scale").flatMap(Double.init) ?? 1
            guard let image = BrandArt.diskImageBackground(scale: CGFloat(scale)),
                  Snapshot.write(image, to: URL(fileURLWithPath: path)) else {
                FileHandle.standardError.write(Data("could not render the disk image background\n".utf8))
                return 1
            }
            return 0
        }

        guard let path = value("--snapshot") else { return 64 }
        var options = Snapshot.Options()
        if let width = value("--width").flatMap(Double.init), let height = value("--height").flatMap(Double.init) {
            options.size = CGSize(width: width, height: height)
        }
        if let scale = value("--scale").flatMap(Double.init) { options.scale = CGFloat(scale) }
        if let seconds = value("--seconds").flatMap(Double.init) { options.seconds = seconds }
        if let lead = value("--lead").flatMap(Double.init) { options.lead = lead }
        if let preset = value("--preset"), let match = Preset.all.first(where: { $0.id == preset }) {
            match.apply(&options.config)
        }
        if let style = value("--style").flatMap(BulbStyle.init(rawValue:)) { options.config.bulbStyle = style }
        if let palette = value("--palette").flatMap(LightPalette.init(rawValue:)) { options.config.palette = palette }
        if let pattern = value("--pattern").flatMap(LightPattern.init(rawValue:)) { options.config.pattern = pattern }
        if let depth = value("--accumulation").flatMap(Accumulation.init(rawValue:)) { options.config.accumulation = depth }
        if let intensity = value("--intensity").flatMap(Double.init) { options.config.snowIntensity = intensity }
        if let surprise = value("--surprise").flatMap(SurpriseKind.init(rawValue:)) { options.surprise = surprise }
        if let layering = value("--layering").flatMap(SnowLayering.init(rawValue:)) { options.config.snowLayering = layering }
        // --stroke x1,y1,x2,y2,...: a pointer path in points, for wiping frost.
        if let numbers = value("--stroke")?.split(separator: ",").compactMap({ Double($0) }), numbers.count >= 4 {
            options.stroke = stride(from: 0, to: numbers.count - 1, by: 2).map { CGPoint(x: numbers[$0], y: numbers[$0 + 1]) }
        }
        if arguments.contains("--bottom") { options.config.edgeBottom = true }
        if arguments.contains("--top-only") {
            options.config.edgeLeft = false
            options.config.edgeRight = false
        }
        if arguments.contains("--no-snow") { options.config.snowEnabled = false }
        if arguments.contains("--no-lights") { options.config.lightsEnabled = false }
        if arguments.contains("--light-windows") { options.darkWindows = false }
        if arguments.contains("--transparent") { options.transparent = true }
        if arguments.contains("--no-menu-bar") { options.topInset = 0 }
        options.windows = arguments.contains("--no-windows") ? [] : Snapshot.defaultWindows(for: options.size)

        guard var image = Snapshot.render(options) else {
            FileHandle.standardError.write(Data("could not render the snapshot\n".utf8))
            return 1
        }
        // --crop x,y,w,h in points.
        if let crop = value("--crop")?.split(separator: ",").compactMap({ Double($0) }), crop.count == 4 {
            let k = Double(options.scale)
            let rect = CGRect(x: crop[0] * k, y: crop[1] * k, width: crop[2] * k, height: crop[3] * k)
            if let cropped = image.cropping(to: rect) { image = cropped }
        }
        guard Snapshot.write(image, to: URL(fileURLWithPath: path)) else {
            FileHandle.standardError.write(Data("could not render the snapshot\n".utf8))
            return 1
        }
        return 0
    }
}
