import AppKit
import SwiftUI
import QuartzCore

// WindowServer background blur. The masked visual-effect view paints the region;
// this call supplies the actual Gaussian blur without a visible material tint.
private typealias CGSConnectionID = UInt32
@_silgen_name("CGSDefaultConnectionForThread")
private func CGSDefaultConnectionForThread() -> CGSConnectionID
@_silgen_name("CGSSetWindowBackgroundBlurRadius")
@discardableResult
private func CGSSetWindowBackgroundBlurRadius(
    _ connection: CGSConnectionID,
    _ windowNumber: UInt32,
    _ radius: UInt32
) -> Int32

private func applyWindowBackgroundBlur(_ window: NSWindow, radius: UInt32) {
    guard window.windowNumber > 0 else { return }
    CGSSetWindowBackgroundBlurRadius(
        CGSDefaultConnectionForThread(),
        UInt32(window.windowNumber),
        radius
    )
}

private func backdropSpreadCurve(_ raw: CGFloat) -> CGFloat {
    pow(min(max(raw, 0), 1), 1.75)
}

private func backdropIntensityCurve(_ raw: CGFloat) -> CGFloat {
    pow(min(max(raw, 0), 1), 1.15)
}

/// Floating overlay window that shows a radial pie menu at the cursor
/// when the trackpad is engaged. Individual glass elements, macOS 26 style.
/// Supports recursive sub-category rings.
final class SelectionOverlay {

    private var window: NSWindow?
    private var hostView: NSHostingView<OverlayRadialView>?

    /// Screen-space center of the overlay (after show).
    var center: CGPoint = .zero

    func show(engine: SessionEngine) {
        let size = CGFloat(engine.overlayWindowSize)

        if window == nil {
            let frame = NSRect(x: 0, y: 0, width: size, height: size)
            let view = OverlayRadialView(engine: engine)
            let hv = NSHostingView(rootView: view)
            hv.frame = frame
            // Layer-backed so appear/disappear run as GPU-composited
            // Core Animation transitions instead of CPU redraws.
            hv.wantsLayer = true
            hv.layerContentsRedrawPolicy = .onSetNeedsDisplay
            self.hostView = hv

            let w = NSWindow(
                contentRect: frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            w.isOpaque = false
            w.backgroundColor = .clear
            w.level = .screenSaver
            w.ignoresMouseEvents = true
            w.hasShadow = false
            w.collectionBehavior = [.canJoinAllSpaces, .stationary]
            w.contentView = hv
            self.window = w
        } else {
            let frame = NSRect(x: 0, y: 0, width: size, height: size)
            hostView?.frame = frame
            hostView?.rootView = OverlayRadialView(engine: engine)
        }

        let cursorLoc = NSEvent.mouseLocation
        let origin = NSPoint(
            x: cursorLoc.x - size / 2,
            y: cursorLoc.y - size / 2
        )
        center = CGPoint(x: cursorLoc.x, y: cursorLoc.y)
        window?.setFrame(NSRect(origin: origin, size: NSSize(width: size, height: size)), display: true)
        window?.alphaValue = 1.0
        window?.orderFrontRegardless()
        if let window {
            let settings = AppSettings.shared
            let enabled = settings.overlayBackdropSpread > 0.001
                && settings.overlayBackdropIntensity > 0.001
            let radius = enabled
                ? UInt32(10 + backdropIntensityCurve(CGFloat(settings.overlayBackdropIntensity)) * 30)
                : 0
            applyWindowBackgroundBlur(window, radius: radius)
        }
        playAppear()
    }

    func hide() {
        guard let layer = hostView?.layer, window?.isVisible == true else {
            window?.orderOut(nil)
            return
        }
        // Fade + slight shrink, then order out.
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.window?.orderOut(nil)
            layer.opacity = 1
            layer.transform = CATransform3DIdentity
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.0
        fade.duration = 0.14
        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.fromValue = 1.0
        shrink.toValue = 0.94
        shrink.duration = 0.14
        shrink.timingFunction = CAMediaTimingFunction(name: .easeIn)
        layer.opacity = 0
        layer.add(fade, forKey: "fractalFade")
        layer.add(shrink, forKey: "fractalShrink")
        CATransaction.commit()
    }

    private func playAppear() {
        guard let layer = hostView?.layer else { return }
        layer.removeAllAnimations()
        layer.opacity = 1
        layer.transform = CATransform3DIdentity
        // Anchor scale at the center of the view.
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = CGPoint(x: layer.bounds.midX, y: layer.bounds.midY)

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.0
        fade.toValue = 1.0
        fade.duration = 0.16
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let pop = CASpringAnimation(keyPath: "transform.scale")
        pop.fromValue = 0.88
        pop.toValue = 1.0
        pop.mass = 0.7
        pop.stiffness = 260
        pop.damping = 20
        pop.duration = pop.settlingDuration

        layer.add(fade, forKey: "fractalFade")
        layer.add(pop, forKey: "fractalPop")
    }
}

// MARK: - Fractal-tree menu view

private struct OverlayRadialView: View {
    var engine: SessionEngine

