import SwiftUI

// MARK: - Root View

struct ContentView: View {
    private let engine = SessionEngine.shared
    @State private var selectedTab: SettingsTab = .menu

    enum SettingsTab: String, CaseIterable {
        case menu = "Menu", trackpad = "Trackpad", shortcut = "Shortcut"
        case appearance = "Appearance", general = "General"

        var icon: String {
            switch self {
            case .menu: "square.grid.2x2"; case .trackpad: "hand.point.up.left"
            case .shortcut: "keyboard"; case .appearance: "paintbrush"; case .general: "gearshape"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Tab bar (Safari-settings style: centered, icon over label) ──
            HStack(spacing: 0) {
                // Traffic-light spacer so tabs clear the window controls
                Spacer().frame(width: 76)

                Spacer()
                HStack(spacing: 4) {
                    ForEach(SettingsTab.allCases, id: \.self) { tab in
                        let active = selectedTab == tab
                        Button { selectedTab = tab } label: {
                            VStack(spacing: 3) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 17, weight: .regular))
                                    .frame(height: 20)
                                Text(tab.rawValue)
                                    .font(.caption)
                            }
                            .foregroundStyle(active ? Color.accentColor : Color.secondary)
                            .frame(width: 74, height: 50)
                            .background(active ? Color.accentColor.opacity(0.12) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }
                }
                Spacer()

                // Start / Stop button aligned to the right
                Button {
                    if engine.isRunning { engine.stop() } else { engine.start() }
                } label: {
                    Image(systemName: engine.isRunning ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(engine.isRunning ? .red : .green)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(engine.isRunning ? "Stop session" : "Start session")
                .frame(width: 76)
            }
            .padding(.top, 4)
            .padding(.bottom, 2)

            Divider()

            // ── Content ───────────────────────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedTab {
                    case .menu:       menuTab
                    case .trackpad:   trackpadTab
                    case .shortcut:   shortcutTab
                    case .appearance: appearanceTab
                    case .general:    generalTab
                    }
                }
                .padding(16)
            }

            // ── Last-action toast (only visible after an action fires) ─────
            if engine.finalizedZoneID != nil {
                LastActionBar(engine: engine)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: engine.finalizedZoneID != nil)
        .onAppear { engine.start() }
        .onReceive(NotificationCenter.default.publisher(for: .trackZoneToggleTracking)) { _ in
            if engine.isRunning { engine.stop() } else { engine.start() }
        }
    }

    // MARK: - Tabs

    @ViewBuilder private var menuTab: some View {
        SettingsSection(title: "Radial Menu") {
            HStack {
                Spacer()
                Text("Drag to reorder").font(.caption).foregroundStyle(.tertiary)
            }
            RadialMenuEditor()
        }
    }

    @ViewBuilder private var trackpadTab: some View {
        SettingsSection(title: "Trackpad") {
            SettingsToggle("Trackpad Trigger",
                isOn: Binding(get: { engine.settings.trackpadEnabled },
                              set: { engine.settings.trackpadEnabled = $0 }))

            if engine.settings.trackpadEnabled {
                Divider().padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Activation Style").font(.callout).foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { engine.settings.activationTrigger },
                        set: { engine.settings.activationTrigger = $0 })) {
                        ForEach(ActivationTrigger.allCases) { t in Text(t.label).tag(t) }
                    }
                    .labelsHidden().pickerStyle(.segmented)
                    Text(engine.settings.activationTrigger.help)
                        .font(.caption).foregroundStyle(.secondary)
                }

                Divider().padding(.vertical, 2)

                SettingsSlider("Hold Duration",
                    value: Binding(get: { engine.settings.activationHoldDuration },
                                   set: { engine.settings.activationHoldDuration = $0 }),
                    range: 0.10...1.50, step: 0.05, format: "%.2fs",
                    caption: "How long the finger must rest before the menu opens")

                SettingsSlider("Ring Delay",
                    value: Binding(get: { engine.settings.ringDelay },
                                   set: { engine.settings.ringDelay = $0 }),
                    range: 0.05...0.80, step: 0.05, format: "%.2fs",
                    caption: "Delay before the loading ring appears — avoids flicker on quick taps")

                SettingsSlider("Activation Zone",
                    value: Binding(get: { engine.settings.activationMargin },
                                   set: { engine.settings.activationMargin = $0 }),
                    range: 0...40, step: 5, format: "%.0f%%",
                    caption: engine.settings.activationMargin > 0
                        ? "Ignores touches within \(Int(engine.settings.activationMargin))% of the left/right edges"
                        : "Touches anywhere on the trackpad can trigger the menu")

