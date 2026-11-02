import SwiftUI

struct FocusPage: View {
    @Bindable var model: NotchModel

    var body: some View {
        let focus = model.focus
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                durationTrigger
                meta
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(model.focusMenu == nil ? 1 : 0)
                controls(focus)
            }
            .frame(height: 54)
            Color.clear.frame(height: 18)
        }
        .frame(maxHeight: .infinity)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(NotchSpace.root)) } action: { model.focusPageFrame = $0 }
    }

    // MARK: Triggers

    private var durationTrigger: some View {
        Button { model.toggleFocusMenu(.duration) } label: {
            Text(liltClock(model.focus.remaining))
                .font(Lilt.font(46, .bold)).tracking(-1.38).monospacedDigit()
                .frame(minHeight: 54)
                .overlay(alignment: .trailing) { Chevron(visible: model.focusMenu == .duration).offset(x: 14) }
        }
        .buttonStyle(TriggerStyle(locked: model.focus.locked))
        .disabled(model.focus.locked)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(NotchSpace.root)) } action: { model.focusTriggerFrames[.duration] = $0 }
        .accessibilityLabel(durationLabel)
    }

    private var meta: some View {
        let focus = model.focus
        let note = focusNote
        return VStack(alignment: .leading, spacing: 4) {
            Button { model.toggleFocusMenu(.activity) } label: {
                HStack(spacing: 5) {
                    Text(focus.isBreak ? "Break" : activityName(focus.activity)).lineLimit(1)
                    Chevron(visible: model.focusMenu == .activity)
                }
                .font(Lilt.font(14))
                .foregroundStyle(Lilt.ink.mix(70))
                .frame(minHeight: 28)
            }
            .buttonStyle(TriggerStyle(locked: focus.locked))
            .disabled(focus.locked)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(NotchSpace.root)) } action: { model.focusTriggerFrames[.activity] = $0 }
            .accessibilityLabel(focus.isBreak ? "Break" : "Focus activity, \(activityName(focus.activity))")
            if !note.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(note)
                        .font(Lilt.font(11)).lineSpacing(1)
                        .foregroundStyle(Lilt.ink.mix(70))
                        .lineLimit(focus.error == nil ? 2 : 3)
                        .frame(maxWidth: 184, alignment: .leading)
                        .help(focus.error?.message ?? "")
                    if model.focusWithMusic, let error = focus.error {
                        if error.code == "permission" {
                            Button("Open Settings") { model.post(["action": "brainfmSettings"]) }.buttonStyle(LinkButtonStyle(size: 13))
                        } else {
                            Button("Open Brain.fm") { model.post(["action": "brainfm"]) }.buttonStyle(LinkButtonStyle(size: 13))
                        }
                    }
                }
            }
        }
    }

    private func controls(_ focus: FocusState) -> some View {
        let running = focus.phase == .running
        let completed = focus.phase == .completed
        let busy = focus.pending != nil
        return HStack(spacing: 4) {
            Button { model.focusPrimary() } label: { PlayPauseIcon(playing: running, animate: !model.reducedMotion) }
                .buttonStyle(IconButtonStyle(diameter: 48, prominent: true))
                .disabled(busy || !focus.ready || focus.restoring)
                .accessibilityLabel(primaryLabel)
                .help(primaryLabel)
            if [.running, .paused, .completed].contains(focus.phase) {
                Button("+5") { model.focusCommand("extend") }
                    .buttonStyle(PillButtonStyle())
                    .disabled(!focus.canExtend)
                    .accessibilityLabel("Extend focus by five minutes")
                    .help("Add 5 minutes")
            }
            if completed {
                Button("End") { model.focusCommand("reset") }
                    .buttonStyle(PillButtonStyle())
                    .disabled(busy || focus.restoring)
            } else {
                Button { model.focusCommand("reset") } label: { IconView(icon: .reset) }
                    .buttonStyle(IconButtonStyle())
                    .disabled(busy || !focus.ready || focus.restoring)
                    .accessibilityLabel("Reset the focus timer to \(minutesLabel)")
            }
        }
    }

    // MARK: Text

    private var minutesLabel: String {
        let minutes = model.focus.duration / 60
        return "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
    }

    private var durationLabel: String { "Focus duration, \(minutesLabel). \(liltClock(model.focus.remaining)) remaining." }

    private func activityName(_ activity: String) -> String { activity == "lightWork" ? "Light Work" : "Deep Work" }

    private var focusNote: String {
        let focus = model.focus
        let music = model.focusWithMusic
        if focus.restoring { return music ? "Checking Brain.fm…" : "Restoring timer…" }
        if let pending = focus.pending {
            return music ? (["start", "extend"].contains(pending) ? "Starting Brain.fm…" : "Pausing Brain.fm…") : "Updating timer…"
        }
        if let error = focus.error { return error.code == "permission" ? "Allow Lilt in Accessibility." : error.message }
        if focus.phase == .completed {
            if focus.awaitingNext { return focus.interval?.phase == "work" ? "Focus complete" : "Break complete" }
            return "Focus complete"
        }
        return ""
    }

    private var primaryLabel: String {
        let focus = model.focus
        let music = model.focusWithMusic
        if focus.error == nil, focus.awaitingNext { return focus.interval?.phase == "work" ? "Start break" : "Start work" }
        if focus.pending != nil { return music ? "Waiting for Brain.fm" : "Updating focus timer" }
        if focus.error != nil { return music ? "Retry Brain.fm control" : "Retry focus timer" }
        if focus.phase == .running { return music ? "Pause focus and Brain.fm" : "Pause focus timer" }
        return music ? "Start focus and Brain.fm" : "Start focus timer"
    }
}

