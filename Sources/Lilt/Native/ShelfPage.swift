import SwiftUI

struct ShelfPage: View {
    @Bindable var model: NotchModel

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                if model.shelf.isEmpty { dropZone } else { list }
            }
            .frame(maxHeight: .infinity)
            // Like the web grid, the action column may overflow its row without moving the layout.
            .overlay(alignment: .trailing) { actions.fixedSize() }
            if let message = model.shelfMessage {
                Text(message)
                    .font(Lilt.font(11)).lineSpacing(1)
                    .foregroundStyle(Lilt.warning)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, maxHeight: 32, alignment: .leading)
                    .padding(.horizontal, 4)
                    .background(.black)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .padding(.vertical, 2)
    }

    private var dropZone: some View {
        Button { model.post(["action": "chooseFiles"]) } label: {
            DropZoneLabel(dragging: model.dragging)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 56)
        .accessibilityLabel("Drop files or folders, or choose")
    }

    private var list: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 1) {
                ForEach(model.shelf) { item in
                    ShelfRow(model: model, item: item)
                }
            }
            .padding(.top, 2)
            .padding(.bottom, 14)
        }
        .scrollIndicators(.hidden)
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.9), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .padding(.trailing, 48)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(NotchSpace.root)) } action: { frame in
            model.shelfListFrame = frame
            model.publishShelfRegions()
        }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, _ in model.publishShelfRegions() }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Lilt.accent3.mix(6))
                .strokeBorder(Lilt.accent3, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .opacity(model.dragging ? 1 : 0)
                .animation(model.motion(.easeOut(duration: 0.15)), value: model.dragging)
                .allowsHitTesting(false)
        }
        .accessibilityLabel("On the shelf")
    }

    private var actions: some View {
        VStack(spacing: 2) {
            Button("Paste") { model.shelfCommand("paste") }
                .buttonStyle(PillButtonStyle()).help("Paste files or folders (⌘V)")
            if model.shelfCanUndo {
                Button("Undo") { model.shelfCommand("undo") }
                    .buttonStyle(PillButtonStyle()).help("Undo removal (⌘Z)")
            }
            if !model.shelf.isEmpty {
                Button { model.post(["action": "chooseFiles"]) } label: { IconView(icon: .plus, size: 18) }
                    .buttonStyle(IconButtonStyle(diameter: 40, rest: Lilt.ink.mix(75)))
                    .accessibilityLabel("Add files").help("Add files")
                Button { model.shelfCommand("clear") } label: { IconView(icon: .trash, size: 18) }
                    .buttonStyle(IconButtonStyle(diameter: 40, rest: Lilt.ink.mix(75)))
                    .accessibilityLabel("Clear Shelf").help("Clear Shelf")
            }
        }
    }
}

private struct DropZoneLabel: View {
    let dragging: Bool
    @State private var hover = false

    var body: some View {
        let highlighted = hover || dragging
        HStack(spacing: 10) {
            IconView(icon: .shelf, size: 22)
            (Text("Drop files or folders, or ") + Text("choose").underline(true, color: Lilt.ink.mix(40)))
                .font(Lilt.font(14)).lineSpacing(2)
        }
        .foregroundStyle(highlighted ? Lilt.ink : Lilt.ink.mix(70))
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(dragging ? Lilt.accent3.mix(8) : hover ? Lilt.ink.mix(5) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(dragging ? Lilt.accent3 : Lilt.ink.mix(22), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.15), value: highlighted)
        .onHover { hover = $0 }
    }
}

private struct ShelfRow: View {
    @Bindable var model: NotchModel
    let item: ShelfItem
    @State private var hover = false
    @State private var menuFrame = CGRect.zero
    @SwiftUI.FocusState private var focused: Bool