    var body: some View {
        let branches = engine.buildTree()
        let windowSize = CGSize(width: engine.overlayWindowSize, height: engine.overlayWindowSize)
        let center = CGPoint(x: windowSize.width / 2, y: windowSize.height / 2)
        let overlayOpacity = AppSettings.shared.overlayOpacity
        let labelPlacements = makeTreeLabelPlacements(
            branches: branches,
            center: center,
            activeLevel: engine.lockedDepth,
            rootReveal: CGFloat(engine.revealProgress),
            ringReveal: engine.ringRevealProgress.map { CGFloat($0) },
            opacity: overlayOpacity
        )
        let backdropGeometry = TreeBackdropGeometry(
            size: windowSize,
            center: center,
            trunkTip: CGPoint(
                x: center.x + TreeLayout.trunkTip(engine.treeConfig).x,
                y: center.y
            ),
            activeLevel: engine.lockedDepth,
            branches: branches.map { branch in
                TreeBackdropBranch(
                    start: CGPoint(x: center.x + branch.start.x, y: center.y - branch.start.y),
                    end: CGPoint(x: center.x + branch.end.x, y: center.y - branch.end.y),
                    angle: -branch.angle,
                    level: branch.level,
                    label: branch.info.label
                )
            },
            labelRects: labelPlacements.map(\.box)
        )

        ZStack {
            TreeBackdropEffect(
                geometry: backdropGeometry,
                spread: CGFloat(AppSettings.shared.overlayBackdropSpread),
                intensity: CGFloat(AppSettings.shared.overlayBackdropIntensity)
            )

            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let op = overlayOpacity
            let config = engine.treeConfig
            let reveal = CGFloat(engine.revealProgress)
            let maxLevels = max(1, engine.maxMenuDepth() + 1)

            // Math coords (origin = trunk base, +y up) → canvas coords (+y down).
            func toCanvas(_ p: CGPoint) -> CGPoint {
                CGPoint(x: center.x + p.x, y: center.y - p.y)
            }
            // Per-level growth fraction so branches "draw in" — used for both the
            // initial fan-out and re-fanning when the cursor moves back a level.
            func levelReveal(_ level: Int) -> CGFloat {
                if level < engine.ringRevealProgress.count {
                    return CGFloat(engine.ringRevealProgress[level])
                }
                return level == 0 ? reveal : 0
            }

            // ── Trunk (grows first, from the cursor outward) ──
            let trunkTip = toCanvas(TreeLayout.trunkTip(config))
            let trunkFrac = min(reveal * 1.8, 1.0)
            let trunkEnd = CGPoint(
                x: center.x + (trunkTip.x - center.x) * trunkFrac,
                y: center.y + (trunkTip.y - center.y) * trunkFrac
            )
            drawSegment(context, from: center, to: trunkEnd,
                        width: 9, color: Color(red: 0.42, green: 0.30, blue: 0.20),
                        glow: nil, op: op)

            // ── Cancel hub at the trunk base ──
            let hubR: CGFloat = 6
            let hubRect = CGRect(x: center.x - hubR, y: center.y - hubR,
                                 width: hubR * 2, height: hubR * 2)
            context.fill(Circle().path(in: hubRect),
                         with: .color(Color(white: 0.10).opacity(0.7 * op)))
            context.stroke(Circle().path(in: hubRect),
                           with: .color(.white.opacity(0.4 * op)), lineWidth: 0.5)

            // ── Branch lines (painted first, behind every joint/icon) ──
            for branch in branches {
                let frac = levelReveal(branch.level)
                guard frac > 0.001 else { continue }

                let start = toCanvas(branch.start)
                let tip = toCanvas(branch.end)
                let dx = tip.x - start.x
                let dy = tip.y - start.y
                let length = hypot(dx, dy)
                guard length > 0.001 else { continue }
                let unitX = dx / length
                let unitY = dy / length
                let jointRadius: CGFloat = 16
                // Child branches leave their parent at its rim, and every
                // branch stops at the child rim. This keeps center-to-center
                // geometry from showing through translucent node interiors.
                let startInset = branch.level > 0 ? min(jointRadius, length * 0.25) : 0
                let endInset = min(jointRadius, max(0, length - startInset))
                let visibleStart = CGPoint(
                    x: start.x + unitX * startInset,
                    y: start.y + unitY * startInset
                )
                let visibleTip = CGPoint(
                    x: tip.x - unitX * endInset,
                    y: tip.y - unitY * endInset
                )
                let drawnEnd = CGPoint(
                    x: visibleStart.x + (visibleTip.x - visibleStart.x) * frac,
                    y: visibleStart.y + (visibleTip.y - visibleStart.y) * frac
                )

                let base = rgb(branch.info.colorHex)
                let lightenT = maxLevels > 1
                    ? min(0.6, Double(branch.level) / Double(maxLevels - 1) * 0.65) : 0
                let normalColor = mix(base, (1, 1, 1), lightenT)
                // Use the same selection tint at every depth. Otherwise the
                // depth lightening compounds with selection and washes out the
                // glow on second- and later-level branches.
                let selectedColor = mix(base, (1, 1, 1), 0.3)
                let col = branch.isSelected ? selectedColor : normalColor

                let width = max(1.6, 6.5 * pow(0.7, CGFloat(branch.level)))
                    + (branch.isSelected ? 1.8 : 0)
                let glow: Color? = branch.isSelected ? selectedColor : nil

                drawSegment(context, from: visibleStart, to: drawnEnd,
                            width: width, color: col, glow: glow, op: op)
            }

            // ── Node joints (above all branch lines) ──
            // Constant joint radius for ALL layout math — selection enlarges the
            // drawing only, never the collision geometry, so hovering an item
            // can never push other labels around.
            for branch in branches {
                let frac = levelReveal(branch.level)
                guard frac > 0.88 else { continue }

                let labelAlpha = min((Double(frac) - 0.88) / 0.12, 1.0) * op
                let tip = toCanvas(branch.end)

                let base = rgb(branch.info.colorHex)
                let leafColor = branch.info.isCategory
                    ? mix(base, (1, 1, 1), 0.28)
                    : mix(base, (0.40, 0.80, 0.36), 0.55)
                _ = drawNodeJoint(context, at: tip,
                                  color: leafColor,
                                  systemImage: branch.info.systemImage,
                                  selected: branch.isSelected,
                                  op: op * labelAlpha)
            }

        }

            // Keep labels in their own compositing layer. Difference blending
            // makes white glyphs dark over light content and light over dark
            // content without exposing the underlying pixels to the app.
            Canvas { context, _ in
                for placement in labelPlacements {
                    drawTreeText(context, at: placement.at, text: placement.text,
                                 selected: placement.selected, opacity: placement.alpha,
                                 anchor: placement.leading ? .leading : .trailing)
                }
            }
            .blendMode(.difference)
            .allowsHitTesting(false)
        }
        .frame(width: windowSize.width, height: windowSize.height)
    }

