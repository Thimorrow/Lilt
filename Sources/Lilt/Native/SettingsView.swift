import SwiftUI

// Settings window design; values mirror the former settings.css.
extension Lilt {
    static let surface0 = Color(white: 0x08 / 255)
    static let surface = Color(white: 0x11 / 255)
    static let surface2 = Color(white: 0x1a / 255)
    static let surface3 = Color(white: 0x22 / 255)
    static let surfaceHover = Color(white: 0x2a / 255)
    static let line = Color(white: 0x26 / 255)
    static let lineStrong = Color(white: 0x33 / 255)
    static let muted = Color(red: 0xaa / 255, green: 0xa4 / 255, blue: 0x9f / 255)
    static let quiet = Color(red: 0x79 / 255, green: 0x75 / 255, blue: 0x71 / 255)
    static let focusRing = Color(red: 0xe5 / 255, green: 0xde / 255, blue: 0xd6 / 255)
    static let ready = Color(red: 0xb9 / 255, green: 0xd7 / 255, blue: 0xbd / 255)
    static let knobOn = Color(red: 0x25 / 255, green: 0x21 / 255, blue: 0x1e / 255)
}

/// CSS breakpoints `max-width: 740px` and `max-height: 560px`.
struct SettingsLayout {
    var compact = false
    var short = false
}

struct SettingsRootView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        GeometryReader { proxy in
            let layout = SettingsLayout(compact: proxy.size.width <= 740, short: proxy.size.height <= 560)
            HStack(spacing: 0) {
                SettingsSidebar(model: model, layout: layout)
                    .frame(width: layout.compact ? 156 : 178)
                SettingsMain(model: model, layout: layout)
            }
        }
        .background(Color.black)
        .foregroundStyle(Lilt.ink)
        .font(Lilt.font(14))
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
        .onAppear { model.post(["action": "settingsReady"]) }
    }
}

// MARK: Sidebar

private struct SettingsSidebar: View {
    let model: SettingsModel
    let layout: SettingsLayout
    @SwiftUI.FocusState private var focused: SettingsSection?

    var body: some View {
        let index = CGFloat(SettingsSection.allCases.firstIndex(of: model.section)!)
        VStack(alignment: .leading, spacing: 0) {
            IconView(icon: .wordmark, size: 52)
                .frame(height: 35)
                .padding(.horizontal, 12)
                .padding(.bottom, 39)
            VStack(spacing: 5) {
                ForEach(SettingsSection.allCases, id: \.self) { section in
                    Button { model.setSection(section) } label: {
                        HStack(spacing: 10) {
                            IconView(icon: section.icon, size: 18)
                            Text(section.title)
                        }
                    }
                    .buttonStyle(NavButtonStyle(selected: model.section == section))
                    .focused($focused, equals: section)
                    .accessibilityAddTraits(model.section == section ? .isSelected : [])
                    .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .home, .end]) { press in
                        let all = SettingsSection.allCases
                        switch press.key {
                        case .home: model.setSection(all[0], animate: false)
                        case .end: model.setSection(all[all.count - 1], animate: false)
                        case .upArrow, .leftArrow: model.moveSection(by: -1)
                        default: model.moveSection(by: 1)
                        }
                        focused = model.section
                        return .handled
                    }
                }
            }
            .background(alignment: .top) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Lilt.surface3)
                    .frame(height: 42)
                    .offset(y: index * 47)
                    .animation(model.motion(.liltEaseOut(0.24)), value: index)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Settings sections")
            Spacer(minLength: 0)
            let status = model.saveStatus
            HStack(spacing: 5) {
                IconView(icon: .check, size: 13).opacity(status == "saved" ? 1 : 0)
                Text(model.saveLabel).font(Lilt.font(11))
            }
            .foregroundStyle(status == "error" ? Lilt.destructive : Lilt.muted)
            .frame(minHeight: 17)
            .padding(.top, 24)
            .padding(.horizontal, 12)
            .accessibilityElement(children: .combine)
        }
        .padding(.top, layout.short ? 68 : 75)
        .padding(.bottom, 22)
        .padding(.leading, layout.compact ? 14 : 20)
        .padding(.trailing, layout.compact ? 13 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Lilt.surface0)
        .overlay(alignment: .trailing) { Rectangle().fill(Lilt.line).frame(width: 1) }
    }
}

// MARK: Main

