import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var settings: Settings

    var body: some View {
        TabView {
            SnowSettings(settings: settings)
                .tabItem { Label("Snow", systemImage: "snowflake") }
            LightSettings(settings: settings)
                .tabItem { Label("Lights", systemImage: "lightbulb.max") }
            SurpriseSettings(settings: settings)
                .tabItem { Label("Surprises", systemImage: "gift") }
            GeneralSettings(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 540, height: 560)
    }
}

/// A slider with a title and words at each end.
private struct RangeRow: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var low: String
    var high: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            Slider(value: $value, in: range) {
                Text(title)
            } minimumValueLabel: {
                Text(low).font(.caption).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text(high).font(.caption).foregroundStyle(.secondary)
            }
            .labelsHidden()
        }
    }
}

private struct SnowSettings: View {
    @ObservedObject var settings: Settings

    var body: some View {
        Form {
            Section {
                Toggle("Let it snow", isOn: $settings.config.snowEnabled)
            }
            Section("Snowfall") {
                RangeRow(title: "Amount", value: $settings.config.snowIntensity, range: 0.03...1,
                         low: "Flurries", high: "Blizzard")
                RangeRow(title: "Flake size", value: $settings.config.flakeSize, range: 0.6...1.6,
                         low: "Fine", high: "Fat")
                RangeRow(title: "Wind", value: $settings.config.wind, range: 0...1,
                         low: "Still", high: "Gusty")
            }
            .disabled(!settings.config.snowEnabled)
            Section {
                Picker("Snow on windows", selection: $settings.config.accumulation) {
                    ForEach(Accumulation.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Snow on the ground", isOn: $settings.config.groundSnow)
                    .disabled(settings.config.accumulation == .off)
            } header: {
                Text("Settling")
            } footer: {
                Text("Snow piles up along the top of your windows. Drag a window and its snow slides off; close it and the snow drops.")
            }
            .disabled(!settings.config.snowEnabled)
            Section {
                Toggle("Distant snow falls behind windows", isOn: $settings.config.depthBehindWindows)
                Toggle("Snow swirls around the pointer", isOn: $settings.config.cursorPlay)
            } header: {
                Text("Depth")
            } footer: {
                Text("Griswold only reads where windows are, never what is in them. It needs no permissions.")
            }
            .disabled(!settings.config.snowEnabled)
        }
        .formStyle(.grouped)
    }
}

private struct LightSettings: View {
    @ObservedObject var settings: Settings

    private var customColor: Binding<Color> {
        Binding(
            get: {
                let c = Palettes.color(hex: settings.config.customColorHex) ?? SIMD3(1, 0.27, 0.23)
                return Color(red: Double(c.x), green: Double(c.y), blue: Double(c.z))
            },
            set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                settings.config.customColorHex = String(
                    format: "%02X%02X%02X",
                    Int((rgb.redComponent * 255).rounded()),
                    Int((rgb.greenComponent * 255).rounded()),
                    Int((rgb.blueComponent * 255).rounded())
                )
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("Hang the lights", isOn: $settings.config.lightsEnabled)
                BulbStrip(palette: settings.config.palette, customHex: settings.config.customColorHex,
                          lit: settings.config.lightsEnabled)
            }
            Section("Bulbs") {
                Picker("Style", selection: $settings.config.bulbStyle) {
                    ForEach(BulbStyle.allCases) { Text($0.title).tag($0) }
                }
                Picker("Colors", selection: $settings.config.palette) {
                    ForEach(LightPalette.allCases) { Text($0.title).tag($0) }
                }
                if settings.config.palette == .custom {
                    ColorPicker("Custom color", selection: customColor, supportsOpacity: false)
                }
                RangeRow(title: "Size", value: $settings.config.bulbScale, range: 0.7...1.6, low: "Small", high: "Large")
                RangeRow(title: "Spacing", value: $settings.config.spacing, range: 0.6...1.8, low: "Tight", high: "Loose")
            }
            .disabled(!settings.config.lightsEnabled)
            Section("Animation") {
                Picker("Pattern", selection: $settings.config.pattern) {
                    ForEach(LightPattern.allCases) { Text($0.title).tag($0) }
                }
                RangeRow(title: "Speed", value: $settings.config.lightSpeed, range: 0...1, low: "Slow", high: "Fast")
                RangeRow(title: "Brightness", value: $settings.config.brightness, range: 0.3...1, low: "Dim", high: "Bright")
                RangeRow(title: "Glow", value: $settings.config.glow, range: 0...1, low: "None", high: "Lots")
            }
            .disabled(!settings.config.lightsEnabled)
            Section("Where") {
                LabeledContent("Edges") {
                    HStack(spacing: 6) {
                        Toggle("Top", isOn: $settings.config.edgeTop)
                        Toggle("Left", isOn: $settings.config.edgeLeft)
                        Toggle("Right", isOn: $settings.config.edgeRight)
                        Toggle("Bottom", isOn: $settings.config.edgeBottom)
                    }
                    .toggleStyle(.button)
                }
                Toggle("Hang below the menu bar", isOn: $settings.config.belowMenuBar)
                    .disabled(!settings.config.edgeTop)
            }
            .disabled(!settings.config.lightsEnabled)
        }
        .formStyle(.grouped)
    }
}

private struct SurpriseSettings: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var settings: Settings

