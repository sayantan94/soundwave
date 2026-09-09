import Foundation

public enum GestureResponse: String, CaseIterable, Identifiable {
    case responsive = "Responsive"
    case balanced = "Balanced"
    case deliberate = "Deliberate"
    public var id: String { rawValue }
    var attack: Double { self == .responsive ? 0.009 : self == .balanced ? 0.025 : 0.045 }
    var confidence: Double { self == .responsive ? 0.60 : self == .balanced ? 0.70 : 0.78 }
    var cooldown: Double { self == .responsive ? 0.45 : self == .balanced ? 0.60 : 0.75 }
    var neutral: Double { self == .responsive ? 0.18 : self == .balanced ? 0.24 : 0.30 }
}

public enum GesturePhase: String {
    case settling = "Hold still"
    case ready = "Ready"
    case tracking = "Following your hand"
    case cooldown = "Return your hand"
}

public struct GestureUpdate {
    public let phase: GesturePhase
    public let progress: Double
    public let acceptedDirection: Int?
}

/// Recognizes a stroke once. Return strokes, short gaps, and tone loss cannot rearm it.
/// Feed every FFT frame with its sample timestamp, including invalid-signal frames.
public struct GestureRecognizer {
    public var response: GestureResponse
    public private(set) var phase: GesturePhase = .settling
    private var previousTime: Double?
    private var lastFire = -Double.infinity
    private var neutralSince: Double?
    private var candidate = 0
    private var evidence = 0.0
    private var samples = 0
    private var lastEvidence: Double?

    public init(response: GestureResponse = .responsive) { self.response = response }

    public mutating func update(motion: Double, confidence: Double, activity: Double,
                                signalGood: Bool, time: Double) -> GestureUpdate {
        guard time.isFinite else { return result() }
        let elapsed = time - (previousTime ?? time)
        previousTime = time
        guard signalGood, motion.isFinite, confidence.isFinite, activity.isFinite,
              elapsed >= 0, elapsed < 0.15 else {
            clearCandidate()
            neutralSince = nil
            phase = time - lastFire < response.cooldown ? .cooldown : .settling
            return result()
        }
        let quiet = abs(motion) < 0.1 && activity < 0.25
        if quiet {
            if neutralSince == nil { neutralSince = time }
        } else { neutralSince = nil }

        if phase == .settling || phase == .cooldown {
            let needed = phase == .settling ? 0.12 : response.neutral
            if let since = neutralSince, time - since >= needed, time - lastFire >= response.cooldown {
                phase = .ready
            }
            return result()
        }

        let direction = confidence >= response.confidence && abs(motion) >= 0.15 ? (motion > 0 ? 1 : -1) : 0
        // Evidence against a stroke still counts even when it is too weak to
        // accept an opposite stroke. Otherwise alternating motion can add up.
        if candidate != 0 && motion * Double(candidate) < -0.15 && confidence >= 0.35 {
            clearCandidate()
            phase = .ready
        }
        if direction == 0 {
            if let lastEvidence, time - lastEvidence > 0.04 { clearCandidate(); phase = .ready }
            return result()
        }
        if candidate != direction {
            clearCandidate()
            candidate = direction
            samples = 1
        } else {
            samples += 1
            // Only actual supporting frames count, not a long gap between them.
            if let lastEvidence, time - lastEvidence <= 0.025 { evidence += max(0, elapsed) }
        }
        lastEvidence = time
        phase = .tracking
        if samples >= 2 && evidence >= response.attack {
            lastFire = time
            neutralSince = nil
            clearCandidate()
            phase = .cooldown
            return GestureUpdate(phase: phase, progress: 1, acceptedDirection: direction)
        }
        return result()
    }

    private mutating func clearCandidate() {
        candidate = 0; evidence = 0; samples = 0; lastEvidence = nil
    }
    private func result() -> GestureUpdate {
        GestureUpdate(phase: phase, progress: phase == .tracking ? min(1, evidence / response.attack) : 0, acceptedDirection: nil)
    }
}