    // MARK: - Tree drawing helpers

    /// Stroke a rounded line, optionally with a soft glow underneath.
    private func drawSegment(
        _ context: GraphicsContext,
        from a: CGPoint, to b: CGPoint,
        width: CGFloat, color: Color, glow: Color?, op: Double
    ) {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)

        if let glow {
            var g = context
            g.addFilter(.blur(radius: 6))
            g.stroke(path, with: .color(glow.opacity(0.6 * op)),
                     style: StrokeStyle(lineWidth: width + 3, lineCap: .round))
        }
        context.stroke(path, with: .color(color.opacity(op)),
                       style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    /// Draw a circular joint at a branch tip with its icon inside. Returns its
    /// diameter so callers can place text beyond it.
    @discardableResult
    private func drawNodeJoint(
        _ context: GraphicsContext,
        at p: CGPoint, color: Color,
        systemImage: String, selected: Bool, op: Double
    ) -> CGFloat {
        let scale: CGFloat = selected ? 1.18 : 1.0
        let diameter: CGFloat = 32 * scale
        let rect = CGRect(x: p.x - diameter / 2, y: p.y - diameter / 2,
                          width: diameter, height: diameter)
        let joint = Circle().path(in: rect)

        if selected {
            var glow = context
            glow.addFilter(.blur(radius: 5))
            glow.fill(joint, with: .color(color.opacity(0.7 * op)))
        }
        context.fill(joint, with: .radialGradient(
            Gradient(colors: [color.opacity(op), color.opacity(0.6 * op)]),
            center: CGPoint(x: p.x - diameter * 0.22, y: p.y - diameter * 0.25),
            startRadius: 0, endRadius: diameter / 2))
        context.stroke(joint, with: .color(.white.opacity((selected ? 0.65 : 0.38) * op)),
                       lineWidth: selected ? 1.2 : 0.7)
        context.draw(
            Text(Image(systemName: systemImage))
                .font(.system(size: 14 * min(scale, 1.1), weight: .semibold))
                .foregroundColor(.white.opacity(op)),
            at: p
        )
        return diameter
    }

    /// Draw a text label (no icon) at an anchor point.
    private func drawTreeText(
        _ context: GraphicsContext,
        at p: CGPoint, text: String, selected: Bool, opacity: Double,
        anchor: UnitPoint = .leading
    ) {
        var attributes = AttributeContainer()
        attributes.strokeColor = NSColor.black.withAlphaComponent(0.72 * opacity)
        // Negative width draws a true hairline outline while retaining the fill.
        attributes.strokeWidth = -2.5
        let label = Text(AttributedString(text, attributes: attributes))
            .font(.system(size: 12, weight: selected ? .bold : .regular, design: .rounded))
            .foregroundColor(.white.opacity(opacity))
        context.draw(label, at: p, anchor: anchor)
    }

    // MARK: - Label collision helpers

    /// True if an axis-aligned rect intersects a circle.
    private func rectIntersectsCircle(_ r: CGRect, _ c: CGPoint, _ radius: CGFloat) -> Bool {
        let nx = min(max(c.x, r.minX), r.maxX)
        let ny = min(max(c.y, r.minY), r.maxY)
        let dx = c.x - nx, dy = c.y - ny
        return dx * dx + dy * dy < radius * radius
    }

    /// True if a line segment intersects a rect (edges or endpoints inside).
    private func segmentIntersectsRect(_ p1: CGPoint, _ p2: CGPoint, _ r: CGRect) -> Bool {
        if r.contains(p1) || r.contains(p2) { return true }
        let tl = CGPoint(x: r.minX, y: r.minY)
        let tr = CGPoint(x: r.maxX, y: r.minY)
        let bl = CGPoint(x: r.minX, y: r.maxY)
        let br = CGPoint(x: r.maxX, y: r.maxY)
        return segmentsIntersect(p1, p2, tl, tr) || segmentsIntersect(p1, p2, tr, br)
            || segmentsIntersect(p1, p2, br, bl) || segmentsIntersect(p1, p2, bl, tl)
    }

    private func segmentsIntersect(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Bool {
        func ccw(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) -> Bool {
            (r.y - p.y) * (q.x - p.x) > (q.y - p.y) * (r.x - p.x)
        }
        return ccw(a, c, d) != ccw(b, c, d) && ccw(a, b, c) != ccw(a, b, d)
    }

    // MARK: - Color helpers

    private func rgb(_ hex: String) -> (Double, Double, Double) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6, let v = UInt64(h, radix: 16) else { return (0.30, 0.50, 0.90) }
        return (Double((v >> 16) & 0xFF) / 255,
                Double((v >> 8) & 0xFF) / 255,
                Double(v & 0xFF) / 255)
    }

    private func mix(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ t: Double) -> Color {
        Color(red: a.0 + (b.0 - a.0) * t,
              green: a.1 + (b.1 - a.1) * t,
              blue: a.2 + (b.2 - a.2) * t)
    }

    // MARK: - Legacy drawing helpers (unused)

    private func drawGlassSlice(
        context: GraphicsContext, center: CGPoint,
        innerR: CGFloat, outerR: CGFloat,
        a1: CGFloat, a2: CGFloat,
        color: Color, isSelected: Bool,
        baseOpacity: Double
    ) {
        // Selected slice pops outward slightly.
        let outR = isSelected ? outerR + 4 : outerR
        let mid = (a1 + a2) / 2
        // Overall overlay opacity: 1.0 = solid, lower = see-through.
        let op = AppSettings.shared.overlayOpacity

        var path = Path()
        path.move(to: pointOnCircle(center, innerR, a1))
        path.addArc(center: center, radius: outR,
                     startAngle: .radians(a1), endAngle: .radians(a2), clockwise: false)
        path.addLine(to: pointOnCircle(center, innerR, a2))
        path.addArc(center: center, radius: innerR,
                     startAngle: .radians(a2), endAngle: .radians(a1), clockwise: true)
        path.closeSubpath()

        _ = baseOpacity
        // Solid dark backing whose alpha is driven by the opacity setting:
        // at 100% it fully hides the screen behind the slice.
        var shadowCtx = context
        shadowCtx.addFilter(.shadow(color: .black.opacity((isSelected ? 0.45 : 0.30) * op),
                                    radius: isSelected ? 7 : 4, x: 0, y: 2))
        shadowCtx.fill(path, with: .color(Color(white: 0.13).opacity(op)))

        // Radial glass gradient: darker at the inner edge, tinted brighter outward.
        let gInner = pointOnCircle(center, innerR, mid)
        let gOuter = pointOnCircle(center, outR, mid)
        context.fill(
            path,
            with: .linearGradient(
                Gradient(colors: [
                    color.opacity((isSelected ? 0.28 : 0.12) * op),
                    color.opacity((isSelected ? 0.62 : 0.32) * op)
                ]),
                startPoint: gInner, endPoint: gOuter
            )
        )
        // Top sheen.
        context.fill(
            path,
            with: .linearGradient(
                Gradient(colors: [.white.opacity((isSelected ? 0.14 : 0.07) * op),
                                  .white.opacity(0.0)]),
                startPoint: gOuter, endPoint: gInner
            )
        )
        context.stroke(path, with: .color(.white.opacity((isSelected ? 0.60 : 0.22) * op)),
                       lineWidth: isSelected ? 1.0 : 0.5)
        if isSelected {
            var glowCtx = context
            glowCtx.addFilter(.blur(radius: 7))
            glowCtx.stroke(path, with: .color(color.opacity(0.55 * op)), lineWidth: 3)
        }
    }

    /// Hub content: highlighted item's name (wrapped to two lines if needed),
    /// or a dismiss ✕ when nothing is highlighted.
    private func drawHubContent(
        context: GraphicsContext, center: CGPoint,
        radius: CGFloat, engine: SessionEngine,
        categories: [RadialCategory], alpha: Double
    ) {
        var label: String? = nil
        let path = engine.selectionPath
        if let catIdx = engine.selectedCategoryIndex, categories.indices.contains(catIdx) {
            label = categories[catIdx].label
            // Deepest highlighted item wins.
            for depth in stride(from: path.count - 1, through: 1, by: -1) {
                let items = engine.itemsAtDepth(depth)
                if items.indices.contains(path[depth]) {
                    label = items[path[depth]].label
                    break
                }
            }
        }

        guard let label else {
            context.draw(
                Text("✕")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5 * alpha)),
                at: center
            )
            return
        }

