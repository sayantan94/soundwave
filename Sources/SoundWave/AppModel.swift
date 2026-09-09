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
            if oldValue != controlEnabled { resetInteraction() }
            if oldValue && !controlEnabled { requestedControl = false }
        }
    }
    @Published var accessible = AXIsProcessTrusted()
    @Published var eventPostingGranted = CGPreflightPostEventAccess()
    @Published var microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @Published var mode: ActionMode = .spaces { didSet { resetInteraction(); UserDefaults.standard.set(mode.rawValue, forKey: "mode") } }
    @Published var response: GestureResponse = .responsive { didSet { recognizer.response = response; UserDefaults.standard.set(response.rawValue, forKey: "response") } }
    @Published var feedbackEnabled = true { didSet { UserDefaults.standard.set(feedbackEnabled, forKey: "feedbackEnabled") } }
    @Published var practiceOnly = false
    @Published var practiceToward = 0
    @Published var practiceAway = 0
    @Published var gesturePhase: GesturePhase = .settling
    @Published var gestureProgress = 0.0
    @Published var lastGesture = ""
    @Published var lastDirection = 0
    @Published var frequency = 20000.0
    @Published var amplitude = 0.12
    @Published var sensitivity = 0.5
    @Published var speed = 650.0
    @Published var reversed = false { didSet { resetInteraction(); UserDefaults.standard.set(reversed, forKey: "reversed") } }
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
    private let hud = GestureHUD()
    private var recognizer = GestureRecognizer()
    private var session = UUID()
    private var lastDetection = 0.0
    private var startedAt = 0.0
    private var timer: Timer?
    private var sleepObserver: NSObjectProtocol?
    private var requestedControl = false
    private var testTask: Task<Void, Never>?
    private var motionDetections = 0
    private var lastUIUpdate = 0.0
    private var lastAcceptedAt = -Double.infinity
    private var inputBlockSize = 0
    private var droppedSamples: UInt64 = 0
    private var processedFrames = 0
    private var frameAges: [Double] = []
    private var acceptedGestures = 0
    private var corroboratedFrames = 0
    private var pendingSpaceTime: Double?
    private var confirmedSpaceChanges = 0
    private var lastSpaceChangeMS = 0.0
    private var spaceObserver: NSObjectProtocol?

    init() {
        if let saved = UserDefaults.standard.string(forKey: "mode"), let value = ActionMode(rawValue: saved) { mode = value }
        if let saved = UserDefaults.standard.string(forKey: "response"), let value = GestureResponse(rawValue: saved) { response = value }
        if let saved = UserDefaults.standard.object(forKey: "feedbackEnabled") as? Bool { feedbackEnabled = saved }
        reversed = UserDefaults.standard.bool(forKey: "reversed")
        recognizer.response = response
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkStatus() }
        }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stop(); self?.message = "Paused for sleep. Start sensing when you’re ready." }
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, let requested = self.pendingSpaceTime else { return }
                let elapsed = ProcessInfo.processInfo.systemUptime - requested
                if elapsed < 1.5 { self.confirmedSpaceChanges += 1; self.lastSpaceChangeMS = elapsed * 1000 }
                self.pendingSpaceTime = nil
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--resume-control") {
            DispatchQueue.main.async { [weak self] in self?.start(enableControl: true) }
        }
    }

    var ready: Bool { running && calibration >= 1 && signalGood }
    var controlAccess: ControlAccess { ControlAccess(accessibilityGranted: accessible, eventPostingGranted: eventPostingGranted) }
    var canControl: Bool { controlAccess == .ready }
    var needsPermissionRestart: Bool { controlAccess == .restartNeeded }
    var feedbackTitle: String {
        if starting { return "Getting ready…" }
        if !running { return "Ready when you are." }
        if calibration < 1 { return signalGood ? "Keep your hand still." : "Checking the sound…" }
        if !signalGood { return "Move a little closer." }
        if ProcessInfo.processInfo.systemUptime - lastAcceptedAt < 0.55 { return lastGesture }
        if mode.isContinuous && abs(motion) > 0.15 { return (motion > 0) != reversed ? mode.toward : mode.away }
        switch gesturePhase {
        case .ready: return "Ready for your gesture."
        case .tracking: return "Following your hand…"
        case .cooldown: return "Return your hand."
        case .settling: return "Let your hand settle."
        }
    }
    var feedbackSubtitle: String {
        if !running { return "One deliberate move. One action. No camera." }
        if calibration < 1 { return "Measuring the room. This takes about 3 seconds." }
        if !signalGood { return "Keep your palm near the Mac and check speaker volume." }
        if gesturePhase == .cooldown { return "Your gesture was accepted. Settle briefly, then go again." }
        if practiceOnly { return "Practice freely. Your Mac won’t move until you choose Use gestures." }
        return controlEnabled ? "Palm 15–30 cm above the keyboard. Lower or lift, then settle." : "Sensing is ready. Choose Use gestures to control your Mac."
    }
    var status: String {
        if starting { return "Requesting microphone" }
        if !running { return "Paused" }
        if !signalGood { return "Looking for tone" }
        if calibration < 1 { return "Calibrating" }
        if !accessible { return "Accessibility needed" }
        if !eventPostingGranted { return "Restart to apply permission" }
        if practiceOnly { return "Practice mode" }
        return controlEnabled ? "Gesture control on" : "Ready · control is off"
    }

    func start(enableControl: Bool = false, practice: Bool = false) {
        guard !starting else { return }
        stop()
        practiceOnly = practice
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
                    onDetection: { [weak self] frames in
                        DispatchQueue.main.async {
                            guard let self, self.session == token, self.running else { return }
                            for frame in frames { self.receive(frame) }
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
        resetInteraction()
        hud.hide()
        running = false
        starting = false
        practiceOnly = false
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

    func beginPractice() {
        practiceToward = 0; practiceAway = 0
        if running {
            controlEnabled = false; requestedControl = false; practiceOnly = true; resetInteraction()
        } else { start(practice: true) }
    }

    func useGestures() {
        practiceOnly = false
        requestedControl = true
        if !running { start(enableControl: true); return }
        if !canControl { requestAccessibility() }
        if canControl && ready { controlEnabled = true }
    }

    private func resetInteraction() {
        emitter.reset()
        recognizer = GestureRecognizer(response: response)
        gesturePhase = .settling
        gestureProgress = 0
        lastAcceptedAt = -.infinity
        pendingSpaceTime = nil
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

    private func receive(_ frame: SensorFrame) {
        let time = ProcessInfo.processInfo.systemUptime
        let detection = frame.detection
        let age = time - frame.capturedAt
        let fresh = age >= -0.02 && age < 0.12
        lastDetection = time
        processedFrames += 1
        inputBlockSize = frame.inputBlockSize
        droppedSamples = frame.droppedSamples
        frameAges.append(max(0, age * 1000))
        if frameAges.count > 200 { frameAges.removeFirst(frameAges.count - 200) }
        if detection.motion != 0 { motionDetections += 1 }
        if detection.corroborated { corroboratedFrames += 1 }
        let valid = fresh && detection.signalGood && detection.calibration >= 1
        if valid && requestedControl && canControl && !controlEnabled { controlEnabled = true }
        let gesture = recognizer.update(motion: detection.motion, confidence: detection.confidence, activity: detection.activity,
                                        signalGood: valid, time: frame.capturedAt)
        if gesturePhase != gesture.phase { gesturePhase = gesture.phase }
        if let direction = gesture.acceptedDirection {
            acceptedGestures += 1
            lastDirection = direction
            lastAcceptedAt = time
            lastGesture = (direction > 0) != reversed ? mode.toward : mode.away
            if practiceOnly {
                if direction > 0 { practiceToward += 1 } else { practiceAway += 1 }
            } else if controlEnabled && canControl && !mode.isContinuous {
                if emitter.emitGesture(mode: mode, direction: direction, reversed: reversed) {
                    if mode == .spaces { pendingSpaceTime = time }
                    if feedbackEnabled { hud.show(title: lastGesture, symbol: (direction > 0) != reversed ? "arrow.right" : "arrow.left") }
                }
            }
        }
        if mode.isContinuous && controlEnabled && canControl {
            emitter.update(motion: valid ? detection.motion : 0, now: frame.capturedAt, mode: mode, speed: speed, reversed: reversed)
        }
        // Gesture decisions use every frame. SwiftUI/spectrum redraws are capped at 30 Hz.
        if time - lastUIUpdate >= 1.0 / 30 {
            lastUIUpdate = time
            calibration = detection.calibration
            signalDB = detection.signalDB
            signalGood = detection.signalGood && fresh
            motion = detection.motion
            shiftHz = detection.shiftHz
            spectrum = detection.spectrum
            gestureProgress = gesture.progress
            if !fresh { message = "Audio processing fell behind. Hold still while it catches up." }
            else if !signalGood { message = "Tone is weak. Move closer or try 19 kHz in Settings." }
            else if calibration < 1 { message = "Keep your hand still while the room is measured." }
            else { message = "Sound is clear. One gesture is accepted at a time." }
        }
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
        let ages = frameAges.sorted()
        return ["running": running, "calibration": calibration, "signalGood": signalGood,
         "signalDB": signalDB, "message": message, "microphone": microphone, "devices": devices,
         "accessible": accessible, "canPostEvents": eventPostingGranted,
         "controlEnabled": controlEnabled, "mode": mode.rawValue, "status": status,
         "motion": motion, "motionDetections": motionDetections, "postedEvents": emitter.postedEvents,
         "testCountdown": testCountdown, "controlMessage": controlMessage,
         "gesturePhase": gesturePhase.rawValue, "response": response.rawValue,
         "acceptedGestures": acceptedGestures, "lastDirection": lastDirection, "lastGesture": lastGesture,
         "corroboratedFrames": corroboratedFrames, "frequency": frequency,
         "companionFrequency": CorroboratedDetector.companion(for: frequency),
         "reversed": reversed, "practiceToward": practiceToward, "practiceAway": practiceAway, "inputBlockFrames": inputBlockSize,
         "droppedSamples": droppedSamples, "processedFrames": processedFrames,
         "frameAgeMedianMS": ages.isEmpty ? 0 : ages[ages.count / 2],
         "frameAgeP95MS": ages.isEmpty ? 0 : ages[min(ages.count - 1, Int(Double(ages.count) * 0.95))],
         "confirmedSpaceChanges": confirmedSpaceChanges, "lastSpaceChangeMS": lastSpaceChangeMS]
    }

    private func writeDiagnosticsIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--diagnostics"), args.indices.contains(index + 1),
              let data = try? JSONSerialization.data(withJSONObject: diagnostics, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: URL(fileURLWithPath: args[index + 1]), options: .atomic)
    }
}