/// Focus dropdowns, drawn above the footer. Like the web version they open 4 pt below the trigger and stay
/// inside the focus view, covering the trigger row when the view is too short.
struct FocusMenuLayer: View {
    @Bindable var model: NotchModel
    @State private var menuSize = CGSize(width: 164, height: 120)

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let kind = model.focusMenu {
                let placement = placement(kind)
                Group {
                    if kind == .duration { DurationMenu(model: model) } else { ActivityMenu(model: model) }
                }
                .frame(width: 164)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { menuSize = $0 }
                .offset(x: placement.origin.x, y: placement.origin.y)
                .transition(.menu(anchor: placement.anchor))
            }
        }
        .animation(model.motion(model.focusMenu == nil ? .menuClose : .menuOpen), value: model.focusMenu)
    }

    private func placement(_ kind: NotchModel.FocusMenu) -> (origin: CGPoint, anchor: UnitPoint) {
        let panelX = (NotchModel.panelWidth - model.openSize.width) / 2
        let view = model.focusPageFrame.offsetBy(dx: -panelX, dy: 0)
        let trigger = (model.focusTriggerFrames[kind] ?? .zero).offsetBy(dx: -panelX, dy: 0)
        let left = max(0, min(trigger.minX - view.minX, view.width - menuSize.width))
        let top = max(0, min(trigger.maxY - view.minY + 4, view.height - menuSize.height))
        let origin = CGPoint(x: view.minX + left, y: view.minY + top)
        let anchor = UnitPoint(x: (trigger.midX - origin.x) / max(1, menuSize.width), y: (trigger.maxY - origin.y) / max(1, menuSize.height))
        return (origin, anchor)
    }
}

/// Hover/expanded chevron: hidden at rest, 0.6 opacity on hover, focus or while the menu is open.
private struct Chevron: View {
    var visible: Bool
    @Environment(\.triggerHover) private var hover
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        IconView(icon: .chevronDown, size: 12)
            .opacity(enabled && (visible || hover) ? 0.6 : 0)
            .animation(.linear(duration: 0.12), value: visible || hover)
    }
}

private struct TriggerHoverKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var triggerHover: Bool {
        get { self[TriggerHoverKey.self] }
        set { self[TriggerHoverKey.self] = newValue }
    }
}

/// Text trigger that stays fully legible while locked during a running session.
private struct TriggerStyle: ButtonStyle {
    var locked: Bool

