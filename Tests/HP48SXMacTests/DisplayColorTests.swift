import XCTest
import CEmu
@testable import HP48SXMac

/// Final-review Important finding I2: HPView's constructor calls
/// x48.setBlankColor(...) with contrast "1" (the real default -- nothing
/// in this port ever sets a different value), which computes to 0xBE14
/// (contrast_factor 0.5: R=(15*0.5+16)=23, G=(30*0.5+33)=48,
/// B=(15*0.5+13)=20 -> (23<<11)+(48<<5)+20 = 48660 = 0xBE14). That call
/// fills disp_buf_header_short (the LCD's 14-row icon strip) with the
/// correct background color; EmulatorBridge never called it, so that
/// array stayed all-zero (black) -- the annunciator icons (black glyphs)
/// draw onto a black strip and are invisible, and the LCD background
/// itself is the wrong, dingy color.
final class DisplayColorTests: XCTestCase {
    func testIconStripIsFilledWithTheRealBlankColorNotBlack() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let paths = AppPaths(configDir: dir)
        try paths.ensureFirstRunAssets()

        let bridge = EmulatorBridge(paths: paths)
        bridge.start()
        defer { bridge.stop(); try? fm.removeItem(at: dir) }

        let deadline = Date().addingTimeInterval(2)
        while bridge.latestFrame() == nil, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        guard let frame = bridge.latestFrame() else {
            XCTFail("setup: should have booted at all")
            return
        }

        // The icon strip is the first 14 * 262 shorts of the screen
        // buffer (see EMU_SCREEN_BUF_LEN's own comment).
        let iconStripLength = 14 * 262
        let iconStrip = frame.screen.prefix(iconStripLength)
        let blankColor: UInt16 = 0xBE14
        XCTAssertTrue(iconStrip.allSatisfy { $0 == blankColor }, "the icon strip should be filled with the real blank color (0xBE14), not left at 0 (black)")
    }
}
