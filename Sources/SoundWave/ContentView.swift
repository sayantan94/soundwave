import SwiftUI

private let mint = Color(red: 0.54, green: 0.96, blue: 0.79)
private let surface = Color(red: 0.075, green: 0.09, blue: 0.10)

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    Image(systemName: "waveform.path").font(.system(size: 29)).foregroundStyle(mint)
                    Text("soundwave").font(.system(size: 24, weight: .semibold, design: .rounded))
                    Spacer()
                    Text("AUDIO GESTURE LAB").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(.secondary)
                    Text("EXPERIMENTAL").font(.system(size: 9, weight: .semibold)).padding(.horizontal, 9).padding(.vertical, 6)
                        .background(.white.opacity(0.07), in: Capsule())
                }
                if !model.canControl {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(model.needsPermissionRestart ? "Permission granted — restart SoundWave to apply it" : "Mac control needs Accessibility permission", systemImage: "lock.fill")
                            .font(.system(size: 15, weight: .semibold))
                        Text(model.needsPermissionRestart ? "macOS has enabled Accessibility, but this running process still has an old event-posting denial. Restart once to refresh it." : "Enable SoundWave in System Settings → Privacy & Security → Accessibility.")
                            .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            if model.needsPermissionRestart {
                                Button("Apply permission & restart") { model.restartForPermission() }
                                    .buttonStyle(.borderedProminent).tint(mint).foregroundStyle(.black)
                            } else {
                                Button("Open Accessibility settings") { model.requestAccessibility() }
                                    .buttonStyle(.borderedProminent).tint(mint).foregroundStyle(.black)
                                Button("Show app to add") {
                                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                                }.buttonStyle(.bordered)
                            }
                        }
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(mint.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                }
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("A little motion.\nA new way to navigate.").font(.system(size: 36, weight: .medium)).tracking(-1)
                        Text("Your Mac’s speakers + microphone. No camera. No wearable.")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "hand.raised.fingers.spread.fill")
                        .font(.system(size: 66, weight: .ultraLight)).foregroundStyle(mint.opacity(0.85))
                        .rotationEffect(.degrees(model.motion * 12))
                        .padding(24).background(mint.opacity(0.05), in: Circle())
                }
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            label("01", "LIVE SIGNAL")
                            Spacer()
                            Circle().fill(model.ready ? mint : .gray).frame(width: 6, height: 6)
                            Text(model.status).font(.system(size: 11)).foregroundStyle(model.ready ? mint : .secondary)
                        }
                        SpectrumView(values: model.spectrum).frame(height: 135)
                        HStack {
                            Text("AWAY  ←").foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1f kHz", model.frequency / 1000)).foregroundStyle(mint)
                            Spacer()
                            Text("→  TOWARD").foregroundStyle(.secondary)
                        }.font(.system(size: 10, design: .monospaced))
                        Divider().overlay(.white.opacity(0.03))
                        HStack {
                            metric("TONE", model.running ? String(format: "%.0f dBFS", model.signalDB) : "—")
                            Spacer()
                            metric("MOTION", abs(model.motion) > 0 ? (model.motion > 0 ? "Toward" : "Away") : "Still")
                            Spacer()
                            metric("DOPPLER SHIFT", abs(model.shiftHz) > 0 ? String(format: "%+.0f Hz", model.shiftHz) : "—")
                        }
                        if model.running && model.calibration < 1 {
                            ProgressView(value: model.calibration).tint(mint)
                        }
                        Text(model.message).font(.system(size: 12)).foregroundStyle(.secondary).frame(minHeight: 36, alignment: .topLeading)
                        HStack(spacing: 10) {
                            Button { model.running || model.starting ? model.stop() : model.start(enableControl: true) } label: {
                                Label(model.running || model.starting ? "Stop sensing" : "Start gesture control", systemImage: model.running ? "stop.fill" : "waveform")
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                            }.buttonStyle(.borderedProminent).tint(mint).foregroundStyle(.black)
                            if model.running {
                                Button("Recalibrate") { model.start(enableControl: model.controlEnabled) }.buttonStyle(.bordered).controlSize(.large)
                            } else if !model.starting {
                                Button("Preview only") { model.start() }.buttonStyle(.bordered).controlSize(.large)
                            }
                        }
                    }.padding(22).background(surface, in: RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 18) {
                        label("02", "CHOOSE AN ACTION")
                        Picker("Gesture action", selection: $model.mode) {
                            ForEach(ActionMode.allCases) { mode in Label(mode.rawValue, systemImage: mode.symbol).tag(mode) }
                        }.labelsHidden().controlSize(.large)
                        gesture("arrow.down.to.line", "Palm toward Mac", model.reversed ? model.mode.away : model.mode.toward)
                        gesture("arrow.up.to.line", "Palm away from Mac", model.reversed ? model.mode.toward : model.mode.away)
                        Text(model.mode.note).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Divider()
                        Toggle("Reverse direction", isOn: $model.reversed).font(.system(size: 12)).toggleStyle(.switch).controlSize(.small)
                        if model.canControl {
                            Toggle("Control my Mac", isOn: $model.controlEnabled).toggleStyle(.switch).tint(mint)
                                .disabled(!model.ready)
                        } else if model.needsPermissionRestart {
                            Button("Apply permission & restart") { model.restartForPermission() }
                                .buttonStyle(.bordered).controlSize(.small)
                        } else {
                            Button("Allow Accessibility for Mac control") { model.requestAccessibility() }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                        Text(model.controlEnabled ? "Control is on. Switch to your PDF or target app to use gestures." : "Start gesture control to calibrate and enable actions. Preview only checks the signal.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Button(model.testCountdown > 0 ? "Test in \(model.testCountdown)s…" : "Test action in 5 seconds") { model.testAction() }
                            .disabled(model.testCountdown > 0).buttonStyle(.bordered).controlSize(.small)
                        if !model.controlMessage.isEmpty {
                            Text(model.controlMessage).font(.system(size: 11)).foregroundStyle(mint)
                        }
                    }.padding(22).frame(width: 275).background(surface, in: RoundedRectangle(cornerRadius: 18))
                }
                HStack(alignment: .top, spacing: 22) {
                    VStack(alignment: .leading, spacing: 12) {
                        label("03", "TUNE YOUR SETUP")
                        HStack(spacing: 22) {
                            VStack(alignment: .leading) {
                                Text("Frequency · \(model.frequency / 1000, specifier: "%.1f") kHz")
                                Slider(value: $model.frequency, in: 18500...20500, step: 250)
                            }
                            VStack(alignment: .leading) {
                                Text("Tone level · \(model.amplitude * 100, specifier: "%.0f")%")
                                Slider(value: $model.amplitude, in: 0.02...0.3, step: 0.01)
                            }
                            VStack(alignment: .leading) {
                                Text("Sensitivity")
                                Slider(value: $model.sensitivity, in: 0...1)
                            }
                        }.disabled(model.running || model.starting)
                        HStack {
                            Text("Scroll speed")
                            Slider(value: $model.speed, in: 200...1500).frame(maxWidth: 180)
                            Text("\(model.speed, specifier: "%.0f") px/s").foregroundStyle(.secondary)
                        }
                        Text("Stop sensing to adjust the tone. Start with moderate Mac volume. If you hear the tone or find it uncomfortable, stop or lower the level.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }.font(.system(size: 11)).tint(mint)
                    VStack(alignment: .leading, spacing: 12) {
                        label("04", "PERMISSIONS")
                        permission("Microphone", granted: model.microphone) { model.openSettings("Privacy_Microphone") }
                        permission("Accessibility", granted: model.accessible) { model.requestAccessibility() }
                        Text("Audio is processed live on your Mac. Nothing is recorded or uploaded.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }.frame(width: 240)
                }.padding(22).background(surface, in: RoundedRectangle(cornerRadius: 18))
                HStack {
                    Image(systemName: "lock.shield").foregroundStyle(mint)
                    Text(model.devices).lineLimit(1)
                    Spacer()
                    Text("⌃ ⌥ ⌘ S").foregroundStyle(.primary)
                    Text("stop from any app")
                }.font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(30)
        }.background(Color(red: 0.035, green: 0.045, blue: 0.05))
    }

    private func label(_ number: String, _ title: String) -> some View {
        HStack(spacing: 8) {
            Text(number).foregroundStyle(mint.opacity(0.7))
            Text(title).foregroundStyle(.secondary).tracking(1.5)
        }.font(.system(size: 10, weight: .medium, design: .monospaced))
    }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 17, weight: .medium, design: .monospaced))
        }
    }
    private func gesture(_ icon: String, _ title: String, _ action: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 19)).foregroundStyle(mint).frame(width: 35, height: 39)
                .background(mint.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
                Text(action).font(.system(size: 14, weight: .medium))
            }
        }
    }
    private func permission(_ title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle").foregroundStyle(granted ? mint : .gray)
            Text(title).font(.system(size: 12))
            Spacer()
            if !granted { Button("Allow", action: action).controlSize(.small) }
        }
    }
}

struct SpectrumView: View {
    let values: [Double]
    var body: some View {
        Canvas { context, size in
            for index in 0...4 {
                let y = size.height * CGFloat(index) / 4
                var line = Path(); line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(.white.opacity(0.05)), lineWidth: 1)
            }
            var center = Path(); center.move(to: CGPoint(x: size.width / 2, y: 0)); center.addLine(to: CGPoint(x: size.width / 2, y: size.height))
            context.stroke(center, with: .color(mint.opacity(0.2)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            guard values.count > 1 else { return }
            var path = Path()
            for (index, value) in values.enumerated() {
                let point = CGPoint(x: Double(index) / Double(values.count - 1) * size.width, y: (1 - value) * (size.height - 6) + 3)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(mint), style: StrokeStyle(lineWidth: 1.7, lineJoin: .round))
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: size.height)); path.closeSubpath()
            context.fill(path, with: .linearGradient(Gradient(colors: [mint.opacity(0.2), mint.opacity(0.01)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        }
        .overlay {
            if values.isEmpty { Text("Your live spectrum will appear here").font(.system(size: 11)).foregroundStyle(.secondary) }
        }
        .accessibilityLabel("Live frequency spectrum around the pilot tone")
    }
}
