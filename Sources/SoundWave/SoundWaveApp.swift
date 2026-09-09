import AppKit
import Carbon
import SwiftUI
import AVFoundation

@main struct SoundWaveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup("SoundWave") {
            ContentView(model: model)
                .onAppear {
                    delegate.model = model
                    DispatchQueue.main.async {
                        delegate.mainWindow = NSApp.windows.first(where: { $0.canBecomeMain })
                        delegate.mainWindow?.isReleasedWhenClosed = false
                    }
                }
                .frame(minWidth: 740, idealWidth: 800, minHeight: 640, idealHeight: 730)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(model.running ? "Stop sensing" : "Start gesture control") { model.running ? model.stop() : model.start(enableControl: true) }
                Button("Toggle gesture control") { model.toggleControl() }.keyboardShortcut("s", modifiers: [.command, .option])
            }
        }
        MenuBarExtra("SoundWave", systemImage: model.controlEnabled ? "waveform.circle.fill" : "waveform.circle") {
            Text(model.status)
            Button("Open SoundWave") { delegate.showWindow() }
            Divider()
            Picker("Action", selection: $model.mode) { ForEach(ActionMode.allCases) { Text($0.rawValue).tag($0) } }
            Button(model.controlEnabled ? "Pause gesture control" : "Enable gesture control") { model.toggleControl() }
                .disabled(!model.ready || !model.canControl)
            if model.needsPermissionRestart {
                Button("Apply permission & restart") { model.restartForPermission() }
            }
            Button(model.running ? "Stop sensing" : "Start gesture control") { model.running ? model.stop() : model.start(enableControl: true) }
            Divider()
            Text("⌃⌥⌘S · Stop sensing")
            Button("Quit SoundWave") { model.stop(); NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
        }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    // Menu-bar launches and restored windows must use the same model even before onAppear.
    weak var model: AppModel? = AppModel.shared
    var mainWindow: NSWindow?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // Render this app's own view for local visual QA, without screen-recording access.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--test-desktop"), arguments.indices.contains(index + 1) {
            let path = arguments[index + 1]
            let emitter = ActionEmitter()
            var changes = 0
            var attempts = 0
            let observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in changes += 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if emitter.test(mode: .spaces, reversed: false) { attempts += 1 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if emitter.test(mode: .spaces, reversed: true) { attempts += 1 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        let report: [String: Any] = ["accessible": AXIsProcessTrusted(), "canPostEvents": CGPreflightPostEventAccess(), "secureInput": IsSecureEventInputEnabled(),
                            "attempts": attempts, "spaceChangesObserved": changes]
                        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                            try? data.write(to: URL(fileURLWithPath: path))
                        }
                        NSWorkspace.shared.notificationCenter.removeObserver(observer)
                        NSApp.terminate(nil)
                    }
                }
            }
            return
        }
        if let index = arguments.firstIndex(of: "--audio-check"), arguments.indices.contains(index + 1) {
            let path = arguments[index + 1]
            var duration = 7.0
            if let option = arguments.firstIndex(of: "--check-duration"), arguments.indices.contains(option + 1),
               let seconds = Double(arguments[option + 1]), seconds.isFinite {
                duration = min(60, max(7, seconds))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let model = self?.model else { NSApp.terminate(nil); return }
                if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized { model.start() }
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                    let report = model.diagnostics
                    if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                        try? data.write(to: URL(fileURLWithPath: path))
                    }
                    model.stop()
                    NSApp.terminate(nil)
                }
            }
            return
        }
        if let index = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(index + 1) {
            let path = arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let view = (self?.mainWindow ?? NSApp.windows.first(where: { $0.canBecomeMain }))?.contentView,
                      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { NSApp.terminate(nil); return }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                NSApp.terminate(nil)
            }
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in delegate.model?.stop() }
            return noErr
        }, 1, &type, pointer, &handler)
        RegisterEventHotKey(UInt32(kVK_ANSI_S), UInt32(controlKey | optionKey | cmdKey),
                            EventHotKeyID(signature: 0x53575645, id: 1), GetApplicationEventTarget(), 0, &hotKey)
    }

    func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = mainWindow ?? NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationWillTerminate(_ notification: Notification) { model?.stop() }
}