        // Fit inside the hub: wrap two-word labels, shrink otherwise.
        let maxWidth = radius * 1.75
        func fontSize(for text: String) -> CGFloat {
            let fitted = maxWidth / (CGFloat(text.count) * 0.55)
            return min(11, max(8, fitted))
        }
        let words = label.split(separator: " ").map(String.init)
        let oneLineSize = fontSize(for: label)
        if words.count >= 2, CGFloat(label.count) * 0.55 * 11 > maxWidth {
            let split = (words.count + 1) / 2
            let l1 = words[0..<split].joined(separator: " ")
            let l2 = words[split...].joined(separator: " ")
            let size = min(fontSize(for: l1), fontSize(for: l2))
            context.draw(hubText(l1, size: size, alpha: alpha),
                         at: CGPoint(x: center.x, y: center.y - size * 0.62))
            context.draw(hubText(l2, size: size, alpha: alpha),
                         at: CGPoint(x: center.x, y: center.y + size * 0.62))
        } else {
            context.draw(hubText(label, size: oneLineSize, alpha: alpha), at: center)
        }
    }

    private func hubText(_ s: String, size: CGFloat, alpha: Double) -> Text {
        Text(s)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.92 * alpha))
    }

    private func pointOnCircle(_ center: CGPoint, _ radius: CGFloat, _ angle: CGFloat) -> CGPoint {
        CGPoint(x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle))
    }

    /// Draw an SF Symbol icon rotated to follow the arc at the given angle.
    private func drawRotatedIcon(
        systemName: String,
        context: GraphicsContext,
        at point: CGPoint,
        angle: CGFloat,
        fontSize: CGFloat,
        opacity: Double
    ) {
        // Mirror the same logic used by drawCurvedText: icons in the upper half
        // (sin ≤ 0) point outward; icons in the lower half point inward.
        // Both branches keep rotation in [-π/2, π/2] so the icon is never upside-down.
        let rotation = sin(angle) <= 0 ? angle + .pi / 2 : angle - .pi / 2
        var iconCtx = context
        iconCtx.translateBy(x: point.x, y: point.y)
        iconCtx.rotate(by: .radians(rotation))
        iconCtx.draw(
            Text(Image(systemName: systemName))
                .font(.system(size: fontSize, weight: .medium))
                .foregroundStyle(.white.opacity(opacity)),
            at: .zero
        )
    }

    /// Draw a slice label, wrapping onto two curved lines when a multi-word
    /// label doesn't fit its slice arc at full size.
    private func drawCurvedLabel(
        _ text: String,
        context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        midAngle: CGFloat,
        fontSize: CGFloat,
        maxAngle: CGFloat,
        opacity: Double
    ) {
        let fitsOneLine = (fontSize * 0.55 * CGFloat(text.count)) / radius <= maxAngle
        let words = text.split(separator: " ").map(String.init)

        if !fitsOneLine && words.count >= 2 {
            // Balanced two-line split at a word boundary.
            var line1 = words[0], line2 = words[1...].joined(separator: " ")
            var bestDiff = abs(line1.count - line2.count)
            for k in 2..<words.count {
                let l1 = words[0..<k].joined(separator: " ")
                let l2 = words[k...].joined(separator: " ")
                let diff = abs(l1.count - l2.count)
                if diff < bestDiff { bestDiff = diff; line1 = l1; line2 = l2 }
            }
            // Visually-top line: larger radius on the upper half of the ring,
            // smaller radius on the lower half (where glyphs are flipped).
            let flipped = sin(midAngle) > 0
            let dr = fontSize * 0.62
            let lineSize = fontSize - 1
            drawCurvedText(flipped ? line2 : line1, context: context, center: center,
                           radius: radius + dr, midAngle: midAngle,
                           fontSize: lineSize, maxAngle: maxAngle, opacity: opacity)
            drawCurvedText(flipped ? line1 : line2, context: context, center: center,
                           radius: radius - dr, midAngle: midAngle,
                           fontSize: lineSize, maxAngle: maxAngle, opacity: opacity)
            return
        }

        drawCurvedText(text, context: context, center: center,
                       radius: radius, midAngle: midAngle,
                       fontSize: fontSize, maxAngle: maxAngle, opacity: opacity)
    }

    private func drawCurvedText(
        _ text: String,
        context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        midAngle: CGFloat,
        fontSize: CGFloat,
        maxAngle: CGFloat,
        opacity: Double
    ) {
        var chars = Array(text)
        guard !chars.isEmpty, maxAngle > 0 else { return }

        // ── Auto-fit: shrink the font until the text fits the slice arc, ──
        // ── down to a minimum size; then truncate with an ellipsis.      ──
        let minFontSize: CGFloat = 8
        func arcAngle(charCount: Int, size: CGFloat) -> CGFloat {
            (size * 0.55 * CGFloat(charCount)) / radius
        }
        var size = fontSize
        if arcAngle(charCount: chars.count, size: size) > maxAngle {
            let fitted = maxAngle * radius / (0.55 * CGFloat(chars.count))
            size = max(minFontSize, fitted)
        }
        if arcAngle(charCount: chars.count, size: size) > maxAngle {
            let maxChars = max(2, Int(maxAngle * radius / (0.55 * size)))
            if maxChars < chars.count {
                chars = Array(chars.prefix(maxChars - 1)) + ["\u{2026}"]
            }
        }

        let charWidth: CGFloat = size * 0.55
        let totalAngle = (charWidth * CGFloat(chars.count)) / radius
        let readsCW = sin(midAngle) <= 0

        for (i, char) in chars.enumerated() {
            let t = (CGFloat(i) + 0.5) / CGFloat(chars.count)
            let charAngle: CGFloat
            let rotation: CGFloat

            if readsCW {
                charAngle = midAngle - totalAngle / 2 + t * totalAngle
                rotation = charAngle + .pi / 2
            } else {
                charAngle = midAngle + totalAngle / 2 - t * totalAngle
                rotation = charAngle - .pi / 2
            }

            let pt = CGPoint(
                x: center.x + radius * cos(charAngle),
                y: center.y + radius * sin(charAngle)
            )

            var charCtx = context
            charCtx.translateBy(x: pt.x, y: pt.y)
            charCtx.rotate(by: .radians(rotation))
            charCtx.draw(
                Text(String(char))
                    .font(.system(size: size, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(opacity)),
                at: .zero
            )
        }
    }

    private func colorFromHex(_ hex: String) -> Color {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return .blue }
        let r = Double((val >> 16) & 0xFF) / 255
        let g = Double((val >> 8) & 0xFF) / 255
        let b = Double(val & 0xFF) / 255
        return Color(red: r, green: g, blue: b)
    }
}

