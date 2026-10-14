import XCTest
import AppKit
@testable import HP48SXMac

final class RenderingTests: XCTestCase {
    /// Plan's Review Focus #2: drawing before the emulator thread has
    /// produced a first frame must show a blank/background LCD, never
    /// read uninitialized screen-buffer memory. Never covered by a real
    /// test -- also the permanent regression test for the coordinate-flip
    /// bug where the LCD's green background fill used the raw (top-left
    /// authored) rect directly, landing it at the bottom of the window
    /// instead of the top; the real LCD area then showed whatever was
    /// painted under it instead of green.
    func testLCDAreaShowsTheBlankGreenBackgroundBeforeTheFirstFrameArrives() throws {
        let bridge = EmulatorBridge(paths: AppPaths(configDir: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        // Deliberately never call bridge.start() -- latestFrame() stays
        // nil, exactly the "before first frame" case.
        let size = KeyLayout.contentSize
        let view = CalculatorView(frame: NSRect(origin: .zero, size: size), bridge: bridge)
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            XCTFail("could not create an offscreen bitmap for cacheDisplay")
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)

        let scaleX = CGFloat(rep.pixelsWide) / view.bounds.width
        let scaleY = CGFloat(rep.pixelsHigh) / view.bounds.height
        let lcdFlipped = KeyLayout.flipped(KeyLayout.lcdRect, inHeight: size.height)
        let bx = Int(lcdFlipped.midX * scaleX)
        // NSBitmapImageRep's own pixel coordinates are top-left; the view
        // point above is bottom-left (AppKit's usual view space).
        let by = Int(CGFloat(rep.pixelsHigh) - 1 - lcdFlipped.midY * scaleY)
        guard let color = rep.colorAt(x: bx, y: by) else {
            XCTFail("could not sample a pixel from the rendered bitmap")
            return
        }

        XCTAssertEqual(color.redComponent * 255, 189, accuracy: 2)
        XCTAssertEqual(color.greenComponent * 255, 195, accuracy: 2)
        XCTAssertEqual(color.blueComponent * 255, 165, accuracy: 2)
    }
}