private struct SettingsMain: View {
    let model: SettingsModel
    let layout: SettingsLayout

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    ZStack(alignment: .topLeading) {
                        section(model.section)
                            .id(model.section)
                            .transition(model.reducedMotion ? .identity : .settingsSection)
                    }
                    .padding(.horizontal, 2)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .id("top")
                }
                .scrollIndicators(.automatic)
                .onChange(of: model.section) { proxy.scrollTo("top", anchor: .top) }
            }
            if let error = model.errorMessage {
                HStack(alignment: .top, spacing: 9) {
                    IconView(icon: .error, size: 16).padding(.top, 1)
                    Text(error).font(Lilt.font(12)).lineSpacing(2).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(Lilt.destructive)
                .padding(.vertical, 13)
                .padding(.horizontal, 15)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0x1e / 255, green: 0x12 / 255, blue: 0x0d / 255)))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(red: 0x52 / 255, green: 0x35 / 255, blue: 0x2a / 255)))
                .padding(.top, 14)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, layout.short ? 68 : 75)
        .padding(.bottom, layout.short ? 18 : 26)
        .padding(.horizontal, layout.compact ? 27 : 39)
    }

    @ViewBuilder
    private func section(_ section: SettingsSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(section.title)
                .font(Lilt.font(31, .medium)).tracking(-1.085)
                .frame(minHeight: 37)
                .padding(.bottom, layout.short ? 25 : 34)
                .accessibilityAddTraits(.isHeader)
            switch section {
            case .music: MusicSettings(model: model, layout: layout)
            case .focus: FocusSettings(model: model, layout: layout)
            case .shelf: ShelfSettings(model: model)
            case .notifications: NotificationSettings(model: model)
            case .general: GeneralSettings(model: model)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

extension AnyTransition {
    /// Leaving: 100 ms fade, 160 ms drift. Entering after 100 ms: 160 ms fade, 220 ms rise.
    static let settingsSection = AnyTransition.asymmetric(
        insertion: AnyTransition.opacity.animation(.liltEaseOut(0.16).delay(0.1))
            .combined(with: AnyTransition.offset(y: 5).animation(.liltEaseOut(0.22).delay(0.1))),
        removal: AnyTransition.opacity.animation(.easeInOut(duration: 0.1))
            .combined(with: AnyTransition.offset(y: 5).animation(.liltEaseOut(0.16))))
}

// MARK: Music

private struct MusicSettings: View {
    let model: SettingsModel
    let layout: SettingsLayout
    @SwiftUI.FocusState private var focused: String?

    var body: some View {
        let state = model.state
        let selected = musicSources.firstIndex { $0.id == state.musicSource } ?? 0
        VStack(alignment: .leading, spacing: 0) {
            Text("Player").font(Lilt.font(13)).foregroundStyle(Lilt.muted).padding(.bottom, 12)
            HStack(spacing: 4) {
                ForEach(musicSources, id: \.id) { source in option(source) }
            }
            .padding(5)
            .background {
                GeometryReader { proxy in
                    let width = (proxy.size.width - 18) / 3
                    RoundedRectangle(cornerRadius: 11)
                        .fill(Lilt.surface3)
                        .frame(width: width, height: proxy.size.height - 10)
                        .offset(x: 5 + CGFloat(selected) * (width + 4), y: 5)
                        .animation(model.motion(.liltEaseOut(0.25)), value: selected)
                }
            }
            .background(RoundedRectangle(cornerRadius: 16).fill(Lilt.surface))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Lilt.line))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Music player")
            connectionCard.padding(.top, 19)
            if state.musicBusy { ContextNote("Wait for the current player command to finish.") }
        }
    }

    private func option(_ source: (id: String, name: String)) -> some View {
        let checked = model.state.musicSource == source.id
        let missing = model.state.providers.first { $0.id == source.id }?.installed == false
        let pending = (model.requested?["musicSource"] as? String) == source.id
        return Button { model.selectSource(source.id) } label: {
            HStack(spacing: layout.compact ? 8 : 10) {
                IconView(icon: logo(source.id), size: 22, cutout: checked ? Lilt.surface3 : Lilt.surface)
                    .opacity(missing ? 0.4 : pending ? 0.55 : 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(source.name).lineLimit(1)
                    if missing { Text("Not installed").font(Lilt.font(11)).foregroundStyle(Lilt.quiet).lineLimit(1) }
                }
            }
            .font(Lilt.font(layout.compact ? 12 : 13, .medium))
            .padding(.vertical, 8)
            .padding(.horizontal, layout.compact ? 10 : 14)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        }
        .buttonStyle(SegmentStyle(selected: checked, radius: 11))
        .disabled(model.musicDisabled)
        .focused($focused, equals: source.id)
        .accessibilityLabel(missing ? "\(source.name), not installed" : source.name)
        .accessibilityAddTraits(checked ? .isSelected : [])
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .home, .end]) { press in
            let ids = musicSources.map(\.id)
            let index = ids.firstIndex(of: source.id)!
            let next: Int
            switch press.key {
            case .home: next = 0
            case .end: next = ids.count - 1
            case .leftArrow, .upArrow: next = (index - 1 + ids.count) % ids.count
            default: next = (index + 1) % ids.count
            }
            guard !model.musicDisabled else { return .handled }
            focused = ids[next]
            model.selectSource(ids[next], keyboard: true)
            return .handled
        }
    }

    private var connectionCard: some View {
        let state = model.state
        let name = musicSources.first { $0.id == state.musicSource }?.name ?? ""
        let connection = ProviderState(model.provider)
        let message = model.provider?.message ?? ""
        let dot = connection.status == "ready" ? Lilt.ready : ["permission", "unavailable"].contains(connection.status) ? Lilt.destructive : Lilt.quiet
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 13) {
                IconView(icon: logo(state.musicSource), size: 26, cutout: Lilt.surface)
                    .frame(width: 44, height: 44)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Lilt.lineStrong))
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(Lilt.font(16, .medium)).tracking(-0.24)
                    HStack(spacing: 6) {
                        Circle().fill(dot).frame(width: 5, height: 5)
                        Text(connection.label).font(Lilt.font(12)).foregroundStyle(Lilt.muted)
                    }
                    .frame(minHeight: 18)
                    .accessibilityElement(children: .combine)
                }
            }
            if !message.isEmpty, message != connection.label {
                Text(message)
                    .font(Lilt.font(12)).lineSpacing(4).foregroundStyle(Lilt.muted)
                    .textSelection(.enabled)
                    .frame(maxWidth: 356, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 17)
            }
            if connection.open || connection.connect {
                HStack(spacing: 8) {
                    if connection.connect {
                        Button { model.act("musicConnect") } label: {
                            ArrowLabel(connection.status == "permission" ? "Allow connection" : "Connect")
                        }
                        .buttonStyle(SettingsButtonStyle(primary: true))
                        .disabled(model.musicDisabled)
                    }
                    Button { model.act("musicOpen") } label: { ArrowLabel("Open \(name)") }
                        .buttonStyle(SettingsButtonStyle(primary: !connection.connect && connection.open))
                        .disabled(model.musicDisabled || !connection.open)
                }
                .padding(.top, 20)
            }
        }
        .padding(21)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Lilt.surface))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Lilt.line))
    }

    private func logo(_ id: String) -> NotchIcon { id == "appleMusic" ? .appleMusic : id == "meld" ? .meld : .spotify }
}

