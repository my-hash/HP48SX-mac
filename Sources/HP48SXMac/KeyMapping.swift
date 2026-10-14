import Cocoa

/// Ports HPView.actionKey's physical-keyboard table (Android KeyEvent
/// codes -> HP48 button index) to macOS characters/special keys.
enum KeyMapping {
    enum SpecialKey { case delete, upArrow, downArrow, leftArrow, rightArrow }

    private static let digitCodes: [Character: Int32] = [
        "0": 45, "1": 40, "2": 41, "3": 42, "4": 35,
        "5": 36, "6": 37, "7": 30, "8": 31, "9": 32,
    ]

    private static let letterCodes: [Character: Int32] = [
        "a": 0, "b": 1, "c": 2, "d": 3, "e": 4, "f": 5, "g": 6, "h": 7,
        "i": 8, "j": 9, "k": 10, "l": 11, "m": 12, "n": 13, "o": 14,
        "p": 15, "q": 16, "r": 17, "s": 18, "t": 19, "u": 20, "v": 21,
        "w": 22, "x": 23, "y": 25, "z": 26,
    ]

    static func code(forCharacters characters: String) -> Int32? {
        guard let c = characters.first, characters.count == 1 else { return nil }
        if c == "\r" || c == "\n" { return 24 } // ENTER
        if c == "." { return 46 }
        if c == " " { return 47 }
        if c == "@" { return 29 }
        let lower = Character(c.lowercased())
        if let code = digitCodes[c] { return code }
        if let code = letterCodes[lower] { return code }
        return nil
    }

    static func code(forSpecialKey key: SpecialKey) -> Int32 {
        switch key {
        case .delete: return 28
        case .upArrow: return 10
        case .downArrow: return 16
        case .leftArrow: return 15
        case .rightArrow: return 17
        }
    }
}

/// Tracks which HP48 key code is currently held for each physical
/// keyboard key (NSEvent.keyCode), so a key-up always releases the same
/// code its key-down pressed -- even if the key's *produced characters*
/// would now map differently (e.g. Shift released a moment before a
/// shift-dependent character's own key-up fires).
final class HeldKeyTracker {
    private var held: [UInt16: Int32] = [:]

    func press(physicalKeyCode: UInt16, logicalCode: Int32) {
        held[physicalKeyCode] = logicalCode
    }

    func release(physicalKeyCode: UInt16) -> Int32? {
        held.removeValue(forKey: physicalKeyCode)
    }
}
