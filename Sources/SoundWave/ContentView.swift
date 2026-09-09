import SwiftUI
import SoundWaveCore

private let mint = Color(red: 0.54, green: 0.96, blue: 0.79)
private let surface = Color(red: 0.075, green: 0.09, blue: 0.10)

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var settingsExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path").font(.system(size: 25)).foregroundStyle(mint)
                    Text("soundwave").font(.system(size: 23, weight: .semibold, design: .rounded))
                    Spacer()
                    Circle().fill(model.controlEnabled ? mint : .gray).frame(width: 6, height: 6)
                    Text(model.status).font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(.bottom, 6)

                if !model.canControl && !model.practiceOnly {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "lock.open").foregroundStyle(mint).padding(.top, 3)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.needsPermissionRestart ? "One restart to finish setup." : "Allow SoundWave to control your Mac.")
                                .font(.system(size: 14, weight: .semibold))
                            Text(model.needsPermissionRestart ? "Your permission is enabled. Restart once to apply it." : "Enable SoundWave in System Settings → Privacy & Security → Accessibility.")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                            Button(model.needsPermissionRestart ? "Finish setup & restart" : "Open Accessibility settings") {
                                model.needsPermissionRestart ? model.restartForPermission() : model.requestAccessibility()
                            }.buttonStyle(.bordered).controlSize(.small)
                        }
                        Spacer(minLength: 0)
                    }.padding(16).background(mint.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                }

                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Text("CONTROL").font(.system(size: 10, weight: .medium)).tracking(1.5).foregroundStyle(.secondary)
                        Picker("Action", selection: $model.mode) {
                            ForEach(ActionMode.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                        }.labelsHidden().controlSize(.large).frame(maxWidth: 245)
                        Spacer()
                        if model.practiceOnly {
                            Text("PRACTICE").font(.system(size: 10, weight: .semibold)).foregroundStyle(mint)
                                .padding(.horizontal, 10).padding(.vertical, 6).background(mint.opacity(0.09), in: Capsule())
                        }
                    }
                    HStack(spacing: 25) {
                        GestureDial(phase: model.gesturePhase, progress: model.gestureProgress, motion: model.motion,
                                    running: model.running, calibrated: model.calibration >= 1)
                            .frame(width: 132, height: 132)
                        VStack(alignment: .leading, spacing: 9) {
                            Text(model.feedbackTitle).font(.system(size: 29, weight: .medium)).tracking(-0.8)
                                .contentTransition(.opacity)
                            Text(model.feedbackSubtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true).frame(minHeight: 35, alignment: .topLeading)
                            if model.running && model.calibration < 1 {
                                ProgressView(value: model.calibration).tint(mint).frame(maxWidth: 220)
                            }
                        }
                        Spacer(minLength: 0)
                    }.padding(.vertical, 4)
                    HStack(spacing: 12) {
                        mapping(toward: true)
                        mapping(toward: false)
                    }
                    HStack {
                        Text("Move closer to the keyboard or away from it.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Swap directions") { model.reversed.toggle() }
                            .buttonStyle(.plain).foregroundStyle(mint).font(.system(size: 11, weight: .medium))
                    }
                    HStack(spacing: 10) {
                        Button(action: primaryAction) {
                            Label(primaryLabel, systemImage: model.practiceOnly && model.running ? "play.fill" : model.running ? "pause.fill" : "waveform")
                                .font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 9)
                        }.buttonStyle(.borderedProminent).tint(mint).foregroundStyle(.black)
                        Button(model.practiceOnly && model.running ? "End practice" : "Practice first") {
                            model.practiceOnly && model.running ? model.stop() : model.beginPractice()
                        }.buttonStyle(.bordered).controlSize(.large).disabled(model.starting)
                    }
                    if !model.running && model.message != "Ready when you are. Start sensing to check your Mac’s signal." {
                        Text(model.message).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }.padding(24).background(surface, in: RoundedRectangle(cornerRadius: 20))

                HStack(alignment: .center, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Response").font(.system(size: 12, weight: .medium))
                        Picker("Response", selection: $model.response) {
                            ForEach(GestureResponse.allCases) { Text($0.rawValue).tag($0) }
                        }.labelsHidden().pickerStyle(.segmented)
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        Toggle("On-screen confirmation", isOn: $model.feedbackEnabled)
                            .toggleStyle(.switch).controlSize(.small).tint(mint).font(.system(size: 12))
                        Text("Instant feedback without stealing focus.").font(.system(size: 10)).foregroundStyle(.secondary)
                    }.frame(width: 255)
                }.padding(.horizontal, 4)

                DisclosureGroup("Settings & diagnostics", isExpanded: $settingsExpanded) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Button("Recalibrate") { model.start(enableControl: model.controlEnabled, practice: model.practiceOnly) }
                                .disabled(!model.running)
                        }
                        HStack(spacing: 22) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Tone · \(model.frequency / 1000, specifier: "%.1f") kHz")
                                Slider(value: $model.frequency, in: 18500...20500, step: 250)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Tone level · \(model.amplitude * 100, specifier: "%.0f")%")
                                Slider(value: $model.amplitude, in: 0.02...0.3, step: 0.01)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Sensitivity")
                                Slider(value: $model.sensitivity, in: 0...1)
                            }
                        }.disabled(model.running || model.starting)
                        Text("Pause to adjust audio. Keep speaker volume comfortable; reduce the level if you can hear the tone.")
                            .foregroundStyle(.secondary)
                        if model.mode.isContinuous {
                            HStack {
                                Text("Scroll speed")
                                Slider(value: $model.speed, in: 200...1500)
                                Text("\(model.speed, specifier: "%.0f") px/s").monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                        SpectrumView(values: model.spectrum).frame(height: 90)
                        HStack {
                            Text(model.running ? "Pilot: \(model.signalDB, specifier: "%.0f") dBFS" : "Pilot: —")
                            Spacer()
                            Text(model.devices).foregroundStyle(.secondary).lineLimit(1)
                        }.font(.system(size: 10, design: .monospaced))
                        Text(model.message).foregroundStyle(.secondary)
                        HStack {
                            Label("Microphone", systemImage: model.microphone ? "checkmark.circle.fill" : "circle")
                            Label("Mac control", systemImage: model.canControl ? "checkmark.circle.fill" : "circle")
                            Spacer()
                            Button(model.testCountdown > 0 ? "Test in \(model.testCountdown)s…" : "Test action in 5 seconds") { model.testAction() }
                                .disabled(model.testCountdown > 0)
                        }
                        if !model.controlMessage.isEmpty { Text(model.controlMessage).foregroundStyle(mint) }
                    }.font(.system(size: 11)).tint(mint).padding(.top, 18)
                }.font(.system(size: 12)).tint(.secondary).padding(18)
                    .background(surface, in: RoundedRectangle(cornerRadius: 14))

                HStack {
                    Image(systemName: "lock.shield").foregroundStyle(mint)
                    Text("No camera. Audio stays on your Mac.")
                    Spacer()
                    Text("⌃ ⌥ ⌘ S").foregroundStyle(.primary)
                    Text("Stop anytime")
                }.font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(26)
        }.background(Color(red: 0.035, green: 0.045, blue: 0.05))
    }

    private var primaryLabel: String {
        if model.starting { return "Cancel" }
        if model.practiceOnly && model.running { return "Use gestures" }
        return model.running ? "Pause" : "Start gesture control"
    }
    private func primaryAction() {
        if model.starting { model.stop() }
        else if model.practiceOnly && model.running { model.useGestures() }
        else if model.running { model.stop() }
        else { model.start(enableControl: true) }
    }
    private func mapping(toward: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: toward ? "arrow.down.to.line" : "arrow.up.to.line")
                .font(.system(size: 20)).foregroundStyle(mint).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(toward ? "Lower your palm ↓" : "Lift your palm ↑").font(.system(size: 11)).foregroundStyle(.secondary)
                Text((toward != model.reversed) ? model.mode.toward : model.mode.away).font(.system(size: 14, weight: .medium))
            }
            Spacer(minLength: 0)
            if model.practiceOnly {
                Text("\(toward ? model.practiceToward : model.practiceAway)").font(.system(size: 20, weight: .medium, design: .rounded)).foregroundStyle(mint)
            }
        }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct GestureDial: View {
    let phase: GesturePhase
    let progress: Double
    let motion: Double
    let running: Bool
    let calibrated: Bool
    var body: some View {
        ZStack {
            Circle().fill(mint.opacity(0.045))
            Circle().strokeBorder(mint.opacity(0.12), lineWidth: 1)
            Circle().trim(from: 0, to: phase == .cooldown ? 1 : max(0.02, progress))
                .stroke(mint.opacity(running && calibrated ? 0.8 : 0.12), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: phase == .cooldown && running ? "checkmark" : "hand.raised.fingers.spread.fill")
                .font(.system(size: phase == .cooldown ? 37 : 48, weight: .light)).foregroundStyle(mint)
                .offset(y: phase == .cooldown ? 0 : -motion * 8)
        }.animation(.easeOut(duration: 0.08), value: phase)
            .accessibilityLabel(phase.rawValue)
    }
}

struct SpectrumView: View {
    let values: [Double]
    var body: some View {
        Canvas { context, size in
            for i in 0...3 {
                var line = Path()
                let y = size.height * Double(i) / 3
                line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(.white.opacity(0.05)), lineWidth: 1)
            }
            guard values.count > 1 else { return }
            var path = Path()
            for (i, value) in values.enumerated() {
                let p = CGPoint(x: Double(i) / Double(values.count - 1) * size.width, y: (1 - value) * size.height)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            context.stroke(path, with: .color(mint), lineWidth: 1.5)
        }.accessibilityLabel("Live frequency spectrum")
    }
}