// MARK: Focus

private struct FocusSettings: View {
    let model: SettingsModel
    let layout: SettingsLayout
    @SwiftUI.FocusState private var durationFocused: Bool
    @SwiftUI.FocusState private var focusedActivity: String?

    var body: some View {
        let state = model.state
        let brainFM = model.shownBool("brainFMEnabled")
        VStack(alignment: .leading, spacing: 0) {
            duration.padding(.bottom, layout.short ? 21 : 28)
            SettingsCard {
                HStack(spacing: layout.compact ? 10 : 16) {
                    Text("Activity").font(Lilt.font(13))
                    Spacer(minLength: 0)
                    activityPicker
                }
                .settingsRow(height: 72, padding: 15)
                HStack(spacing: 16) {
                    Text("When time is up").font(Lilt.font(13))
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        Button("Sound") { model.toggle("focusSound") }
                            .buttonStyle(CompletionStyle(on: model.shownBool("focusSound")))
                            .disabled(model.toggleDisabled("focusSound"))
                            .switchAccessibility("Sound when time is up", on: model.shownBool("focusSound"))
                        Button("Notification") { model.toggleFocusNotifications() }
                            .buttonStyle(CompletionStyle(on: state.focusNotificationsEnabled))
                            .disabled(model.busy || state.focusNotificationRequesting)
                            .switchAccessibility("Notification when time is up", on: state.focusNotificationsEnabled)
                    }
                }
                .settingsRow(height: 72, padding: 15, divider: true)
                if !model.focusNotificationNote.isEmpty {
                    Text(model.focusNotificationNote)
                        .font(Lilt.font(12)).lineSpacing(3).foregroundStyle(Lilt.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }
                HStack(spacing: 20) {
                    HStack(spacing: 10) {
                        IconView(icon: .brain, size: 20)
                            .frame(width: 31, height: 31)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Lilt.surface2))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Lilt.lineStrong))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Brain.fm").font(Lilt.font(13))
                            Text(brainFM ? "Music follows your timer" : "Optional focus music").font(Lilt.font(11)).foregroundStyle(Lilt.muted)
                        }
                    }
                    Spacer(minLength: 0)
                    SwitchControl(on: brainFM, label: "Brain.fm", reducedMotion: model.reducedMotion) { model.toggle("brainFMEnabled") }
                        .disabled(model.focusDisabled)
                }
                .settingsRow(height: 80, padding: 15, divider: true)
                if brainFM { brainFMDetail }
            }
            .animation(model.motion(.liltEaseOut(brainFM ? 0.24 : 0.2)), value: brainFM)
            if state.focusLocked { ContextNote("Reset or finish your focus session to change these settings.") }
        }
    }

    private var duration: some View {
        let disabled = model.focusDisabled
        let text = model.durationDraft ?? String(model.state.focusMinutes)
        return VStack(alignment: .leading, spacing: 0) {
            Text("Default duration").font(Lilt.font(13)).foregroundStyle(Lilt.muted)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("", text: Binding(get: { text }, set: { model.editDuration($0) }))
                    .textFieldStyle(.plain)
                    .font(Lilt.font(64, .medium)).monospacedDigit()
                    // NSTextField ignores tracking; the resting value is drawn as Text with the CSS -0.055em letter spacing.
                    .foregroundStyle(durationFocused ? Lilt.ink : .clear)
                    .overlay(alignment: .leading) {
                        if !durationFocused {
                            Text(text).font(Lilt.font(64, .medium)).monospacedDigit().tracking(-3.52)
                                .foregroundStyle(disabled ? Lilt.muted : Lilt.ink)
                                .lineLimit(1)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(width: CGFloat(max(1, text.count)) * Self.digitWidth + 4)
                    .padding(.leading, -2)
                    .focused($durationFocused)
                    .disabled(disabled)
                    .accessibilityLabel("Default duration")
                    .accessibilityHint(model.durationError ?? "Minutes")
                    .onSubmit { model.commitDuration(keyboard: true); refocusOnError() }
                    .onExitCommand { model.cancelDuration() }
                    .onChange(of: durationFocused) { _, focused in
                        if !focused { model.commitDuration(); refocusOnError() }
                    }
                Text("min").font(Lilt.font(16)).foregroundStyle(Lilt.muted)
                if model.durationDraft != nil {
                    Button { model.commitDuration(keyboard: true); refocusOnError() } label: { IconView(icon: .check, size: 17) }
                        .buttonStyle(SquareButtonStyle())
                        .disabled(disabled)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 8 }
                        .accessibilityLabel("Save default duration")
                }
            }
            .frame(minHeight: 73)
            .padding(.top, 2)
            HStack(spacing: 2) {
                ForEach([25, 50, 90], id: \.self) { minutes in
                    let pressed = model.state.focusMinutes == minutes
                    Button("\(minutes) min") { model.choosePreset(minutes) }
                        .buttonStyle(PresetStyle(pressed: pressed))
                        .disabled(disabled)
                        .accessibilityAddTraits(pressed ? .isSelected : [])
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 11).fill(Lilt.surface0))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Lilt.line))
            .padding(.top, 12)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Default duration presets")
            if let error = model.durationError { FieldError(error).padding(.top, 10) }
        }
    }

    private func refocusOnError() { if model.durationError != nil { durationFocused = true } }

    /// One tabular digit at 64 pt (`1ch` in the former CSS width calculation).
    private static let digitWidth: CGFloat = {
        Lilt.registerFont()
        let font = NSFont(name: "Familjen Grotesk", size: 64) ?? .systemFont(ofSize: 64)
        return ("0" as NSString).size(withAttributes: [.font: font]).width
    }()

    private var activityPicker: some View {
        let activities = [("deepWork", "Deep Work"), ("lightWork", "Light Work")]
        let selected = model.state.focusActivity == "lightWork" ? 1 : 0
        return HStack(spacing: 2) {
            ForEach(activities, id: \.0) { id, name in
                Button(name) { model.selectActivity(id) }
                    .buttonStyle(SegmentStyle(selected: id == model.state.focusActivity, radius: 7, horizontal: layout.compact ? 9 : 11, font: 12))
                    .disabled(model.focusDisabled)
                    .focused($focusedActivity, equals: id)
                    .accessibilityAddTraits(id == model.state.focusActivity ? .isSelected : [])
                    .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .home, .end]) { press in
                        let next = press.key == .home ? 0 : press.key == .end ? 1 : (activities.firstIndex { $0.0 == id }! + 1) % 2
                        guard !model.focusDisabled else { return .handled }
                        focusedActivity = activities[next].0
                        model.selectActivity(activities[next].0, keyboard: true)
                        return .handled
                    }
            }
        }
        .fixedSize()
        .padding(4)
        .background {
            GeometryReader { proxy in
                let width = (proxy.size.width - 10) / 2
                RoundedRectangle(cornerRadius: 7)
                    .fill(Lilt.surface3)
                    .frame(width: width, height: proxy.size.height - 8)
                    .offset(x: 4 + CGFloat(selected) * (width + 2), y: 4)
                    .animation(model.motion(.liltEaseOut(0.22)), value: selected)
            }
        }
        .background(RoundedRectangle(cornerRadius: 11).fill(Lilt.surface0))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Lilt.line))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Activity")
    }

    private var brainFMDetail: some View {
        let state = model.state
        let disabled = !state.ready || !model.shownBool("brainFMEnabled") || model.requested != nil
        return HStack(spacing: 14) {
            Text(model.brainFMMessage)
                .font(Lilt.font(12)).lineSpacing(3).foregroundStyle(Lilt.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
            if state.brainFMInstalled, !state.brainFMPermission {
                Button { model.act("brainfmSettings") } label: { ArrowLabel("Allow control") }
                    .buttonStyle(SettingsButtonStyle()).disabled(disabled)
            }
            if state.brainFMInstalled, state.brainFMPermission {
                Button { model.act("brainfm") } label: { ArrowLabel("Open Brain.fm") }
                    .buttonStyle(SettingsButtonStyle()).disabled(disabled)
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(Lilt.line).frame(height: 1) }
        .clipped()
        .transition(model.reducedMotion ? .identity : .asymmetric(
            insertion: AnyTransition.opacity.animation(.easeInOut(duration: 0.18).delay(0.06)),
            removal: AnyTransition.opacity.animation(.easeInOut(duration: 0.12))))
    }
}

// MARK: Shelf

private struct ShelfSettings: View {
    let model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCard {
                RetentionRow(model: model, key: "shelfShortDays", label: "New files")
                    .zIndex(model.openMenu == "shelfShortDays" ? 1 : 0)
                RetentionRow(model: model, key: "shelfLongDays", label: "Kept longer", divider: true)
            }
            .zIndex(1)
            ContextNote("Changes apply to files added or kept longer from now on. Original files are never removed.")
        }
    }
}

