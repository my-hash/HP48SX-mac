import XCTest
@testable import HP48SXMac

/// CalculatorView.loadImages() looks up images as "Keycaps/k01" etc. via
/// Bundle.module.image(forResource:). This project has already hit two
/// different Bundle resource-path surprises (rom/ram/hp48 landing flat
/// vs. under "Resources/", and Bundle.module not being visible from a
/// test target) -- worth pinning down for real rather than assuming the
/// subpath-qualified lookup works.
final class KeycapResourceTests: XCTestCase {
    func testAllFortyNineKeycapsLoadAsNonEmptyImages() {
        for i in 1...49 {
            let name = "k\(String(format: "%02d", i))"
            let image = KeycapImages.load(name)
            XCTAssertNotNil(image, "\(name) should resolve to an image")
            XCTAssertNotEqual(image?.size, .zero, "\(name) resolved but has zero size")
        }
    }

    func testAllSixAnnunciatorsLoadAsNonEmptyImages() {
        for i in 1...6 {
            let name = "ann\(String(format: "%02d", i))"
            let image = KeycapImages.load(name)
            XCTAssertNotNil(image, "\(name) should resolve to an image")
            XCTAssertNotEqual(image?.size, .zero, "\(name) resolved but has zero size")
        }
    }
}
