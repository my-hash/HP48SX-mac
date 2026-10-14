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