private struct RetentionRow: View {
    let model: SettingsModel
    let key: String
    let label: String
    var divider = false
    @SwiftUI.FocusState private var fieldFocused: Bool

    var body: some View {
        let custom = model.retentionCustom.contains(key)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Text(label).font(Lilt.font(13))
                Spacer(minLength: 0)
                if custom { customField } else { MenuField(model: model, key: key, label: label) }
            }
            if let error = model.retentionErrors[key] { FieldError(error) }
        }
        .settingsRow(height: 78, padding: 16, divider: divider)
    }

    private var customField: some View {
        let text = model.retentionDrafts[key] ?? String(model.state.days(key))
        return HStack(spacing: 8) {
            TextField("", text: Binding(get: { text }, set: { model.editRetention(key, $0) }))
                .textFieldStyle(.plain)
                .font(Lilt.font(16)).monospacedDigit()
                .foregroundStyle(model.busy ? Lilt.muted : Lilt.ink)
                .padding(.horizontal, 10)
                .frame(width: 80, height: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(Lilt.surface0))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Lilt.lineStrong))
                .focused($fieldFocused)
                .disabled(model.busy)
                .accessibilityLabel(label)
                .accessibilityHint(model.retentionErrors[key] ?? "Days")
                .onSubmit { model.commitRetention(key); if model.retentionErrors[key] != nil { fieldFocused = true } }
                .onExitCommand { model.cancelRetention(key) }
                .onAppear { fieldFocused = true }
            Text("days").font(Lilt.font(13)).foregroundStyle(Lilt.muted)
            if model.retentionDrafts[key] != nil {
                Button("Save") { model.commitRetention(key); if model.retentionErrors[key] != nil { fieldFocused = true } }
                    .buttonStyle(SettingsButtonStyle())
                    .disabled(model.busy)
            }
        }
    }
}