                Divider().padding(.vertical, 2)

                SettingsToggle("Lift to Select",
                    isOn: Binding(get: { engine.settings.liftToSelect },
                                  set: { engine.settings.liftToSelect = $0 }),
                    caption: engine.settings.liftToSelect
                        ? "Lift finger to confirm selection"
                        : "Click again to confirm selection")
            }
        }
    }

    @ViewBuilder private var shortcutTab: some View {
        SettingsSection(title: "Keyboard Shortcut") {
            HotkeyRecorderRow(settings: engine.settings)

            if engine.settings.hotkeyEnabled && engine.settings.hotkeyMode == .doubleTap {
                Divider().padding(.vertical, 2)
                SettingsSlider("Double-tap Window",
                    value: Binding(get: { engine.settings.doubleTapWindow },
                                   set: { engine.settings.doubleTapWindow = $0 }),
                    range: 0.15...0.80, step: 0.05, format: "%.2fs",
                    caption: "Maximum time between two presses to count as a double-tap")
            }
        }
    }

    @ViewBuilder private var appearanceTab: some View {
        SettingsSection(title: "Menu Appearance") {
            SettingsSlider("Ring Height",
                value: Binding(get: { engine.settings.ringHeight },
                               set: { engine.settings.ringHeight = $0 }),
                range: 30...100, step: 5, format: "%.0f pt",
                caption: "Radial thickness of each ring")

            Divider().padding(.vertical, 2)

            SettingsSlider("Slice Width",
                value: Binding(get: { engine.settings.selectionWidth },
                               set: { engine.settings.selectionWidth = $0 }),
                range: 20...80, step: 5, format: "%.0f pt",
                caption: "Arc width of each action slice in sub-rings")

            Divider().padding(.vertical, 2)

            SettingsSlider("Overlay Opacity",
                value: Binding(get: { engine.settings.overlayOpacity * 100 },
                               set: { engine.settings.overlayOpacity = $0 / 100 }),
                range: 30...100, step: 5, format: "%.0f%%",
                caption: "Lower keeps your screen content visible behind the menu")
        }
    }

    @ViewBuilder private var generalTab: some View {
        SettingsSection(title: "General") {
            SettingsSlider("Cooldown",
                value: Binding(get: { engine.settings.cooldownDuration },
                               set: { engine.settings.cooldownDuration = $0 }),
                range: 0.1...2.0, step: 0.1, format: "%.1fs",
                caption: "Wait after a selection before the menu can open again")

            Divider().padding(.vertical, 2)

            SettingsToggle("Pause While Typing",
                isOn: Binding(get: { engine.settings.pauseWhileTyping },
                              set: { engine.settings.pauseWhileTyping = $0 }),
                caption: "Disables tracking briefly after each keystroke")

            Divider().padding(.vertical, 2)

            SettingsToggle("Test Mode",
                isOn: Binding(get: { engine.settings.isTestMode },
                              set: { engine.settings.isTestMode = $0 }),
                caption: engine.settings.isTestMode
                    ? "⚠ Actions suppressed — menu works but nothing executes"
                    : "Simulates the menu without executing any actions")
        }
    }
}

// MARK: - Last-action toast