private struct TreeLabelPlacement {
    let at: CGPoint
    let box: CGRect
    let leading: Bool
    let text: String
    let selected: Bool
    let alpha: Double
}

/// Resolve collision-free label positions once for both drawing and backdrop masking.
private func makeTreeLabelPlacements(
    branches: [TreeLayout.Branch],
    center: CGPoint,
    activeLevel: Int,
    rootReveal: CGFloat,
    ringReveal: [CGFloat],
    opacity: Double
) -> [TreeLabelPlacement] {
    func reveal(for level: Int) -> CGFloat {
        if ringReveal.indices.contains(level) { return ringReveal[level] }
        return level == 0 ? rootReveal : 0
    }

    func canvasPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: center.x + point.x, y: center.y - point.y)
    }

    typealias LabelRequest = (
        tip: CGPoint,
        baseAngle: CGFloat,
        radius: CGFloat,
        leading: Bool,
        text: String,
        selected: Bool,
        alpha: Double
    )

    let jointRadius: CGFloat = 16
    var circles: [(center: CGPoint, radius: CGFloat)] = []
    var segments: [(start: CGPoint, end: CGPoint)] = []
    var requests: [LabelRequest] = []

    for branch in branches {
        let fraction = reveal(for: branch.level)
        guard fraction > 0.88 else { continue }

        let start = canvasPoint(branch.start)
        let tip = canvasPoint(branch.end)
        circles.append((tip, jointRadius))
        segments.append((start, tip))

        guard branch.level == activeLevel else { continue }
        let angle = atan2(tip.y - start.y, tip.x - start.x)
        requests.append((
            tip: tip,
            baseAngle: angle,
            radius: jointRadius,
            leading: cos(angle) >= -0.25,
            text: branch.info.label,
            selected: branch.isSelected,
            alpha: min((Double(fraction) - 0.88) / 0.12, 1) * opacity
        ))
    }

    let distances: [CGFloat] = [jointRadius + 7, jointRadius + 14,
                                jointRadius + 22, jointRadius + 32]
    let angleOffsets: [CGFloat] = [0, 0.18, -0.18, 0.36, -0.36,
                                   0.55, -0.55, 0.8, -0.8, 1.1, -1.1]
    var occupied: [CGRect] = []
    var placements: [TreeLabelPlacement] = []

    for request in requests.sorted(by: { $0.tip.y < $1.tip.y }) {
        let height: CGFloat = 16
        let width = max(14, CGFloat(request.text.count) * 7.6 + 6)
        var chosen: (point: CGPoint, box: CGRect)?
        var fallback: (point: CGPoint, box: CGRect)?

        search: for distance in distances {
            for offset in angleOffsets {
                let angle = request.baseAngle + offset
                let point = CGPoint(
                    x: request.tip.x + cos(angle) * distance,
                    y: request.tip.y + sin(angle) * distance
                )
                let textRect = request.leading
                    ? CGRect(x: point.x, y: point.y - height / 2, width: width, height: height)
                    : CGRect(x: point.x - width, y: point.y - height / 2, width: width, height: height)
                let box = textRect.insetBy(dx: -2, dy: -2)
                if fallback == nil { fallback = (point, box) }

                var available = true
                for circle in circles
                    where treeRectIntersectsCircle(box, center: circle.center, radius: circle.radius) {
                    available = false
                    break
                }
                if available {
                    for segment in segments
                        where treeSegmentIntersectsRect(segment.start, segment.end, box) {
                        available = false
                        break
                    }
                }
                if available, occupied.contains(where: { $0.intersects(box) }) {
                    available = false
                }
                if available {
                    chosen = (point, box)
                    break search
                }
            }
        }

        guard let placement = chosen ?? fallback else { continue }
        occupied.append(placement.box)
        placements.append(TreeLabelPlacement(
            at: placement.point,
            box: placement.box,
            leading: request.leading,
            text: request.text,
            selected: request.selected,
            alpha: request.alpha
        ))
    }

    return placements
}