/// Trigger plus its dropdown: 200 ms open, 150 ms ease-in close, anchored at the top right.
private struct MenuField: View {
    let model: SettingsModel
    let key: String
    let label: String
    @State private var triggerWidth: CGFloat = 0

    var body: some View {
        let open = model.openMenu == key
        Button { model.toggleMenu(key) } label: {
            HStack(spacing: 6) {
                Text(model.menuLabel(key)).lineLimit(1)
                IconView(icon: .chevron, size: 15)
                    .foregroundStyle(Lilt.muted)
                    .rotationEffect(.degrees(open ? 180 : 0))
                    .animation(model.motion(.liltEaseOut(0.2)), value: open)
            }
        }
        .buttonStyle(MenuTriggerStyle(open: open))
        .disabled(model.busy)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            triggerWidth = frame.width
            model.menuFrames[key] = frame
        }
        .accessibilityLabel(label)
        .accessibilityValue(model.menuLabel(key))
        .accessibilityHint("Opens a menu")
        .onKeyPress(keys: [.downArrow, .upArrow]) { press in
            guard !open else { return .ignored }
            model.toggleMenu(key, last: press.key == .upArrow, animate: false)
            return .handled
        }
        .overlay(alignment: .topTrailing) {
            if open {
                menu
                    .frame(minWidth: triggerWidth, alignment: .trailing)
                    .offset(y: 38)
                    .transition(model.reducedMotion ? .identity : .menu(anchor: .topTrailing))
            }
        }
        .animation(model.motion(open ? .menuOpen : .menuClose), value: open)
    }

    private var menu: some View {
        let items = model.menuItems(key)
        let value = model.menuValue(key)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.value) { index, item in
                if item.value == "custom" { Rectangle().fill(Lilt.line).frame(height: 1).padding(4) }
                Button { model.chooseMenuItem(item.value) } label: {
                    HStack(spacing: 18) {
                        Text(item.label).lineLimit(1)
                        Spacer(minLength: 0)
                        if item.value != "custom" { IconView(icon: .check, size: 14).opacity(item.value == value ? 1 : 0) }
                    }
                    .font(Lilt.font(13)).monospacedDigit()
                    .padding(.horizontal, 8)
                    .frame(minHeight: 30)
                    .background(RoundedRectangle(cornerRadius: 7).fill(model.menuHighlight == index ? Lilt.surfaceHover : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { if $0 { model.menuHighlight = index } }
                .accessibilityAddTraits(item.value == value ? .isSelected : [])
            }
        }
        .fixedSize()
        .frame(maxWidth: 280)
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 12).fill(Lilt.surface2))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Lilt.lineStrong))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 10)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.menuFrames["menu"] = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

// MARK: General

private struct GeneralSettings: View {
    let model: SettingsModel