    func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration, locked: locked) }

    private struct Styled: View {
        let configuration: Configuration
        let locked: Bool
        @State private var hover = false

        var body: some View {
            configuration.label
                .environment(\.triggerHover, hover && !locked)
                .contentShape(Rectangle())
                .onHover { hover = $0 }
        }
    }
}

private struct ActivityMenu: View {
    let model: NotchModel

    var body: some View {
        VStack(spacing: 0) {
            ForEach([("deepWork", "Deep Work"), ("lightWork", "Light Work")], id: \.0) { activity, title in
                Button { model.configureFocus(activity: activity, activityOnly: true) } label: {
                    MenuCheckRow(title: title, checked: model.focus.activity == activity)
                }
                .buttonStyle(MenuRowStyle())
                .accessibilityAddTraits(model.focus.activity == activity ? .isSelected : [])
            }
        }
        .modifier(MenuSurface())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Focus activity")
    }
}

private struct DurationMenu: View {
    @Bindable var model: NotchModel
    @State private var custom = ""
    @State private var work = ""
    @State private var rest = ""
    @SwiftUI.FocusState private var field: Field?

    enum Field { case custom, work }

    var body: some View {
        let minutes = model.focus.duration / 60
        VStack(alignment: .leading, spacing: 0) {
            if model.focusMenuMode == .intervals {
                intervals
            } else {
                ForEach([25, 50], id: \.self) { preset in
                    Button { model.configureFocus(minutes: preset) } label: {
                        MenuCheckRow(title: "\(preset) min", checked: minutes == preset && model.focus.interval == nil)
                    }
                    .buttonStyle(MenuRowStyle())
                }
                Button {
                    work = String(model.focus.interval?.workMinutes ?? minutes)
                    rest = String(model.focus.interval?.restMinutes ?? 5)
                    model.focusMenuMode = .intervals
                    field = .work
                } label: { MenuCheckRow(title: "Intervals…", checked: model.focus.interval != nil) }
                .buttonStyle(MenuRowStyle())
                if model.focusMenuMode == .custom {
                    customForm
                } else {
                    Button {
                        custom = String(minutes)
                        model.focusMenuMode = .custom
                        field = .custom
                    } label: { MenuCheckRow(title: "Custom…", checked: ![25, 50].contains(minutes) && model.focus.interval == nil) }
                    .buttonStyle(MenuRowStyle())
                }
            }
        }
        .modifier(MenuSurface())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Focus duration")
    }

    private var customForm: some View {
        HStack(spacing: 5) {
            MinuteField(value: $custom, label: "Custom duration in minutes", onSubmit: submitCustom)
                .focused($field, equals: .custom)
            Text("min").foregroundStyle(Lilt.ink.mix(65))
            Spacer(minLength: 0)
            Button("Set", action: submitCustom)
                .buttonStyle(MenuRowStyle()).fixedSize()
                .font(Lilt.font(12, .semibold))
                .accessibilityLabel("Set focus duration")
        }
        .font(Lilt.font(12))
        .padding(.horizontal, 4)
        .frame(height: 32)
    }

    private var intervals: some View {
        VStack(spacing: 3) {
            HStack {
                Text("Work")
                Spacer()
                MinuteField(value: $work, label: "Work", onSubmit: submitIntervals).focused($field, equals: .work)
            }
            HStack {
                Text("Break")
                Spacer()
                MinuteField(value: $rest, label: "Break", onSubmit: submitIntervals)
            }
            Button(action: submitIntervals) { Text("Set").frame(maxWidth: .infinity) }
                .buttonStyle(MenuRowStyle())
        }
        .font(Lilt.font(12))
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
    }

    private func submitCustom() {
        guard let minutes = Int(custom.trimmingCharacters(in: .whitespaces)), (1...180).contains(minutes) else { NSSound.beep(); return }
        model.configureFocus(minutes: minutes)
    }

    private func submitIntervals() {
        guard let work = Int(work), let rest = Int(rest), (1...180).contains(work), (1...180).contains(rest) else { NSSound.beep(); return }
        model.configureIntervals(work: work, rest: rest)
    }
}

private struct MenuCheckRow: View {
    let title: String
    let checked: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 0)
            IconView(icon: .check, size: 14).opacity(checked ? 1 : 0)
        }
    }
}
