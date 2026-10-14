import XCTest
@testable import HP48SXMac

final class KeyMappingTests: XCTestCase {
    func testDigitKeysMapToExpectedButtonCodes() {
        // Matches HPView.actionKey: KEYCODE_0->45, _1->40, _7->30, etc.
        XCTAssertEqual(KeyMapping.code(forCharacters: "0"), 45)
        XCTAssertEqual(KeyMapping.code(forCharacters: "7"), 30)
        XCTAssertEqual(KeyMapping.code(forCharacters: "9"), 32)
    }

    func testEnterAndDeleteMapCorrectly() {
        XCTAssertEqual(KeyMapping.code(forCharacters: "\r"), 24)
        XCTAssertEqual(KeyMapping.code(forSpecialKey: .delete), 28)
    }

    func testLetterAMapsToButtonZero() {
        XCTAssertEqual(KeyMapping.code(forCharacters: "a"), 0)
        XCTAssertEqual(KeyMapping.code(forCharacters: "A"), 0)
    }

    func testUnmappedCharacterReturnsNil() {
        XCTAssertNil(KeyMapping.code(forCharacters: "$"))
        XCTAssertNil(KeyMapping.code(forCharacters: ""))
    }
}

final class HeldKeyTrackerTests: XCTestCase {
    func testReleasingAPhysicalKeyReturnsTheSameCodeItWasPressedWith() {
        // Deferred-minor finding: a shift-dependent character (e.g. "@" =
        // Shift+2) can have its key-up event report different characters
        // than its key-down if Shift is released a moment early -- macOS
        // recomputes charactersIgnoringModifiers from the CURRENT modifier
        // state at each event, not the state when the key went down. If
        // keyUp re-derives the code from characters, it can release a
        // DIFFERENT HP48 key than the one actually pressed, leaving the
        // real one stuck "down" forever. Tracking by the physical,
        // never-changing NSEvent.keyCode instead fixes this.
        let tracker = HeldKeyTracker()
        tracker.press(physicalKeyCode: 19, logicalCode: 29) // Shift+2 -> "@" -> code 29
        XCTAssertEqual(tracker.release(physicalKeyCode: 19), 29, "must release the code it was actually pressed with, even if the key's current characters would now map differently")
    }

    func testReleasingAnUntrackedPhysicalKeyReturnsNil() {
        let tracker = HeldKeyTracker()
        XCTAssertNil(tracker.release(physicalKeyCode: 99))
    }

    func testReleasingAKeyRemovesItSoItCannotBeReleasedTwice() {
        let tracker = HeldKeyTracker()
        tracker.press(physicalKeyCode: 5, logicalCode: 10)
        XCTAssertEqual(tracker.release(physicalKeyCode: 5), 10)
        XCTAssertNil(tracker.release(physicalKeyCode: 5), "a second release of the same physical key (e.g. a duplicate keyUp) must not re-fire")
    }
}