    var body: some View {
        let state = model.state
        VStack(alignment: .leading, spacing: 0) {
            SettingsCard {
                HStack(spacing: 16) {
                    Text("Show Lilt on").font(Lilt.font(13))
                    Spacer(minLength: 0)
                    MenuField(model: model, key: "displayID", label: "Show Lilt on")
                }
                .settingsRow(height: 78, padding: 16)
                .zIndex(1)
                switchRow("Open at login", key: "openAtLogin")
                HStack(spacing: 16) {
                    Text("Keyboard shortcut").font(Lilt.font(13))
                    Spacer(minLength: 0)
                    HStack(spacing: 12) {
                        Button { model.toggleShortcutRecording() } label: {
                            Text(model.recordingShortcut ? "Press shortcut…" : state.shortcutLabel)
                                .font(Lilt.font(15)).tracking(0.9)
                                .foregroundStyle(Lilt.muted)
                                .frame(minWidth: 80)
                                .padding(.leading, 4)
                        }
                        .buttonStyle(SettingsButtonStyle(pressed: model.recordingShortcut))
                        .disabled(model.busy)
                        .accessibilityLabel(model.recordingShortcut ? "Cancel shortcut recording" : "Record keyboard shortcut, currently \(state.shortcutLabel)")
                        if !model.shortcutIsDefault {
                            Button("Reset") { model.resetShortcut() }
                                .buttonStyle(TextButtonStyle())
                                .disabled(model.busy || model.recordingShortcut)
                        }
                        SwitchControl(on: model.shownBool("shortcutEnabled"), label: "Keyboard shortcut", reducedMotion: model.reducedMotion) { model.toggle("shortcutEnabled") }
                            .disabled(model.toggleDisabled("shortcutEnabled"))
                    }
                }
                .settingsRow(height: 72, padding: 15, divider: true)
            }
            .zIndex(1)
            if model.recordingShortcut {
                ContextNote(model.shortcutRecordingError.isEmpty ? "Press a key with Control, Option or Command. Escape cancels." : model.shortcutRecordingError)
            }
            if state.shortcutConflict, state.shortcutEnabled { ContextNote("Another app already uses this shortcut.") }
            if state.displayUnavailable { ContextNote("The selected display is disconnected. Lilt will return when it reconnects.") }
        }
    }

    private func switchRow(_ title: String, key: String, divider: Bool = true) -> some View {
        HStack(spacing: 16) {
            Text(title).font(Lilt.font(13))
            Spacer(minLength: 0)
            SwitchControl(on: model.shownBool(key), label: title, reducedMotion: model.reducedMotion) { model.toggle(key) }
                .disabled(model.toggleDisabled(key))
        }
        .settingsRow(height: 72, padding: 15, divider: divider)
    }
}

// MARK: Notifications

private struct NotificationSettings: View {
    let model: SettingsModel
    @State private var appToken = ""
    @State private var userToken = ""

    var body: some View {
        let state = model.state
        let slackOff = state.slackStatus == "off"
        VStack(alignment: .leading, spacing: 0) {
            SettingsCard {
                HStack(spacing: 16) {
                    Text("Slack").font(Lilt.font(13))
                    Spacer(minLength: 0)
                    if slackOff {
                        Button { model.act("slackCreateApp") } label: { ArrowLabel("Create Slack app") }
                            .buttonStyle(TextButtonStyle())
                            .disabled(!state.ready)
                    } else {
                        Text(state.slackMessage).font(Lilt.font(13)).foregroundStyle(Lilt.muted).lineLimit(1)
                        Button("Disconnect") { model.act("slackDisconnect") }
                            .buttonStyle(SettingsButtonStyle())
                            .disabled(!state.ready)
                    }
                }
                .settingsRow(height: 72, padding: 15)
                if slackOff {
                    tokenRow("App-level token", prompt: "xapp-…", text: $appToken)
                    tokenRow("User token", prompt: "xoxp-…", text: $userToken)
                    HStack {
                        Spacer(minLength: 0)
                        Button("Connect") {
                            model.post(["action": "slackConnect", "appToken": appToken, "userToken": userToken])
                            appToken = ""
                            userToken = ""
                        }
                        .buttonStyle(SettingsButtonStyle(primary: true))
                        .disabled(!state.ready || appToken.isEmpty || userToken.isEmpty)
                    }
                    .settingsRow(height: 66, padding: 15, divider: true)
                }
            }
            if slackOff, !state.slackMessage.isEmpty { ContextNote(state.slackMessage) }
            // The former CSS stacked cards without a gap; 12 pt keeps their borders from doubling.
            SettingsCard {
                HStack(spacing: 16) {
                    Text("Other apps").font(Lilt.font(13))
                    Spacer(minLength: 0)
                    SwitchControl(on: model.shownBool("notificationBannersEnabled"), label: "Show other apps’ notifications", reducedMotion: model.reducedMotion) {
                        model.toggle("notificationBannersEnabled")
                    }
                    .disabled(model.toggleDisabled("notificationBannersEnabled"))
                }
                .settingsRow(height: 72, padding: 15)
            }
            .padding(.top, 12)
            ContextNote(state.notificationCaptureMessage)
            HStack(spacing: 8) {
                if state.notificationCaptureStatus == "permission" {
                    Button("Open Accessibility settings") { model.act("notificationAccessibilitySettings") }
                        .buttonStyle(SettingsButtonStyle())
                        .disabled(!state.ready)
                }
                Button("Preview banner") { model.act("notificationPreview") }
                    .buttonStyle(SettingsButtonStyle())
                    .disabled(!state.ready)
            }
            .padding(.top, 20)
        }
    }

