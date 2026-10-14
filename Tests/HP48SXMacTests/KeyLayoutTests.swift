import XCTest
@testable import HP48SXMac

final class KeyLayoutTests: XCTestCase {
    func testContentSizeMatchesSpec() {
        // XCTAssertEqual(_:_:accuracy:) has no CGSize overload; compare
        // width/height separately.
        XCTAssertEqual(KeyLayout.contentSize.width, 360, accuracy: 1)
        XCTAssertEqual(KeyLayout.contentSize.height, 735, accuracy: 1)
    }

    func testLCDRectIsCenteredAtTop() {
        let r = KeyLayout.lcdRect
        XCTAssertEqual(r.origin.y, 0, accuracy: 0.5)
        XCTAssertEqual(r.midX, KeyLayout.contentSize.width / 2, accuracy: 1)
    }

    func testAllFortyNineKeysHaveNonZeroRects() {
        XCTAssertEqual(KeyLayout.keyRects.count, 49)
        for (i, r) in KeyLayout.keyRects.enumerated() {
            XCTAssertGreaterThan(r.width, 0, "key \(i) has zero width")
            XCTAssertGreaterThan(r.height, 0, "key \(i) has zero height")
        }
    }

    func testEnterKeySpansTripleWidthOfAMenuKey() {
        let enterWidth = KeyLayout.keyRects[24].width
        let menuKeyWidth = KeyLayout.keyRects[0].width
        XCTAssertEqual(enterWidth, menuKeyWidth * 2, accuracy: 1,
                       "ENTER (key 24) is width/3 of content; a menu key (key 0) is width/6")
    }

    func testSixAcrossRowKeysAreSquare() {
        // Keys 0-5 (menu row) and 6-23 (3 regular 6-wide rows) are sized
        // width/6 x regular_key_height, with regular_key_height == width/6
        // (the spec's "square narrow-row keys" choice).
        let r = KeyLayout.keyRects[0]
        XCTAssertEqual(r.width, r.height, accuracy: 1)
    }

    func testHitTestFindsKeyAtItsOwnCenter() {
        for (i, r) in KeyLayout.keyRects.enumerated() {
            XCTAssertEqual(KeyLayout.keyIndex(at: CGPoint(x: r.midX, y: r.midY)), i)
        }
    }

    func testHitTestReturnsNilOutsideAnyKey() {
        XCTAssertNil(KeyLayout.keyIndex(at: CGPoint(x: -10, y: -10)))
    }

    func testEveryKeyRectLiesWithinTheWindow() {
        // Final-review Critical finding C1: keys 25-28 and 29-48 used the
        // wrong row multiplier and rendered one (25-28) to three (29-48)
        // rows below where they belonged -- rows 9-11 landed at or past
        // the window's bottom edge entirely, making ON, both shift keys,
        // the digits, and +-x/ invisible and unclickable. None of the
        // other tests in this file would have caught it (they only check
        // a rect's own internal consistency, never its position against
        // the window bounds).
        // The last row's bottom edge is mathematically exactly at the
        // window's bottom edge by design (startH + rowCount*keyH ==
        // contentSize.height); strict CGRect.contains() can reject that
        // by a floating-point ulp or two depending on operation order, so
        // allow a tiny epsilon rather than requiring strict containment.
        let epsilon: CGFloat = 0.01
        let bounds = CGRect(origin: .zero, size: KeyLayout.contentSize).insetBy(dx: -epsilon, dy: -epsilon)
        for (i, rect) in KeyLayout.keyRects.enumerated() {
            XCTAssertTrue(bounds.contains(rect), "key \(i) at \(rect) is not fully inside the window \(bounds)")
        }
    }
}
