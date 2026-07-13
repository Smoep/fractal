import Foundation
import CoreGraphics

/// Pure geometry for the fractal-tree menu overlay.
///
/// Single source of truth shared by BOTH the hit-test (`SessionEngine`) and the
/// drawing (`OverlayRadialView`) so what the user sees always matches what they can
/// select. All points are in **math coordinates**: origin `(0,0)` at the trunk base
/// (the cursor when the overlay opened), `+x` pointing RIGHT, `+y` pointing UP.
/// Each consumer converts to its own space:
///   • Drawing (Canvas, y-down): `canvas = center + (x, -y)`
///   • Hit-test (screen, y-up):  compare cursor `(dx, dy)` directly against `(x, y)`
enum TreeLayout {

    // MARK: - Config

    struct Config {
        /// Length of the trunk segment from the cursor to the first fork.
        var trunkLength: CGFloat = 52
        /// Length of a level-0 (category) branch. Deeper levels shrink by `lengthRatio`.
        var baseBranchLength: CGFloat = 60
        /// Per-level length multiplier (deeper branches are shorter).
        var lengthRatio: CGFloat = 0.86
        /// Arc-length (points) allotted to each sibling — controls fan spread.
        var itemSpacing: CGFloat = 45
        /// Radius of the cancel dead-zone around the trunk base.
        var deadZone: CGFloat = 38
        /// Maximum angular spread of the level-0 fan (radians). A cap so a very
        /// crowded level doesn't wrap all the way around; tightness comes from length.
        var rootMaxSpread: CGFloat = 5.0
        /// Maximum angular spread of deeper fans (radians).
        var childMaxSpread: CGFloat = 5.0
        /// Peak per-branch organic angle jitter (radians).
        var jitter: CGFloat = 0.10
        /// Minimum distance between adjacent node centers so their circles never
        /// overlap (joint diameter + small gap).
        var minNodeSpacing: CGFloat = 40
        /// Minimum length of any branch, so a parent joint never touches its child.
        var minChainLength: CGFloat = 44

        init(baseBranchLength: CGFloat, itemSpacing: CGFloat) {
            self.baseBranchLength = baseBranchLength
            self.itemSpacing = itemSpacing
        }
    }

    // MARK: - Node info (menu-derived, no geometry)

    struct NodeInfo {
        var label: String
        var systemImage: String
        var colorHex: String
        var isCategory: Bool
    }

    // MARK: - Positioned branch

    struct Branch: Identifiable {
        var id: String { path.map(String.init).joined(separator: ".") }
        /// Selection path to this node ([catIdx], [catIdx, actIdx], …).
        var path: [Int]
        /// 0 = category level, 1 = actions of selected category, …
        var level: Int
        /// Parent tip (math coords). Level-0 branches start at the trunk tip.
        var start: CGPoint
        /// This branch's tip (math coords).
        var end: CGPoint
        /// Direction of this branch (radians, math coords).
        var angle: CGFloat
        var info: NodeInfo
        /// True when this branch's index equals the current selection at its level.
        var isSelected: Bool
    }

    // MARK: - Geometry helpers

    static func trunkTip(_ config: Config) -> CGPoint {
        CGPoint(x: config.trunkLength, y: 0)
    }

    static func branchLength(level: Int, config: Config) -> CGFloat {
        config.baseBranchLength * pow(config.lengthRatio, CGFloat(level))
    }

    /// Angular spread of a fan of `count` items at a level (radians).
    static func totalSpread(level: Int, count: Int, config: Config) -> CGFloat {
        let baseLen = branchLength(level: level, config: config)
        let maxSpread = level == 0 ? config.rootMaxSpread : config.childMaxSpread
        // Never let siblings sit closer than a node circle apart, regardless of the
        // spacing slider, so the joints can never overlap.
        let spacing = max(config.itemSpacing, config.minNodeSpacing)
        let perItem = spacing / max(baseLen, 1)
        return min(maxSpread, perItem * CGFloat(max(count, 1)))
    }

    /// Farthest reach of the deepest possible path — used to size the overlay window
    /// and to detect the cursor escaping the tree.
    static func maxReach(levels: Int, config: Config) -> CGFloat {
        var reach = config.trunkLength
        for d in 0..<max(1, levels) {
            reach += branchLength(level: d, config: config)
        }
        return reach
    }