    private func tokenRow(_ label: String, prompt: String, text: Binding<String>) -> some View {
        HStack(spacing: 16) {
            Text(label).font(Lilt.font(13))
            Spacer(minLength: 0)
            SecureField("", text: text, prompt: Text(prompt).foregroundStyle(Lilt.quiet))
                .textFieldStyle(.plain)
                .font(Lilt.font(13))
                .padding(.horizontal, 10)
                .frame(width: 240, height: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(Lilt.surface0))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Lilt.lineStrong))
                .disabled(!model.state.ready)
                .accessibilityLabel(label)
        }
        .settingsRow(height: 66, padding: 15, divider: true)
    }
}

// MARK: Building blocks

private struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, 19)
            .padding(.vertical, 1)
            // The border sits behind the content so an open menu can overlap it.
            .background(RoundedRectangle(cornerRadius: 16).strokeBorder(Lilt.line).background(RoundedRectangle(cornerRadius: 16).fill(Lilt.surface)))
    }
}

private extension View {
    /// Card row: CSS `min-height` includes the vertical padding; rows after the first get a hairline.
    func settingsRow(height: CGFloat, padding: CGFloat, divider: Bool = false) -> some View {
        self.padding(.vertical, padding)
            .frame(maxWidth: .infinity, minHeight: height)
            .overlay(alignment: .top) { if divider { Rectangle().fill(Lilt.line).frame(height: 1) } }
    }

    func switchAccessibility(_ label: String, on: Bool) -> some View {
        accessibilityLabel(label)
            .accessibilityAddTraits(.isToggle)
            .accessibilityValue(on ? "On" : "Off")
    }
}

private struct ContextNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Lilt.font(12)).lineSpacing(3).foregroundStyle(Lilt.muted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 15)
    }
}

private struct FieldError: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(Lilt.font(12)).foregroundStyle(Lilt.destructive)
            .accessibilityAddTraits(.updatesFrequently)
    }
}

private struct ArrowLabel: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
            IconView(icon: .arrow, size: 14)
        }
    }
}

/// `.switch`: 37×23 track, 15 pt knob travelling 14 pt; track fade and knob share 230 ms. The hit area extends to 55×41.
private struct SwitchControl: View {
    let on: Bool
    let label: String
    let reducedMotion: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .leading) {
                // Drawn tracks: layer-backed capsules picked up stray edges in snapshots.
                track(fill: Lilt.surface3, border: Lilt.lineStrong)
                    .overlay(track(fill: Lilt.ink, border: Lilt.ink).opacity(on ? 1 : 0))
                    .animation(reducedMotion ? nil : .liltEaseOut(0.23), value: on)
                Circle().fill(on ? Lilt.knobOn : Lilt.muted)
                    .frame(width: 15, height: 15)
                    .offset(x: on ? 18 : 4)
                    .animation(reducedMotion ? nil : .liltEaseOut(0.23), value: on)
            }
            .frame(width: 37, height: 23)
            .contentShape(Rectangle().inset(by: -9))
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.55)
        .switchAccessibility(label, on: on)
    }

    private func track(fill: Color, border: Color) -> some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(roundedRect: rect, cornerRadius: size.height / 2, style: .circular), with: .color(fill))
            context.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: size.height / 2 - 0.5, style: .circular),
                           with: .color(border), lineWidth: 1)
        }
    }
}

// MARK: Button styles

/// Hover state lives in a nested view because ButtonStyle itself cannot hold @State.
private struct Hovering<Content: View>: View {
    let content: (Bool, Bool) -> Content
    @State private var hover = false
    @Environment(\.isEnabled) private var enabled

    init(@ViewBuilder content: @escaping (_ hover: Bool, _ enabled: Bool) -> Content) { self.content = content }

    var body: some View { content(hover && enabled, enabled).onHover { hover = $0 } }
}

private struct NavButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        Hovering { hover, _ in
            configuration.label
                .font(Lilt.font(14))
                .foregroundStyle(selected || hover ? Lilt.ink : Lilt.muted)
                .padding(.horizontal, 13)
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                .contentShape(RoundedRectangle(cornerRadius: 12))
                .animation(.easeInOut(duration: 0.14), value: selected || hover)
        }
    }
}

/// Player and activity choices: the moving selection sits behind; only the label colour changes here.
private struct SegmentStyle: ButtonStyle {
    let selected: Bool
    var radius: CGFloat
    var horizontal: CGFloat?
    var font: CGFloat?