private struct LastActionBar: View {
    var engine: SessionEngine

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            if let zone = engine.finalizedZoneID {
                Text(zone).font(.callout.weight(.semibold))
            }
            if let desc = engine.lastFiredActionDescription {
                Text(desc).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { engine.clearFinalizedValue() } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Hotkey Recorder

private struct HotkeyRecorderRow: View {
    let settings: AppSettings
    @State private var isRecording = false
    @State private var keyMonitor: Any?
    @State private var firstPressCode: Int = -1
    @State private var firstPressTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Toggle row
            Toggle(isOn: Binding(get: { settings.hotkeyEnabled },
                                 set: { settings.hotkeyEnabled = $0 })) {
                Text("Keyboard Shortcut").font(.callout)
            }
            .toggleStyle(.switch)
            .frame(maxWidth: .infinity, alignment: .leading)

            if settings.hotkeyEnabled {
                // Recorder pill + clear button
                HStack(spacing: 8) {
                    Button { toggleRecording() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isRecording ? "record.circle" : "keyboard")
                                .foregroundStyle(isRecording ? Color.orange : Color.secondary)
                            Text(isRecording
                                 ? (firstPressCode >= 0 ? "Press again for double-tap…" : "Press shortcut…")
                                 : (settings.hotkeyKeyCode >= 0 ? settings.hotkeyDisplayString : "Click to set"))
                                .font(.system(.callout, design: .monospaced).weight(.medium))
                                .foregroundStyle(isRecording ? Color.orange : Color.primary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(minWidth: 44, minHeight: 28)
                        .background(isRecording
                                    ? Color.orange.opacity(0.10)
                                    : Color.primary.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isRecording ? Color.orange.opacity(0.6) : Color.clear,
                                          lineWidth: 1.5))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    if settings.hotkeyKeyCode >= 0 {
                        Button {
                            settings.hotkeyKeyCode = -1
                            settings.hotkeyModifiers = 0
                            settings.hotkeyKeyLabel = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 28, minHeight: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(captionText).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: settings.hotkeyEnabled) { _, enabled in if !enabled { stopRecording() } }
    }

    private var captionText: String {
        if isRecording { return "Press Esc to cancel  ·  Delete to clear" }
        if settings.hotkeyKeyCode < 0 { return "Press a key combo, or the same key twice for double-tap" }
        switch settings.hotkeyMode {
        case .combo:     return "Press to open  ·  press again to dismiss"
        case .doubleTap: return "Double-press \(settings.hotkeyKeyLabel) to open  ·  double-press again to dismiss"
        }
    }

    private func toggleRecording() { isRecording ? stopRecording() : startRecording() }

    private func startRecording() {
        isRecording = true; firstPressCode = -1
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                let code = Int(event.keyCode)
                guard AppSettings.isModifierKeyCode(code) else { return event }
                let flag = AppSettings.modifierFlagForKeyCode(code)
                guard !flag.isEmpty, event.modifierFlags.contains(flag) else { return event }
                self.handlePress(code: code, label: AppSettings.modifierKeyLabel(code), mods: 0)
                return event
            }
            let code = Int(event.keyCode)
            if code == 53 { self.stopRecording(); return nil }
            if code == 51 || code == 117 {
                self.settings.hotkeyKeyCode = -1; self.settings.hotkeyModifiers = 0
                self.settings.hotkeyKeyLabel = ""; self.stopRecording(); return nil
            }
            if AppSettings.isModifierKeyCode(code) { return nil }
            let mods = Int(event.modifierFlags.intersection([.command, .option, .shift, .control]).rawValue)
            self.handlePress(code: code, label: self.keyLabel(for: event), mods: mods)
            return nil
        }
    }

    private func handlePress(code: Int, label: String, mods: Int) {
        if firstPressCode == code {
            firstPressTimer?.invalidate(); firstPressTimer = nil
            commit(code: code, label: label, mods: 0, mode: .doubleTap)
        } else if firstPressCode < 0 {
            firstPressCode = code
            firstPressTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { _ in
                self.commit(code: code, label: label, mods: mods, mode: .combo)
            }
        } else {
            firstPressTimer?.invalidate(); firstPressCode = code
            firstPressTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { _ in
                self.commit(code: code, label: label, mods: mods, mode: .combo)
            }
        }
    }

    private func commit(code: Int, label: String, mods: Int, mode: HotkeyMode) {
        settings.hotkeyKeyCode = code; settings.hotkeyModifiers = mods
        settings.hotkeyKeyLabel = label; settings.hotkeyMode = mode
        stopRecording()
    }

    private func stopRecording() {
        firstPressTimer?.invalidate(); firstPressTimer = nil
        firstPressCode = -1; isRecording = false
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    private func keyLabel(for event: NSEvent) -> String {
        let special: [Int: String] = [
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "Esc",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4",
            96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12"
        ]
        if let name = special[Int(event.keyCode)] { return name }
        return (event.charactersIgnoringModifiers ?? "").uppercased()
    }
}

// MARK: - Settings Helpers

/// Glass-card section with a small ALL-CAPS header.
private struct SettingsSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.bottom, 2)
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

/// Consistent labelled slider with value readout and optional caption.
private struct SettingsSlider: View {
    var label: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var format: String
    var caption: String? = nil

    init(_ label: String, value: Binding<Double>, range: ClosedRange<Double>,
         step: Double, format: String, caption: String? = nil) {
        self.label = label; self._value = value
        self.range = range; self.step = step; self.format = format; self.caption = caption
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.callout)
                Spacer()
                Text(String(format: format, value))
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step).tint(.accentColor)
            if let caption {
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Toggle with an optional caption line underneath — left-aligned, full-width.
private struct SettingsToggle: View {
    var label: String
    @Binding var isOn: Bool
    var caption: String?

    init(_ label: String, isOn: Binding<Bool>, caption: String? = nil) {
        self.label = label; self._isOn = isOn; self.caption = caption
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(label, isOn: $isOn)
                .toggleStyle(.switch)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let caption {
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView().frame(width: 780, height: 560)
}