private func treeRectIntersectsCircle(_ rect: CGRect, center: CGPoint, radius: CGFloat) -> Bool {
    let nearestX = min(max(center.x, rect.minX), rect.maxX)
    let nearestY = min(max(center.y, rect.minY), rect.maxY)
    return pow(center.x - nearestX, 2) + pow(center.y - nearestY, 2) < radius * radius
}

private func treeSegmentIntersectsRect(_ start: CGPoint, _ end: CGPoint, _ rect: CGRect) -> Bool {
    if rect.contains(start) || rect.contains(end) { return true }
    let topLeft = CGPoint(x: rect.minX, y: rect.minY)
    let topRight = CGPoint(x: rect.maxX, y: rect.minY)
    let bottomLeft = CGPoint(x: rect.minX, y: rect.maxY)
    let bottomRight = CGPoint(x: rect.maxX, y: rect.maxY)
    return treeSegmentsIntersect(start, end, topLeft, topRight)
        || treeSegmentsIntersect(start, end, topRight, bottomRight)
        || treeSegmentsIntersect(start, end, bottomRight, bottomLeft)
        || treeSegmentsIntersect(start, end, bottomLeft, topLeft)
}

private func treeSegmentsIntersect(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Bool {
    func counterClockwise(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) -> Bool {
        (r.y - p.y) * (q.x - p.x) > (q.y - p.y) * (r.x - p.x)
    }
    return counterClockwise(a, c, d) != counterClockwise(b, c, d)
        && counterClockwise(a, b, c) != counterClockwise(a, b, d)
}

// MARK: - Backdrop blur

private struct TreeBackdropBranch: Equatable {
    let start: CGPoint
    let end: CGPoint
    let angle: CGFloat
    let level: Int
    let label: String
}

private struct TreeBackdropGeometry: Equatable {
    let size: CGSize
    let center: CGPoint
    let trunkTip: CGPoint
    let activeLevel: Int
    let branches: [TreeBackdropBranch]
    let labelRects: [CGRect]
}

/// A visual-effect sibling beneath the Canvas. Keeping the Canvas out of the
/// NSVisualEffectView preserves crisp, opaque labels while the screen behind it blurs.
private struct TreeBackdropEffect: NSViewRepresentable {
    let geometry: TreeBackdropGeometry
    let spread: CGFloat
    let intensity: CGFloat

    final class Coordinator {
        var renderKey: RenderKey?
    }

    struct RenderKey: Equatable {
        let geometry: TreeBackdropGeometry
        let spread: Int
        let intensity: Int
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .popover
        view.state = .active
        view.isEmphasized = false
        view.alphaValue = 0.07
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        let clampedSpread = min(max(spread, 0), 1)
        let clampedIntensity = min(max(intensity, 0), 1)
        let enabled = clampedSpread > 0.001 && clampedIntensity > 0.001
        // The material only supplies non-transparent pixels for the blur mask.
        // Keep its tint nearly invisible, matching Kopy's working setup.
        view.alphaValue = enabled ? 0.07 : 0

        if let window = view.window {
            let radius = enabled
                ? UInt32(10 + backdropIntensityCurve(clampedIntensity) * 30)
                : 0
            applyWindowBackgroundBlur(window, radius: radius)
        }

        let key = RenderKey(
            geometry: geometry,
            spread: Int((clampedSpread * 1000).rounded()),
            intensity: Int((clampedIntensity * 1000).rounded())
        )
        guard context.coordinator.renderKey != key else { return }
        context.coordinator.renderKey = key

        guard clampedSpread > 0.001, clampedIntensity > 0.001 else {
            view.maskImage = transparentMask(size: geometry.size)
            return
        }
        view.maskImage = makeMaskImage(
            geometry: geometry,
            spread: clampedSpread,
            intensity: clampedIntensity,
            scale: view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        )
    }

    private func transparentMask(size: CGSize) -> NSImage {
        NSImage(size: size)
    }

    private func makeMaskImage(
        geometry: TreeBackdropGeometry,
        spread: CGFloat,
        intensity: CGFloat,
        scale: CGFloat
    ) -> NSImage? {
        let spreadCurve = backdropSpreadCurve(spread)
        let intensityCurve = backdropIntensityCurve(intensity)
        let renderer = ImageRenderer(
            content: TreeBackdropMask(geometry: geometry, spread: spread)
                .compositingGroup()
                .opacity(0.88 + intensityCurve * 0.12)
                .blur(radius: 2 + spreadCurve * 18)
                .frame(width: geometry.size.width, height: geometry.size.height)
        )
        renderer.proposedSize = ProposedViewSize(geometry.size)
        renderer.scale = scale
        return renderer.nsImage
    }
}

private struct TreeBackdropMask: View {
    let geometry: TreeBackdropGeometry
    let spread: CGFloat

    var body: some View {
        Canvas { context, _ in
            let spreadCurve = backdropSpreadCurve(spread)
            let branchWidth = 18 + spreadCurve * 34
            let nodeDiameter = 46 + spreadCurve * 38

            strokeLine(&context, from: geometry.center, to: geometry.trunkTip,
                       width: branchWidth + 8)

            for branch in geometry.branches {
                strokeLine(&context, from: branch.start, to: branch.end, width: branchWidth)

                let nodeRect = CGRect(
                    x: branch.end.x - nodeDiameter / 2,
                    y: branch.end.y - nodeDiameter / 2,
                    width: nodeDiameter,
                    height: nodeDiameter
                )
                context.fill(Circle().path(in: nodeRect), with: .color(.white))
            }

            let labelPadX = 5 + spreadCurve * 16
            let labelPadY = 3 + spreadCurve * 9
            for rect in geometry.labelRects {
                let labelRect = rect.insetBy(dx: -labelPadX, dy: -labelPadY)
                context.fill(
                    RoundedRectangle(cornerRadius: labelRect.height / 2).path(in: labelRect),
                    with: .color(.white)
                )
            }
        }
    }

    private func strokeLine(
        _ context: inout GraphicsContext,
        from start: CGPoint,
        to end: CGPoint,
        width: CGFloat
    ) {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(path, with: .color(.white),
                       style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}
