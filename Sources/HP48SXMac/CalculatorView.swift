import Cocoa

final class CalculatorView: NSView {
    private let bridge: EmulatorBridge
    private var keyImages: [NSImage] = []
    private var annunciatorImages: [NSImage] = []
    private var redrawTimer: Timer?
    private var pressedKeyCode: Int32?

    // Colors ported verbatim from HPView: central/menu-key background,
    // LCD green. (HPView also draws a "func line" rect, but its own
    // drawRect(0, start_h, w, start_h) call has top == bottom -- a
    // zero-height no-op that never actually renders -- so it's omitted
    // here rather than ported as a visible rect.)
    private let centralColor = NSColor(calibratedRed: 57/255, green: 57/255, blue: 56/255, alpha: 1)
    private let lcdGreen = NSColor(calibratedRed: 189/255, green: 195/255, blue: 165/255, alpha: 1)

    init(frame: NSRect, bridge: EmulatorBridge) {
        self.bridge = bridge
        super.init(frame: frame)
        loadImages()
        redrawTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 25.0, repeats: true) { [weak self] _ in
            self?.setNeedsDisplay(self?.bounds ?? .zero)
        }
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    private func loadImages() {
        keyImages = (1...49).map { i in
            KeycapImages.load("k\(String(format: "%02d", i))") ?? NSImage()
        }
        annunciatorImages = (1...6).map { i in
            KeycapImages.load("ann\(String(format: "%02d", i))") ?? NSImage()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        centralColor.setFill()
        bounds.fill()

        lcdGreen.setFill()
        KeyLayout.flipped(KeyLayout.lcdRect, inHeight: bounds.height).fill()

        drawLCDBitmap()

        for (i, rect) in KeyLayout.keyRects.enumerated() where rect.width > 0 {
            keyImages[i].draw(in: KeyLayout.flipped(rect, inHeight: bounds.height))
        }

        if let frame = bridge.latestFrame() {
            for (i, on) in frame.annunciators.enumerated() where on {
                let r = KeyLayout.iconRects[i]
                annunciatorImages[i].draw(in: KeyLayout.flipped(r, inHeight: bounds.height))
            }
        }
    }

    private func drawLCDBitmap() {
        guard let frame = bridge.latestFrame() else { return }
        let width = 262
        let height = 14 + 128
        guard frame.screen.count == width * height else { return }

        var rgbaBuffer = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            let px = frame.screen[i] // RGB565
            let r = UInt8((px >> 11) & 0x1F) << 3
            let g = UInt8((px >> 5) & 0x3F) << 2
            let b = UInt8(px & 0x1F) << 3
            rgbaBuffer[i * 4] = r
            rgbaBuffer[i * 4 + 1] = g
            rgbaBuffer[i * 4 + 2] = b
            rgbaBuffer[i * 4 + 3] = 255
        }

        guard let provider = CGDataProvider(data: Data(rgbaBuffer) as CFData) else { return }
        // shouldInterpolate: true, matching Android's own default bilinear
        // bitmap filtering. The destination rect's height (headerHeightUnit
        // * ratio, preserved exactly from upstream's own start_h constant
        // -- see the design spec's Dimensions section) is a few points
        // taller than this bitmap's real 142-row height, so an unfiltered
        // draw shows uneven, jagged pixel rows; Android hides the same
        // mismatch with filtering rather than changing its own start_h.
        guard let cgImage = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        ) else { return }

        let context = NSGraphicsContext.current?.cgContext
        context?.interpolationQuality = .high
        context?.draw(cgImage, in: KeyLayout.flipped(KeyLayout.lcdRect, inHeight: bounds.height))
    }
}

extension CalculatorView {
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let p = convertToTopLeft(event.locationInWindow)
        guard let code = KeyLayout.keyIndex(at: p) else { return }
        pressedKeyCode = Int32(code)
        bridge.pressKey(Int32(code), down: true)
    }

    override func mouseUp(with event: NSEvent) {
        guard let code = pressedKeyCode else { return }
        bridge.pressKey(code, down: false)
        pressedKeyCode = nil
    }

    override func keyDown(with event: NSEvent) {
        guard let code = KeyMapping.code(forCharacters: event.charactersIgnoringModifiers ?? "")
            ?? specialKeyCode(for: event) else { return }
        bridge.pressKey(code, down: true)
    }

    override func keyUp(with event: NSEvent) {
        guard let code = KeyMapping.code(forCharacters: event.charactersIgnoringModifiers ?? "")
            ?? specialKeyCode(for: event) else { return }
        bridge.pressKey(code, down: false)
    }

    private func specialKeyCode(for event: NSEvent) -> Int32? {
        switch event.specialKey {
        case .some(.delete), .some(.backspace): return KeyMapping.code(forSpecialKey: .delete)
        case .some(.upArrow): return KeyMapping.code(forSpecialKey: .upArrow)
        case .some(.downArrow): return KeyMapping.code(forSpecialKey: .downArrow)
        case .some(.leftArrow): return KeyMapping.code(forSpecialKey: .leftArrow)
        case .some(.rightArrow): return KeyMapping.code(forSpecialKey: .rightArrow)
        default: return nil
        }
    }

    private func convertToTopLeft(_ windowPoint: NSPoint) -> NSPoint {
        let p = convert(windowPoint, from: nil)
        return NSPoint(x: p.x, y: bounds.height - p.y)
    }
}
