import SwiftUI

/// A rounded panel used to group controls.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.055))
            )
    }
}

/// A row of glowing bulbs drawn in SwiftUI, for headers.
struct BulbStrip: View {
    var palette: LightPalette
    var customHex: String
    var lit: Bool

    var body: some View {
        Canvas { context, size in
            let colours = Palettes.colors(for: palette, customHex: customHex)
            let count = max(Int(size.width / 26), 4)
            var wire = Path()
            wire.move(to: CGPoint(x: 0, y: 2))
            for i in 0..<count {
                let x0 = size.width * CGFloat(i) / CGFloat(count)
                let x1 = size.width * CGFloat(i + 1) / CGFloat(count)
                wire.addQuadCurve(to: CGPoint(x: x1, y: 2), control: CGPoint(x: (x0 + x1) / 2, y: 9))
            }
            context.stroke(wire, with: .color(Color(red: 0.06, green: 0.3, blue: 0.18)), lineWidth: 1.2)
            for i in 0..<count {
                let c = colours[i % colours.count]
                let colour = Color(red: Double(c.x), green: Double(c.y), blue: Double(c.z))
                let x = size.width * (CGFloat(i) + 0.5) / CGFloat(count)
                let bulb = CGRect(x: x - 3.5, y: 6, width: 7, height: 11)
                if lit {
                    context.fill(Path(ellipseIn: bulb.insetBy(dx: -7, dy: -6)), with: .color(colour.opacity(0.22)))
                }
                context.fill(Path(ellipseIn: bulb), with: .color(colour.opacity(lit ? 1 : 0.4)))
            }
        }
        .frame(height: 22)
        .accessibilityHidden(true)
    }
}

struct PopoverView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var settings: Settings

    var body: some View {
        VStack(spacing: 0) {
            BulbStrip(palette: settings.config.palette, customHex: settings.config.customColorHex,
                      lit: settings.config.enabled && settings.config.lightsEnabled)
            header
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 12)
            VStack(spacing: 10) {
                snowCard
                lightsCard
                actions
            }
            .padding(.horizontal, 12)
            .disabled(!settings.config.enabled)
            .opacity(settings.config.enabled ? 1 : 0.45)
            if let update = model.update {
                Button {
                    model.openDownloadPage()
                } label: {
                    Label("Version \(update.version) is available", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .padding(.horizontal, 12)
                .padding(.top, 10)
            }
            Divider().padding(.top, 12)
            footer
        }
        .frame(width: 330)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Griswold")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(AppModel.countdown())
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Griswold", isOn: $settings.config.enabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.large)
        }
    }

    private var snowCard: some View {
        Card {
            Toggle(isOn: $settings.config.snowEnabled) {
                Label("Snow", systemImage: "snowflake").font(.headline)
            }
            .toggleStyle(.switch)
            if settings.config.snowEnabled {
                HStack(spacing: 8) {
                    Image(systemName: "cloud.snow").foregroundStyle(.secondary)
                    Slider(value: $settings.config.snowIntensity, in: 0.03...1)
                        .accessibilityLabel("Snowfall")
                    Image(systemName: "wind.snow").foregroundStyle(.secondary)
                }
                Picker("Piles up", selection: $settings.config.accumulation) {
                    ForEach(Accumulation.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Snow on windows")
            }
        }
    }

    private var lightsCard: some View {
        Card {
            Toggle(isOn: $settings.config.lightsEnabled) {
                Label("Lights", systemImage: "lightbulb.max").font(.headline)
            }
            .toggleStyle(.switch)
            if settings.config.lightsEnabled {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        Text("Bulbs").foregroundStyle(.secondary)
                        Picker("Bulbs", selection: $settings.config.bulbStyle) {
                            ForEach(BulbStyle.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                    }
                    GridRow {
                        Text("Colors").foregroundStyle(.secondary)
                        Picker("Colors", selection: $settings.config.palette) {
                            ForEach(LightPalette.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                    }
                    GridRow {
                        Text("Pattern").foregroundStyle(.secondary)
                        Picker("Pattern", selection: $settings.config.pattern) {
                            ForEach(LightPattern.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                    }
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(Preset.all) { preset in
                    Button {
                        settings.apply(preset)
                    } label: {
                        Text("\(preset.title) — \(preset.blurb)")
                    }
                }
            } label: {
                Label("Presets", systemImage: "wand.and.stars")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.07)))

            Spacer(minLength: 0)

            Menu {
                ForEach(SurpriseKind.allCases) { kind in
                    Button(kind.title) { model.surprise(kind) }
                }
            } label: {
                Label("Surprise Me", systemImage: "gift.fill")
            } primaryAction: {
                model.surprise()
            }
            .menuStyle(.borderedButton)
            .controlSize(.large)
            .fixedSize()
        }
    }

    private var footer: some View {
        HStack {
            Button("Settings…") {
                model.closePopover()
                model.openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
            Spacer()
            Button("Quit Griswold") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
