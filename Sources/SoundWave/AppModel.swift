import AppKit
import AVFoundation
import Combine
import SoundWaveCore

@MainActor final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published var running = false
    @Published var starting = false
    @Published var controlEnabled = false {
        didSet {
            emitter.reset()
            if oldValue && !controlEnabled { requestedControl = false }
        }
    }
    @Published var accessible = AXIsProcessTrusted()
    @Published var eventPostingGranted = CGPreflightPostEventAccess()
    @Published var microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @Published var mode: ActionMode = .scroll { didSet { emitter.reset(); UserDefaults.standard.set(mode.rawValue, forKey: "mode") } }
    @Published var frequency = 20000.0
    @Published var amplitude = 0.12
    @Published var sensitivity = 0.5
    @Published var speed = 650.0
    @Published var reversed = false
    @Published var calibration = 0.0
    @Published var signalGood = false
    @Published var signalDB = -120.0
    @Published var motion = 0.0
    @Published var shiftHz = 0.0
    @Published var spectrum: [Double] = []
    @Published var message = "Ready when you are. Start sensing to check your Mac’s signal."
    @Published var devices = "Built-in microphone + speakers"
    @Published var testCountdown = 0
    @Published var controlMessage = ""
    private let sensor = AudioSensor()
    private let emitter = ActionEmitter()
    private var session = UUID()
    private var lastDetection = 0.0
    private var startedAt = 0.0
    private var timer: Timer?
    private var sleepObserver: NSObjectProtocol?
    private var requestedControl = false
    private var testTask: Task<Void, Never>?
    private var motionDetections = 0

    init() {
        if let saved = UserDefaults.standard.string(forKey: "mode"), let value = ActionMode(rawValue: saved) { mode = value }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkStatus() }
        }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stop(); self?.message = "Paused for sleep. Start sensing when you’re ready." }
        }
        if ProcessInfo.processInfo.arguments.contains("--resume-control") {
            DispatchQueue.main.async { [weak self] in self?.start(enableControl: true) }
        }
    }

    var ready: Bool { running && calibration >= 1 && signalGood }
    var controlAccess: ControlAccess { ControlAccess(accessibilityGranted: accessible, eventPostingGranted: eventPostingGranted) }
    var canControl: Bool { controlAccess == .ready }
    var needsPermissionRestart: Bool { controlAccess == .restartNeeded }
    var status: String {
        if starting { return "Requesting microphone" }
        if !running { return "Paused" }
        if !signalGood { return "Looking for tone" }
        if calibration < 1 { return "Calibrating" }
        if !accessible { return "Accessibility needed" }
        if !eventPostingGranted { return "Restart to apply permission" }
        return controlEnabled ? "Gesture control on" : "Ready · control is off"
    }

    func start(enableControl: Bool = false) {
        guard !starting else { return }
        stop()
        requestedControl = enableControl
        starting = true
        let token = session
        Task {
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard session == token else { return }
            microphone = allowed
            starting = false
            guard allowed else {
                message = "Allow SoundWave in System Settings → Privacy & Security → Microphone, then start again."
                return
            }
            if enableControl && !canControl { requestAccessibility() }
            do {
                devices = try sensor.start(frequency: frequency, amplitude: amplitude, sensitivity: sensitivity,
                    onDetection: { [weak self] detection in
                        let captured = ProcessInfo.processInfo.systemUptime
                        DispatchQueue.main.async {
                            guard let self, self.session == token, self.running,
                                  ProcessInfo.processInfo.systemUptime - captured < 0.2 else { return }
                            self.receive(detection, at: captured)
                        }
                    }, onChange: { [weak self] in
                        Task { @MainActor in
                            guard let self, self.session == token else { return }
                            self.stop()
                            self.message = "Audio devices changed. Start again to recalibrate."
                        }
                    })
                running = true
                startedAt = ProcessInfo.processInfo.systemUptime
                lastDetection = startedAt
                message = "Keep your hands still for calibration (about 3 seconds)."
            } catch { message = error.localizedDescription; sensor.stop() }
        }
    }

    func stop() {
        session = UUID()
        sensor.stop()
        emitter.reset()
        running = false
        starting = false
        controlEnabled = false
        requestedControl = false
        testTask?.cancel()
        testTask = nil
        testCountdown = 0
        motion = 0
        shiftHz = 0
        calibration = 0
        signalGood = false
        spectrum = []
        message = "Sensing paused. Microphone and tone are off."
    }

    func toggleControl() {
        if controlEnabled { controlEnabled = false }
        else if ready && canControl { controlEnabled = true }
    }

    func testAction() {
        guard canControl else {
            controlMessage = needsPermissionRestart ? "Permission is enabled. Restart SoundWave to apply it before testing." : "Allow SoundWave in Accessibility before testing Mac control."
            requestAccessibility()
            return
        }
        controlEnabled = false
        requestedControl = false
        testTask?.cancel()
        let selectedMode = mode
        let reverse = reversed
        testTask = Task {
            for remaining in stride(from: 5, through: 1, by: -1) {
                testCountdown = remaining
                controlMessage = selectedMode == .spaces ? "Testing the next desktop in \(remaining)s…" : "Click your PDF or target app and place the pointer over its content. Test in \(remaining)s…"
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
            }
            guard !Task.isCancelled else { return }
            testCountdown = 0
            guard selectedMode == .spaces || NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier else {
                controlMessage = "Test cancelled: switch to your PDF or target app during the countdown."
                return
            }
            let sent = emitter.test(mode: selectedMode, reversed: reverse)
            controlMessage = sent ? "Test sent. If the page or desktop moved, Mac control works. Enable gesture control to use your hand." : "macOS blocked this test. Restart SoundWave to refresh permission."
        }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        accessible = AXIsProcessTrustedWithOptions(options)
        if accessible {
            eventPostingGranted = CGRequestPostEventAccess()
            if !eventPostingGranted { controlMessage = "Accessibility is enabled. Restart SoundWave to apply the permission." }
        } else { openSettings("Privacy_Accessibility") }
    }

    func restartForPermission() {
        let resume = requestedControl || controlEnabled
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        var args = Array(ProcessInfo.processInfo.arguments.dropFirst())
        if resume && !args.contains("--resume-control") { args.append("--resume-control") }
        configuration.arguments = args
        stop()
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error { self.controlMessage = "Couldn’t restart: \(error.localizedDescription)" }
                else { NSApp.terminate(nil) }
            }
        }
    }

    func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }

    private func receive(_ detection: Detection, at time: Double) {
        lastDetection = time
        calibration = detection.calibration
        signalDB = detection.signalDB
        signalGood = detection.signalGood
        motion = detection.motion
        shiftHz = detection.shiftHz
        spectrum = detection.spectrum
        if detection.motion != 0 { motionDetections += 1 }
        if !signalGood {
            message = "Tone is weak. Check speaker volume; try 19 kHz or a higher tone level, then recalibrate."
        } else if calibration < 1 {
            message = "Keep your hands still while the room’s background signal is measured."
        } else {
            message = "Hold an open palm 15–40 cm above the keyboard. Move toward or away from the Mac."
        }
        if ready && requestedControl && canControl && !controlEnabled { controlEnabled = true }
        guard ready, controlEnabled, canControl else { emitter.reset(); return }
        emitter.update(motion: detection.motion, now: time, mode: mode, speed: speed, reversed: reversed)
    }

    private func checkStatus() {
        defer { writeDiagnosticsIfRequested() }
        accessible = AXIsProcessTrusted()
        eventPostingGranted = CGPreflightPostEventAccess()
        microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        if !canControl && controlEnabled { controlEnabled = false }
        guard running else { return }
        if let issue = AudioSensor.outputIssue() {
            stop()
            message = issue
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if !microphone || now - lastDetection > 2 {
            stop()
            message = "Microphone input stopped. Check microphone permission and start again."
        } else if calibration < 1 && now - startedAt > 18 {
            stop()
            message = "Couldn’t calibrate a clear tone. Check Mac speaker volume, lower the frequency to 19 kHz, and try again."
        }
    }

    var diagnostics: [String: Any] {
        ["running": running, "calibration": calibration, "signalGood": signalGood,
         "signalDB": signalDB, "message": message, "microphone": microphone, "devices": devices,
         "accessible": accessible, "canPostEvents": eventPostingGranted,
         "controlEnabled": controlEnabled, "mode": mode.rawValue, "status": status,
         "motion": motion, "motionDetections": motionDetections, "postedEvents": emitter.postedEvents,
         "testCountdown": testCountdown, "controlMessage": controlMessage]
    }

    private func writeDiagnosticsIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--diagnostics"), args.indices.contains(index + 1),
              let data = try? JSONSerialization.data(withJSONObject: diagnostics, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: URL(fileURLWithPath: args[index + 1]), options: .atomic)
    }
}