    var body: some View {
        let selected = model.selection.selected.contains(item.id)
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                icon
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.name).font(Lilt.font(13, .medium)).opacity(item.available ? 1 : 0.5)
                    Text(item.available ? item.location + (item.retention == "long" ? " · Kept longer" : "") : "File unavailable")
                        .font(Lilt.font(11))
                        .foregroundStyle(item.available ? Lilt.ink.mix(55) : Lilt.warning)
                }
                .lineLimit(1)
                .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.leading, 6).padding(.trailing, 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { click() }
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(phases: .down) { press in key(press) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(item.name), \(item.available ? item.location : "File unavailable")\(item.retention == "long" ? ", kept longer" : "")")
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .help("\(item.name) · \(item.location)\(item.available ? "" : " · File unavailable")")

            Button { toggleMenu() } label: { IconView(icon: .more, size: 16) }
                .buttonStyle(HoverIconStyle(size: CGSize(width: 30, height: 30), rest: Lilt.ink.mix(70), hoverBackground: Lilt.ink.mix(12), radius: 8))
                .opacity(hover || selected || focused || menuOpen ? 1 : 0)
                .animation(.easeOut(duration: 0.12), value: hover || selected || focused || menuOpen)
                .padding(.trailing, 4)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(NotchSpace.root)) } action: { menuFrame = $0 }
                .accessibilityLabel("Actions for \(item.name)")
        }
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(selected ? Lilt.ink.mix(13) : hover ? Lilt.ink.mix(6) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Lilt.ink, lineWidth: 2).opacity(focused ? 1 : 0))
        .animation(.easeOut(duration: 0.12), value: hover)
        .onHover { hover = $0 }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(NotchSpace.root)) } action: { frame in
            model.shelfRowFrames[item.id] = frame
            model.publishShelfRegions()
        }
        .onDisappear { model.shelfRowFrames[item.id] = nil }
        .onChange(of: model.focusedShelfItem) { _, id in if id == item.id { focused = true } }
    }

    private var menuOpen: Bool { model.shelfMenu?.ids.contains(item.id) == true }

    private var icon: some View {
        ZStack {
            Lilt.ink.mix(12)
            if let thumbnail = item.thumbnail {
                Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
            } else if item.kind == "FOLDER" {
                IconView(icon: .folder, size: 16)
            } else if !item.kind.isEmpty {
                Text(item.kind).font(Lilt.font(8, .bold)).tracking(0.32).foregroundStyle(Lilt.ink.mix(75))
            } else {
                IconView(icon: .file, size: 16)
            }
        }
        .frame(width: 26, height: 26)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .opacity(item.available ? 1 : 0.5)
        .accessibilityHidden(true)
    }

    private func click() {
        let event = NSApp.currentEvent
        if (event?.clickCount ?? 1) >= 2 { model.shelfCommand("open", ids: [item.id]); return }
        let flags = event?.modifierFlags ?? []
        model.selectShelfItem(item.id, toggle: flags.contains(.command) || flags.contains(.control), range: flags.contains(.shift))
    }

    private func toggleMenu() {
        if model.shelfMenu != nil { model.closeShelfMenu(); return }
        let keyboard = NSApp.currentEvent?.type == .keyDown
        model.openShelfMenu(for: item.id, at: CGPoint(x: menuFrame.maxX, y: menuFrame.maxY + 4), alignRight: true, keyboard: keyboard)
    }

    private func key(_ press: KeyPress) -> KeyPress.Result {
        let modified = !press.modifiers.intersection([.command, .shift]).isEmpty
        switch press.key {
        case .space where !modified: model.shelfCommand("preview", ids: [item.id])
        case .return where !modified: model.shelfCommand("open", ids: [item.id])
        case .space, .return:
            model.selectShelfItem(item.id, toggle: press.modifiers.contains(.command), range: press.modifiers.contains(.shift))
        case .delete, .deleteForward:
            let ids = model.selection.selected.contains(item.id) ? model.shelfSelectedIDs : [item.id]
            model.shelfCommand("remove", ids: ids)
        case .downArrow, .upArrow:
            let ids = model.shelf.map(\.id)
            guard let index = ids.firstIndex(of: item.id) else { return .ignored }
            let next = ids[max(0, min(ids.count - 1, index + (press.key == .downArrow ? 1 : -1)))]
            model.selectShelfItem(next, toggle: press.modifiers.contains(.command), range: press.modifiers.contains(.shift))
            model.focusedShelfItem = next
        default: return .ignored
        }
        return .handled
    }
}

