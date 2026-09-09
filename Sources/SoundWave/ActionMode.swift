import AppKit
import SoundWaveCore

enum ActionMode: String, CaseIterable, Identifiable {
    case scroll = "Scroll vertically"
    case pages = "Turn PDF pages"
    case spaces = "Switch desktops"
    case apps = "Switch apps"
    case horizontal = "Scroll horizontally"
    case zoom = "Zoom in / out"
    var id: String { rawValue }
    var isContinuous: Bool { self == .scroll || self == .horizontal }
    var symbol: String {
        switch self {
        case .scroll: return "arrow.up.arrow.down"
        case .pages: return "doc.richtext"
        case .spaces: return "rectangle.3.group"
        case .apps: return "square.stack.3d.up"
        case .horizontal: return "arrow.left.arrow.right"
        case .zoom: return "plus.magnifyingglass"
        }
    }
    var toward: String {
        switch self {
        case .scroll: return "Scroll down"
        case .pages: return "Next page"
        case .spaces: return "Next desktop"
        case .apps: return "Next app"
        case .horizontal: return "Scroll right"
        case .zoom: return "Zoom in"
        }
    }
    var away: String {
        switch self {
        case .scroll: return "Scroll up"
        case .pages: return "Previous page"
        case .spaces: return "Previous desktop"
        case .apps: return "Previous app"
        case .horizontal: return "Scroll left"
        case .zoom: return "Zoom out"
        }
    }
    var note: String {
        switch self {
        case .scroll: return "Place the pointer over your PDF or page. Push or pull to scroll; return your hand slowly."
        case .pages: return "Sends Page Down / Page Up to the active PDF reader. Pause briefly between gestures."
        case .spaces: return "Push for the next desktop. Pull for the previous one. Let your hand settle before the next gesture."
        case .apps: return "Uses Command–Tab / Command–Shift–Tab. Repeated next gestures toggle recent apps."
        case .horizontal: return "Place the pointer over a wide document, timeline, or horizontally scrollable page."
        case .zoom: return "Sends Command–Plus / Minus. Works in readers and browsers that support these shortcuts."
        }
    }
}

final class ActionEmitter {
    private let keyboardQueue = DispatchQueue(label: "soundwave.keyboard", qos: .userInteractive)
    private(set) var postedEvents = 0
    private var scroller = ScrollController()
    func reset() { scroller.reset() }

    func update(motion: Double, now: Double, mode: ActionMode, speed: Double, reversed: Bool) {
        guard ControlAccess(accessibilityGranted: AXIsProcessTrusted(), eventPostingGranted: CGPreflightPostEventAccess()) == .ready else { reset(); return }
        if mode == .scroll || mode == .horizontal {
            let delta = scroller.update(motion: motion, now: now, enabled: true, speed: speed, reversed: reversed)
            guard delta != 0 else { return }
            scroll(pixels: delta, horizontal: mode == .horizontal)
            return
        }
    }

    @discardableResult func emitGesture(mode: ActionMode, direction: Int, reversed: Bool) -> Bool {
        guard !mode.isContinuous, AXIsProcessTrusted(), CGPreflightPostEventAccess() else { return false }
        let before = postedEvents
        performDiscrete(mode: mode, forward: (direction > 0) != reversed)
        return postedEvents > before
    }

    @discardableResult func test(mode: ActionMode, reversed: Bool) -> Bool {
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else { return false }
        let before = postedEvents
        if mode == .scroll || mode == .horizontal {
            scroll(pixels: reversed ? 420 : -420, horizontal: mode == .horizontal)
        } else { performDiscrete(mode: mode, forward: !reversed) }
        return postedEvents > before
    }

    private func scroll(pixels: Int32, horizontal: Bool) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: horizontal ? 2 : 1,
                                 wheel1: horizontal ? 0 : pixels, wheel2: horizontal ? pixels : 0, wheel3: 0) else { return }
        if let cursor = CGEvent(source: nil)?.location { event.location = cursor }
        event.post(tap: .cghidEventTap)
        postedEvents += 1
    }

    private func performDiscrete(mode: ActionMode, forward: Bool) {
        switch mode {
        case .pages: key(forward ? 121 : 116)
        case .spaces: key(forward ? 124 : 123, flags: .maskControl)
        case .apps: key(48, flags: forward ? .maskCommand : [.maskCommand, .maskShift])
        case .zoom: key(forward ? 24 : 27, flags: forward ? [.maskCommand, .maskShift] : .maskCommand)
        default: break
        }
    }

    private func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        // Arrow keys carry Fn/numeric-pad flags on macOS. Replacing their flags
        // with Control alone fails to match Mission Control's symbolic hotkey.
        let keyFlags = KeyboardModifiers.forKey(code, modifiers: flags)
        let modifiers: [(CGEventFlags, CGKeyCode)] = [(.maskControl, 59), (.maskAlternate, 58), (.maskShift, 56), (.maskCommand, 55)]
        let pressed = modifiers.filter { flags.contains($0.0) }
        postedEvents += 1
        keyboardQueue.async {
            guard CGPreflightPostEventAccess() else { return }
            var held: CGEventFlags = []
            for (flag, modifier) in pressed {
                held.insert(flag)
                let event = CGEvent(keyboardEventSource: source, virtualKey: modifier, keyDown: true)
                event?.flags = held
                event?.post(tap: .cghidEventTap)
                Thread.sleep(forTimeInterval: 0.008)
            }
            let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
            down?.flags = keyFlags
            down?.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.016)
            let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
            up?.flags = keyFlags
            up?.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.008)
            for (flag, modifier) in pressed.reversed() {
                held.remove(flag)
                let release = CGEvent(keyboardEventSource: source, virtualKey: modifier, keyDown: false)
                release?.flags = held
                release?.post(tap: .cghidEventTap)
                Thread.sleep(forTimeInterval: 0.004)
            }
        }
    }
}