    // MARK: - Build

    /// Build the visible branches for the current selection.
    ///
    /// - Parameters:
    ///   - levelItems: closure returning the menu items at a given level
    ///     (level 0 = categories, level d≥1 = children of the locked path).
    ///   - selectionPath: currently chosen index at each level.
    ///   - lockedDepth: number of locked levels; branches are laid out for
    ///     levels `0...lockedDepth` (the deepest rendered level is the free one).
    static func build(
        levelItems: (Int) -> [NodeInfo],
        selectionPath: [Int],
        lockedDepth: Int,
        config: Config
    ) -> [Branch] {
        var branches: [Branch] = []
        var parentTip = trunkTip(config)
        var parentDir: CGFloat = 0            // trunk points right
        var lockedPrefix: [Int] = []

        let activeLevel = max(0, lockedDepth)
        for level in 0...activeLevel {
            let items = levelItems(level)
            if items.isEmpty { break }

            let count = items.count
            let spread = totalSpread(level: level, count: count, config: config)
            let slice = spread / CGFloat(count)
            // Consistent line length at every level (controlled by the slider);
            // crowded levels fan wider rather than growing longer.
            let length = branchLength(level: level, config: config)

            let selIdx = selectionPath.indices.contains(level) ? selectionPath[level] : nil
            // Only the deepest (active) level shows every sibling; shallower levels
            // collapse to just the selected branch so nothing else is visible until
            // the cursor moves back out.
            let isActive = level == activeLevel

            var nextParentTip = parentTip
            var nextParentDir = parentDir
            var haveNext = false

            for i in 0..<count {
                if !isActive && i != selIdx { continue }
                let path = lockedPrefix + [i]
                // Symmetric fan centred on the parent direction, plus deterministic
                // per-branch jitter for an organic look (stable across frames).
                let base = parentDir - spread / 2 + (CGFloat(i) + 0.5) * slice
                let angle = base + jitterFor(path: path, peak: config.jitter)
                let end = CGPoint(
                    x: parentTip.x + length * cos(angle),
                    y: parentTip.y + length * sin(angle)
                )
                let isSelected = selIdx == i
                branches.append(Branch(
                    path: path, level: level,
                    start: parentTip, end: end, angle: angle,
                    info: items[i], isSelected: isSelected
                ))
                if isSelected {
                    nextParentTip = end
                    nextParentDir = angle
                    haveNext = true
                }
            }

            // Descend only into the selected branch.
            guard haveNext, let selIdx else { break }
            parentTip = nextParentTip
            parentDir = nextParentDir
            lockedPrefix.append(selIdx)
        }

        return branches
    }

    // MARK: - Jitter

    /// Deterministic angle jitter in `[-peak, +peak]` seeded from the branch path,
    /// so the tree looks organic but never flickers between frames.
    static func jitterFor(path: [Int], peak: CGFloat) -> CGFloat {
        var h: UInt64 = 1469598103934665603   // FNV-1a offset basis
        for v in path {
            h = (h ^ UInt64(bitPattern: Int64(v &+ 1))) &* 1099511628211
        }
        // Map high bits to [0,1).
        let unit = CGFloat(h >> 40) / CGFloat(UInt64(1) << 24)
        return (unit * 2 - 1) * peak
    }

    // MARK: - Hit-testing

    /// Fraction of the cursor's projection along a branch segment, `0` at `start`
    /// (parent fork) and `1` at `end` (tip). Clamped to `[0, 1]`.
    static func projectionFraction(of p: CGPoint, on branch: Branch) -> CGFloat {
        let vx = branch.end.x - branch.start.x
        let vy = branch.end.y - branch.start.y
        let len2 = vx * vx + vy * vy
        guard len2 > 0 else { return 0 }
        let t = ((p.x - branch.start.x) * vx + (p.y - branch.start.y) * vy) / len2
        return min(1, max(0, t))
    }

    /// Perpendicular distance from a point to a branch segment.
    static func distance(from p: CGPoint, to branch: Branch) -> CGFloat {
        let t = projectionFraction(of: p, on: branch)
        let cx = branch.start.x + (branch.end.x - branch.start.x) * t
        let cy = branch.start.y + (branch.end.y - branch.start.y) * t
        return hypot(p.x - cx, p.y - cy)
    }
}