    func makeBody(configuration: Configuration) -> some View {
        Hovering { hover, enabled in
            configuration.label
                .font(font.map { Lilt.font($0) })
                .lineLimit(1)
                .padding(.horizontal, horizontal ?? 0)
                .frame(maxWidth: horizontal == nil ? nil : .infinity, minHeight: horizontal == nil ? nil : 30)
                .foregroundStyle(!enabled ? (selected ? Lilt.muted : Lilt.quiet) : selected || hover ? Lilt.ink : Lilt.muted)
                .contentShape(RoundedRectangle(cornerRadius: radius))
                .animation(.easeInOut(duration: 0.14), value: hover)
        }
    }
}

private struct PresetStyle: ButtonStyle {
    let pressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        Hovering { hover, enabled in
            configuration.label
                .font(Lilt.font(12)).monospacedDigit()
                .padding(.horizontal, 11)
                .frame(minHeight: 30)
                .foregroundStyle(!enabled ? Lilt.quiet : pressed || hover ? Lilt.ink : Lilt.muted)
                .background(RoundedRectangle(cornerRadius: 7)
                    .fill(pressed ? Lilt.surface3 : hover ? Lilt.surfaceHover : .clear))
                .contentShape(Rectangle())
                .animation(.easeInOut(duration: 0.14), value: hover)
                .animation(.easeInOut(duration: 0.14), value: pressed)
        }
    }
}

/// `.button.primary` / `.button.secondary`, including the 0.96 press scale.
private struct SettingsButtonStyle: ButtonStyle {
    var primary = false
    var pressed = false

    func makeBody(configuration: Configuration) -> some View {
        Hovering { hover, enabled in
            let fill: Color = !enabled ? Lilt.surface2 : primary ? (hover ? .white : Lilt.ink) : pressed || hover ? Lilt.surfaceHover : Lilt.surface3
            let border: Color = !enabled ? Lilt.line : primary ? .clear : pressed ? Lilt.focusRing : Lilt.lineStrong
            configuration.label
                .font(Lilt.font(12, .medium))
                .lineLimit(1)
                .padding(.horizontal, 13)
                .frame(minHeight: 35)
                .foregroundStyle(!enabled ? Lilt.quiet : primary ? Color(white: 0x11 / 255) : Lilt.ink)
                .background(RoundedRectangle(cornerRadius: 8).fill(fill))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(border))
                .contentShape(Rectangle())
                .scaleEffect(configuration.isPressed && enabled ? 0.96 : 1)
                .animation(.liltEaseOut(0.14), value: configuration.isPressed)
                .animation(.easeInOut(duration: 0.14), value: hover)
        }
    }
}

private struct SquareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Hovering { hover, _ in
            configuration.label
                .frame(width: 31, height: 31)
                .background(RoundedRectangle(cornerRadius: 8).fill(hover ? Lilt.surfaceHover : Lilt.surface3))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Lilt.lineStrong))
                .contentShape(Rectangle())
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .animation(.liltEaseOut(0.14), value: configuration.isPressed)
                .animation(.easeInOut(duration: 0.14), value: hover)
                .padding(.leading, 5)
        }
    }
}

private struct CompletionStyle: ButtonStyle {
    let on: Bool

    func makeBody(configuration: Configuration) -> some View {
        Hovering { hover, enabled in
            configuration.label
                .font(Lilt.font(12))
                .padding(.vertical, 6)
                .padding(.horizontal, 11)
                .frame(minHeight: 32)
                .foregroundStyle(on ? Color.black : hover ? Lilt.ink : Lilt.muted)
                .background(RoundedRectangle(cornerRadius: 8).fill(on ? (hover ? .white : Lilt.ink) : hover ? Lilt.surfaceHover : .clear))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(on ? Lilt.ink : Lilt.lineStrong))
                .contentShape(Rectangle())
                .scaleEffect(configuration.isPressed && enabled ? 0.96 : 1)
                .opacity(enabled ? 1 : 0.5)
                .animation(.liltEaseOut(0.14), value: configuration.isPressed)
                .animation(.easeInOut(duration: 0.14), value: hover)
                .animation(.easeInOut(duration: 0.14), value: on)
        }
    }
}

private struct MenuTriggerStyle: ButtonStyle {
    let open: Bool

    func makeBody(configuration: Configuration) -> some View {
        Hovering { hover, _ in
            configuration.label
                .font(Lilt.font(13)).monospacedDigit()
                .padding(.leading, 12)
                .padding(.trailing, 9)
                .frame(minHeight: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(open || hover ? Lilt.surface2 : Lilt.surface0))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Lilt.lineStrong))
                .contentShape(Rectangle())
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .animation(.liltEaseOut(0.14), value: configuration.isPressed)
                .animation(.easeInOut(duration: 0.14), value: open || hover)
        }
    }
}

private struct TextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Hovering { hover, _ in
            configuration.label
                .font(Lilt.font(12))
                .foregroundStyle(hover ? Lilt.ink : Lilt.muted)
                .padding(8)
                .contentShape(Rectangle())
                .opacity(configuration.isPressed ? 0.7 : 1)
                .animation(.easeInOut(duration: 0.14), value: hover)
        }
    }
}