/// Two-column file menu rendered inside the notch, kept below the physical camera housing.
struct ShelfMenuLayer: View {
    @Bindable var model: NotchModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let menu = model.shelfMenu {
                let items = model.shelfMenuItems(menu.ids)
                let size = CGSize(width: 264, height: CGFloat((items.count + 1) / 2) * 30 - 2 + 8)
                let placement = placement(menu, size: size)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)], spacing: 2) {
                    ForEach(items, id: \.command) { entry in
                        Button(entry.label) { choose(entry.command, menu: menu) }
                            .buttonStyle(MenuRowStyle(destructive: entry.command == "remove"))
                            .disabled(!entry.enabled)
                    }
                }
                .frame(width: 264 - 8)
                .modifier(MenuSurface())
                .offset(x: placement.origin.x, y: placement.origin.y)
                .transition(.menu(anchor: placement.anchor))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("File actions")
            }
        }
        .animation(model.motion(model.shelfMenu == nil ? .menuClose : .menuOpen), value: model.shelfMenu)
    }

    /// Converts the root-space anchor into panel space and clamps the menu inside the open notch.
    private func placement(_ menu: NotchModel.ShelfMenu, size: CGSize) -> (origin: CGPoint, anchor: UnitPoint) {
        let panel = model.openSize
        let panelX = (NotchModel.panelWidth - panel.width) / 2
        let point = CGPoint(x: menu.point.x - panelX, y: menu.point.y)
        let left = max(6, min((menu.alignRight ? point.x - size.width : point.x), panel.width - size.width - 6))
        let top = max(model.hardwareHeight + 4, min(point.y, panel.height - size.height - 6))
        let anchor = UnitPoint(x: max(0, min(1, (point.x - left) / size.width)), y: max(0, min(1, (point.y - top) / size.height)))
        return (CGPoint(x: left, y: top), anchor)
    }

    private func choose(_ command: String, menu: NotchModel.ShelfMenu) {
        let anchor = model.shelfRowFrames[menu.ids[0]].map { CGPoint(x: $0.minX, y: $0.maxY) } ?? CGPoint(x: 250, y: 100)
        model.closeShelfMenu()
        model.shelfCommand(command, ids: menu.ids, anchor: anchor)
    }
}

struct BannerView: View {
    let model: NotchModel
    let banner: NotificationBannerContent

    var body: some View {
        HStack(spacing: 12) {
            if let image = banner.image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 0) {
                if !banner.source.isEmpty {
                    Text(banner.source).font(Lilt.font(12)).foregroundStyle(Lilt.ink.mix(70)).lineLimit(1)
                }
                Text(banner.title).font(Lilt.font(18, .bold)).lineLimit(1)
                if !banner.body.isEmpty {
                    Text(banner.body).font(Lilt.font(14)).lineSpacing(1).lineLimit(2).padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
            Button("Dismiss") { model.setOpen(false) }
                .buttonStyle(BannerDismissStyle())
                .accessibilityLabel("Dismiss notification banner")
        }
        .onAppear {
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: [banner.source, banner.title, banner.body].filter { !$0.isEmpty }.joined(separator: ". "),
                                            .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
        .accessibilityLabel("Notification banner")
    }
}

/// `.banner-dismiss`: transparent at rest, 12 % tint on hover, 18 % while pressed.
private struct BannerDismissStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration) }

    private struct Styled: View {
        let configuration: Configuration
        @State private var hover = false

        var body: some View {
            configuration.label
                .font(Lilt.font(14))
                .frame(minWidth: 70, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Lilt.ink.mix(configuration.isPressed ? 18 : hover ? 12 : 0)))
                .contentShape(Rectangle())
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .animation(.liltEaseOut(0.15), value: configuration.isPressed)
                .onHover { hover = $0 }
        }
    }
}
