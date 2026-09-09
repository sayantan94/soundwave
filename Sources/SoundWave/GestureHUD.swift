import AppKit
import SwiftUI

@MainActor final class GestureHUD {
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(title: String, symbol: String) {
        hideTask?.cancel()
        let hud: NSPanel
        if let panel { hud = panel }
        else {
            hud = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            hud.level = .statusBar
            hud.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            hud.ignoresMouseEvents = true
            hud.hidesOnDeactivate = false
            hud.isOpaque = false
            hud.backgroundColor = .clear
            hud.hasShadow = false
            panel = hud
        }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let screen else { return }
        hud.contentView = NSHostingView(rootView: HUDContent(title: title, symbol: symbol))
        hud.setFrame(NSRect(x: screen.visibleFrame.midX - 145, y: screen.visibleFrame.minY + 65, width: 290, height: 68), display: true)
        hud.alphaValue = 1
        hud.orderFrontRegardless()
        hideTask = Task {
            do { try await Task.sleep(nanoseconds: 550_000_000) } catch { return }
            hud.orderOut(nil)
        }
    }
    func hide() { hideTask?.cancel(); panel?.orderOut(nil) }
}

private struct HUDContent: View {
    let title: String
    let symbol: String
    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol).font(.system(size: 21, weight: .medium)).foregroundStyle(Color(red: 0.54, green: 0.96, blue: 0.79))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                Text("Gesture accepted").font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
            Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
        }.padding(.horizontal, 20).frame(width: 290, height: 64)
            .background(Color(red: 0.06, green: 0.09, blue: 0.10), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.13), lineWidth: 1))
    }
}
