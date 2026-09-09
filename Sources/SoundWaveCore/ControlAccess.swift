/// Accessibility can update while Core Graphics still caches a denial until relaunch.
public enum ControlAccess: Equatable {
    case permissionNeeded
    case restartNeeded
    case ready

    public init(accessibilityGranted: Bool, eventPostingGranted: Bool) {
        if !accessibilityGranted { self = .permissionNeeded }
        else if !eventPostingGranted { self = .restartNeeded }
        else { self = .ready }
    }
}
