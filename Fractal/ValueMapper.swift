import Foundation
import CoreGraphics

/// Maps normalised trackpad position (0–1) to zone index on a grid.
enum ValueMapper {

    /// Compute the zone index (0-based, row-major) from normalised X/Y position.
    /// X: 0 = left, 1 = right. Y: 0 = bottom, 1 = top.
    static func zoneIndex(x: CGFloat, y: CGFloat, divisions: Int) -> Int {
        let d = max(1, divisions)
        let col = min(d - 1, max(0, Int(x * CGFloat(d))))
        // Y on trackpad: 0 = bottom, 1 = top; row 0 = top of grid.
        let row = min(d - 1, max(0, Int((1.0 - y) * CGFloat(d))))
        return row * d + col
    }

    /// Zone ID string from index (e.g. "Z1", "Z2", …).
    static func zoneID(index: Int) -> String {
        "Z\(index + 1)"
    }

    /// Zone ID directly from normalised position.
    static func zoneID(x: CGFloat, y: CGFloat, divisions: Int) -> String {
        zoneID(index: zoneIndex(x: x, y: y, divisions: divisions))
    }

    /// Column index from normalised X (0 = left).
    static func column(x: CGFloat, divisions: Int) -> Int {
        let d = max(1, divisions)
        return min(d - 1, max(0, Int(x * CGFloat(d))))
    }

    /// Row index from normalised Y (0 = top row).
    static func row(y: CGFloat, divisions: Int) -> Int {
        let d = max(1, divisions)
        return min(d - 1, max(0, Int((1.0 - y) * CGFloat(d))))
    }
}
