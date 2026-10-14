import CoreGraphics

/// Ports HPView.refreshMainScreen's portrait / !keybLite / !fullWidth
/// layout math at a fixed lcd_ratio of 2 (the bundled LCD bitmap is
/// already 262x142 = 131x64 real pixels x2, so ratio 2 renders it at
/// native resolution). See the design spec's "Dimensions" section for
/// the full derivation. All values are in points; origin top-left.
enum KeyLayout {
    private static let ratio: CGFloat = 2
    private static let scale: CGFloat = 1.333 // design-unit -> comfortable desktop window

    private static let lcdColumnUnit: CGFloat = 131
    private static let contentWidthUnit: CGFloat = 135
    private static let headerHeightUnit: CGFloat = 73
    private static let rowCount: CGFloat = 9

    private static var designWidth: CGFloat { contentWidthUnit * ratio }
    private static var designStartH: CGFloat { headerHeightUnit * ratio }
    private static var designKeyHeight: CGFloat { designWidth / 6 }
    private static var designHeight: CGFloat { designStartH + rowCount * designKeyHeight }

    static var contentSize: CGSize {
        CGSize(width: designWidth * scale, height: designHeight * scale)
    }

    static var lcdRect: CGRect {
        let w = lcdColumnUnit * ratio * scale
        let h = designStartH * scale
        let x = (contentSize.width - w) / 2
        return CGRect(x: x, y: 0, width: w, height: h)
    }

    static var iconRects: [CGRect] {
        let xOffsetsUnits: [CGFloat] = [0, 21, 45, 67, 91, 112]
        let y = 1 * ratio * scale
        return xOffsetsUnits.map { CGRect(x: lcdRect.minX + $0 * ratio * scale, y: y, width: 17 * scale, height: 12 * scale) }
    }

    /// 49 key rects indexed 0...48, matching HPView's button codes exactly:
    /// 0-5 menu row (A-F), 6-23 three rows of 6, 24 ENTER + 25-28 (row 3,
    /// width/6 each except ENTER at width/3), 29-48 four rows of 5.
    static let keyRects: [CGRect] = {
        let w = designWidth * scale
        let keyH = designKeyHeight * scale
        let startH = designStartH * scale
        var rects = [CGRect](repeating: .zero, count: 49)

        for k in 0..<6 {
            rects[k] = CGRect(x: w / 6 * CGFloat(k), y: startH, width: w / 6, height: keyH)
        }
        for k in 6..<24 {
            let col = CGFloat(k % 6)
            let row = CGFloat(k / 6 - 1)
            rects[k] = CGRect(x: w / 6 * col, y: startH + keyH * (1 + row), width: w / 6, height: keyH)
        }
        rects[24] = CGRect(x: 0, y: startH + keyH * 4, width: w / 3, height: keyH)
        for k in 25..<29 {
            let col = CGFloat((k + 1) % 6)
            let rank = CGFloat((k + 1) / 6)
            // Android: start_h + menu_key_height + regular_key_height*(rank-1)
            //        = startH + keyH*rank (menu_key_height == regular_key_height
            //          in this portrait/!land branch). A previous version of
            //          this file had `keyH * (1 + rank)`, one row too low --
            //          confirmed by the final review: it pushed keys 25-28
            //          into row 5 instead of row 4.
            rects[k] = CGRect(x: w / 6 * col, y: startH + keyH * rank, width: w / 6, height: keyH)
        }
        for k in 29..<49 {
            let col = CGFloat((k + 1) % 5)
            let rank = CGFloat((k + 1) / 5)
            // Android: start_h + menu_key_height + regular_key_height*(rank-2)
            //        = startH + keyH*(rank-1). A previous version of this file
            //          had `keyH * (rank + 2)`, three rows too low -- pushed
            //          keys 29-48 into rows 8-11 (at or past the window's
            //          bottom edge) instead of rows 4-7.
            rects[k] = CGRect(x: w / 5 * col, y: startH + keyH * (rank - 1), width: w / 5, height: keyH)
        }
        return rects
    }()

    static func keyIndex(at point: CGPoint) -> Int? {
        keyRects.firstIndex { $0.contains(point) }
    }
}
