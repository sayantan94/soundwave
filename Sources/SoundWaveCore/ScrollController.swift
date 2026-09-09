import Foundation

/// Converts fresh detections into pixels; no momentum survives signal loss or pause.
public struct ScrollController {
    private var lastTime: Double?
    private var remainder = 0.0
    private var direction = 0
    private var idleSince: Double?
    private var reversalSince: Double?

    public init() {}
    public mutating func reset() { self = ScrollController() }

    public mutating func update(motion: Double, now: Double, enabled: Bool, speed: Double, reversed: Bool) -> Int32 {
        guard enabled && motion.isFinite else { reset(); return 0 }
        let dt = min(0.05, max(0, now - (lastTime ?? now)))
        lastTime = now
        let next = motion > 0 ? 1 : motion < 0 ? -1 : 0
        if next == 0 {
            remainder = 0
            reversalSince = nil
            if idleSince == nil { idleSince = now }
            if now - (idleSince ?? now) > 0.18 { direction = 0 }
            return 0
        }
        idleSince = nil
        // A quick reversal is normally the return stroke. Require sustained intent.
        if direction != 0 && next != direction {
            if reversalSince == nil { reversalSince = now }
            remainder = 0
            guard now - (reversalSince ?? now) >= 0.25 else { return 0 }
        }
        reversalSince = nil
        direction = next
        // Quartz positive scroll deltas move the page up; toward defaults to down.
        let delta = -motion * min(2000, max(0, speed)) * dt * (reversed ? -1 : 1) + remainder
        let pixels = Int32(delta.rounded(.towardZero))
        remainder = delta - Double(pixels)
        return pixels
    }
}