    private func enabled(_ kind: SurpriseKind) -> Binding<Bool> {
        Binding(
            get: { settings.config.isSurpriseEnabled(kind) },
            set: { settings.config.setSurprise(kind, enabled: $0) }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Surprises happen", selection: $settings.config.surpriseFrequency) {
                    ForEach(SurpriseFrequency.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Every so often something happens on its own. They come more often on Christmas Eve and Christmas Day.")
            }
            Section("What can happen") {
                ForEach(SurpriseKind.allCases) { kind in
                    HStack {
                        Toggle(isOn: enabled(kind)) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(kind.title)
                                if let note = SurpriseSettings.note(for: kind) {
                                    Text(note).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer()
                        Button("Play") { model.surprise(kind) }
                            .controlSize(.small)
                            .accessibilityLabel("Play \(kind.title)")
                    }
                }
            }
            Section("Sound") {
                Toggle("Play sounds", isOn: $settings.config.soundEnabled)
                if settings.config.soundEnabled {
                    RangeRow(title: "Volume", value: $settings.config.volume, range: 0.05...1, low: "Quiet", high: "Loud")
                }
            }
        }
        .formStyle(.grouped)
    }

    static func note(for kind: SurpriseKind) -> String? {
        switch kind {
        case .griswold: return "The lights die, then come back with everything they have."
        case .gust: return "Needs snow."
        case .fireworks: return "On its own only on New Year's Eve and New Year's Day."
        case .santa: return "Flies across every display."
        default: return nil
        }
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var settings: Settings

    var body: some View {
        Form {
            Section {
                Toggle("Open Griswold at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                if let error = model.loginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Section {
                Picker("Frame rate", selection: $settings.config.frameRate) {
                    ForEach(FrameRateMode.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Show over full-screen apps", isOn: $settings.config.showOverFullscreen)
                Toggle("Main display only", isOn: $settings.config.mainDisplayOnly)
            } header: {
                Text("Performance")
            } footer: {
                Text("Automatic runs at 60 fps on power and 30 on battery or in Low Power Mode. Griswold stops drawing when the display sleeps, the screen locks, or nothing is moving.")
            }
            Section("Presets") {
                ForEach(Preset.all) { preset in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(preset.title)
                            Text(preset.blurb).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Use") { settings.apply(preset) }
                            .controlSize(.small)
                            .accessibilityLabel("Use \(preset.title)")
                    }
                }
            }
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $settings.config.checkForUpdates)
                HStack {
                    Button("Check Now") { model.checkForUpdates(userInitiated: true) }
                    if let status = model.updateStatus {
                        Text(status).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.update != nil {
                        Button("Download") { model.openDownloadPage() }
                    }
                }
            }
            Section {
                Button("Reset All Settings") { settings.resetToDefaults() }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutView: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)
            Text("Griswold")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text("Version \(UpdateChecker.currentVersion)")
                .foregroundStyle(.secondary)
            Text("Snow, lights and the occasional sleigh, for your Mac.\nFree. No accounts, no tracking, no permissions.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Link("chonkbase.net/griswold", destination: UpdateChecker.homepage)
            Spacer()
            Text("Made with too many extension cords.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
