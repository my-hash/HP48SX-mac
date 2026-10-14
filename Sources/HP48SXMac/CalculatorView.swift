import Cocoa

final class CalculatorView: NSView {
    private let bridge: EmulatorBridge
    private var keyImages: [NSImage] = []
    private var annunciatorImages: [NSImage] = []
    private var redrawTimer: Timer?

    // Colors ported verbatim from HPView: func line, central/menu-key
    // background, LCD green.
    private let funcColor = NSColor(calibratedRed: 83/255, green: 81/255, blue: 82/255, alpha: 1)
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

        funcColor.setFill()
        NSRect(x: 0, y: KeyLayout.lcdRect.maxY, width: bounds.width, height: bounds.height - KeyLayout.lcdRect.maxY).fill()

        lcdGreen.setFill()
        KeyLayout.lcdRect.fill()

        drawLCDBitmap()

        for (i, rect) in KeyLayout.keyRects.enumerated() where rect.width > 0 {
            // AppKit's coordinate origin is bottom-left; KeyLayout is
            // authored top-left (matching HPView/Android), so flip y.
            let flipped = NSRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
            keyImages[i].draw(in: flipped)
        }

        if let frame = bridge.latestFrame() {
            for (i, on) in frame.annunciators.enumerated() where on {
                let r = KeyLayout.iconRects[i]
                let flipped = NSRect(x: r.minX, y: bounds.height - r.maxY, width: r.width, height: r.height)
                annunciatorImages[i].draw(in: flipped)
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
        guard let cgImage = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ) else { return }

        let flipped = NSRect(x: KeyLayout.lcdRect.minX, y: bounds.height - KeyLayout.lcdRect.maxY,
                              width: KeyLayout.lcdRect.width, height: KeyLayout.lcdRect.height)
        NSGraphicsContext.current?.cgContext.draw(cgImage, in: flipped)
    }
}
