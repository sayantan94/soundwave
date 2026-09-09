import CoreGraphics

public enum KeyboardModifiers {
    /// Arrow events include Fn and numeric-pad flags even on compact keyboards.
    /// Mission Control's registered shortcuts require this key identity.
    public static func forKey(_ code: CGKeyCode, modifiers: CGEventFlags) -> CGEventFlags {
        (123...126).contains(code) ? modifiers.union([.maskSecondaryFn, .maskNumericPad]) : modifiers
    }
}
