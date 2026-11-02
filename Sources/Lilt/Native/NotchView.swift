import SwiftUI

/// Root of the 680×300 transparent panel. Only the black shell morphs; content keeps its final layout and is clipped.
struct NotchRootView: View {
    @Bindable var model: NotchModel

    var body: some View {
        let open = model.open
        let size = open ? model.openSize : model.compactSize
        ZStack(alignment: .top) {
            CompactContent(model: model)
                .frame(width: model.compactSize.width, height: model.compactSize.height)
                .opacity(open ? 0 : 1)
                .animation(model.motion(open ? .linear(duration: 0.16) : .linear(duration: 0.22).delay(0.18)), value: open)
                .allowsHitTesting(!open)
            PanelContent(model: model)
                .frame(width: model.openSize.width, height: model.openSize.height)
                .opacity(open ? 1 : 0)
                .animation(model.motion(open ? .linear(duration: 0.22).delay(0.12) : .linear(duration: 0.12)), value: open)
                .allowsHitTesting(open)
                .accessibilityHidden(!open)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(NotchShape(bottomRadius: open ? 28 : 10, ears: false))
        .background {
            // CSS `box-shadow: 0 28px 48px -22px`: a negative spread is a shadow cast by a 22 pt smaller shape.
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.black)
                .padding(22)
                .shadow(color: .black.opacity(0.55), radius: 24, y: 28)
                .opacity(open ? 1 : 0)
                .animation(model.motion(.liltEaseOut(0.3)), value: open)
            NotchShape(bottomRadius: open ? 28 : 10, ears: true).fill(.black)
        }
        .animation(model.motion(.liltSpring), value: open)
        .frame(width: NotchModel.panelWidth, height: NotchGeometry.panelSize.height, alignment: .top)
        .foregroundStyle(Lilt.ink)
        .font(Lilt.font(18))
        .environment(\.colorScheme, .dark)
        .coordinateSpace(.named(NotchSpace.root))
    }
}

enum NotchSpace {
    static let root = "notch-root"
}

extension NotchModel {
    /// Every animation passes through here so reduced motion switches immediately.
    func motion(_ animation: Animation) -> Animation? { reducedMotion ? nil : animation }
}

/// Notch body with rounded bottom corners and, optionally, the 14 pt concave fillets that join the screen edge.
struct NotchShape: Shape {
    var bottomRadius: CGFloat
    var ears: Bool

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(bottomRadius, rect.height / 2, rect.width / 2)
        let ear: CGFloat = ears ? 14 : 0
        var path = Path()
        path.move(to: CGPoint(x: rect.minX - ear, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX + ear, y: rect.minY))
        if ears {
            path.addArc(center: CGPoint(x: rect.maxX + ear, y: rect.minY + ear), radius: ear,
                        startAngle: .degrees(-90), endAngle: .degrees(180), clockwise: true)
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        if ears {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + ear))
            path.addArc(center: CGPoint(x: rect.minX - ear, y: rect.minY + ear), radius: ear,
                        startAngle: .degrees(0), endAngle: .degrees(-90), clockwise: true)
        }
        path.closeSubpath()
        return path
    }
}

// MARK: Compact

private struct CompactContent: View {
    let model: NotchModel

    var body: some View {
        Button { model.userOpen() } label: {
            HStack {
                WingView(model: model, side: .left).frame(width: 50, alignment: .leading)
                Spacer(minLength: 0)
                WingView(model: model, side: .right).frame(width: 50, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .opacity(model.hideHardwareWings || model.hideNotchContent ? 0 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.compactLabel)
    }
}

extension NotchModel {
    var compactLabel: String {
        let detail: String
        switch page {
        case .music: detail = music.title.isEmpty ? sourceName : music.title
        case .focus: detail = liltClock(focus.remaining)
        case .shelf: detail = "\(shelf.count) files"
        }
        return "Open the notch: \(page.rawValue), \(detail)"
    }

    func userOpen() {
        setOpen(true)
    }
}

// MARK: Wings

struct WingView: View {
    enum Side { case left, right }
    let model: NotchModel
    let side: Side

    var body: some View {
        Group {
            if side == .left { left } else { right }
        }
        .font(Lilt.font(14, .semibold))
        .monospacedDigit()
        .lineLimit(1)
    }

    @ViewBuilder private var left: some View {
        switch model.page {
        case .music:
            MiniCover(image: model.musicCover)
        case .focus:
            let color = model.focus.error != nil ? Lilt.error : model.focus.phase == .completed ? Lilt.complete : Lilt.accent2
            Circle().fill(color).frame(width: 9, height: 9)
                .background(Circle().fill(Lilt.accent2.mix(22)).frame(width: 17, height: 17).opacity(model.focus.phase == .running ? 1 : 0))
        case .shelf:
            IconView(icon: .shelf, size: 18)
        }
    }

    @ViewBuilder private var right: some View {
        if model.page == .music, model.music.playing {
            WaveView(animating: !model.reducedMotion)
        } else if model.page == .music, model.connected {
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                Text(liltClock(model.music.elapsed(at: ProcessInfo.processInfo.systemUptime)))
            }
        } else {
            Text(rightLabel).truncationMode(.tail)
        }
    }

    private var rightLabel: String {
        switch model.page {
        case .music: return model.sourceName
        case .focus:
            if model.focus.error != nil { return "!" }
            if model.focus.phase == .completed { return "Done" }
            return (model.focus.isBreak ? "B " : "") + liltClock(model.focus.remaining)
        case .shelf: return model.shelf.isEmpty ? "" : String(model.shelf.count)
        }
    }
}

struct MiniCover: View {
    let image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                IconView(icon: .music, size: 16)
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// Five bars with the study's 900 ms alternate keyframes and staggered negative delays.
struct WaveView: View {
    let animating: Bool
    private static let delays: [Double] = [0, -0.3, -0.7, -0.15, -0.5]

    var body: some View {
        TimelineView(.animation(paused: !animating)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Lilt.accent1)
                        .frame(width: 3, height: 18)
                        .scaleEffect(x: 1, y: animating ? Self.scale(time - Self.delays[index]) : 0.28)
                }
            }
            .frame(height: 18)
        }
    }

    /// `@keyframes wave {0% .25, 50% 1, 100% .45}` with ease-in-out per segment, 900 ms, alternate.
    static func scale(_ time: Double) -> CGFloat {
        let cycle = time.truncatingRemainder(dividingBy: 1.8)
        let positive = cycle < 0 ? cycle + 1.8 : cycle
        let t = positive <= 0.9 ? positive / 0.9 : (1.8 - positive) / 0.9
        func ease(_ x: Double) -> Double { x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2 }
        if t < 0.5 { return CGFloat(0.25 + 0.75 * ease(t / 0.5)) }
        return CGFloat(1 - 0.55 * ease((t - 0.5) / 0.5))
    }
}

// MARK: Open panel

private struct PanelContent: View {
    @Bindable var model: NotchModel

    var body: some View {
        VStack(spacing: 0) {
            Button { model.setOpen(false) } label: {
                HStack {
                    WingView(model: model, side: .left).frame(width: wingWidth, alignment: .leading)
                    Spacer(minLength: 0)
                    WingView(model: model, side: .right).frame(width: wingWidth, alignment: .trailing)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .opacity(model.hideHardwareWings ? 0 : 1)
            }
            .buttonStyle(.plain)
            .frame(height: model.hardwareHeight)
            .accessibilityLabel("Fold Lilt")
            .help("Fold Lilt")

            PageStrip(model: model)
                .frame(maxHeight: .infinity)

            FootView(model: model)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
        .opacity(model.hideNotchContent ? 0 : 1)
        .background {
            // Free surface folds the notch; controls sit above and take precedence.
            Color.black.opacity(0.001).onTapGesture { if !model.dismissMenus() { model.setOpen(false) } }
        }
        .overlay(alignment: .topLeading) { FocusMenuLayer(model: model) }
        .overlay(alignment: .topLeading) { ShelfMenuLayer(model: model) }
    }

    private var wingWidth: CGFloat { max(0, (model.pageWidth - model.hardwareWidth) / 2 - 8) }
}

/// All pages share one horizontal strip. Outside a swipe the active page fades and scales in after the old one leaves.
private struct PageStrip: View {
    @Bindable var model: NotchModel

    var body: some View {
        ZStack {
            ForEach(NotchPage.allCases, id: \.self) { page in
                pageView(page)
                    .modifier(PagePresentation(model: model, page: page))
            }
            if let banner = model.banner {
                BannerView(model: model, banner: banner)
            }
        }
        .frame(width: model.pageWidth)
    }

    @ViewBuilder private func pageView(_ page: NotchPage) -> some View {
        switch page {
        case .music: MusicPage(model: model)
        case .focus: FocusPage(model: model)
        case .shelf: ShelfPage(model: model)
        }
    }
}

private struct PagePresentation: ViewModifier {
    let model: NotchModel
    let page: NotchPage

    func body(content: Content) -> some View {
        let active = model.page == page
        let covered = model.banner != nil
        if let position = model.swipePosition {
            let width = model.pageWidth
            let offset = CGFloat(page.index) * width - position
            let distance = min(1, abs(offset) / width)
            content
                .offset(x: offset)
                .opacity(abs(offset) < width && !covered ? 1 - 0.5 * Double(distance) : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(!active)
                .transaction { $0.animation = nil }
        } else {
            let instant = model.instantPage || model.reducedMotion
            content
                .scaleEffect(active ? 1 : 0.99)
                .offset(y: active ? 0 : 2)
                .animation(instant ? nil : active ? .liltEaseOut(0.2).delay(0.07) : .liltEaseOut(0.14), value: active)
                .opacity(active && !covered ? 1 : 0)
                .animation(instant ? nil : active ? .liltEaseOut(0.16).delay(0.07) : .linear(duration: 0.07), value: active)
                .allowsHitTesting(active && !covered)
                .accessibilityHidden(!active || covered)
        }
    }
}

// MARK: Foot

private struct FootView: View {
    @Bindable var model: NotchModel

    var body: some View {
        HStack(spacing: 12) {
            TabStrip(model: model)
            Spacer(minLength: 0)
            Button { model.post(["action": "settingsOpen"]) } label: {
                IconView(icon: .settings, size: 17)
            }
            .buttonStyle(HoverIconStyle(size: CGSize(width: 44, height: 44), rest: Lilt.ink.mix(70), hoverBackground: Lilt.ink.mix(8)))
            .accessibilityLabel("Open Lilt settings")
            .help("Settings")
        }
    }
}

private struct TabStrip: View {
    @Bindable var model: NotchModel

    var body: some View {
        let markerIndex = model.swipePosition.map { max(0, min(CGFloat(NotchPage.allCases.count - 1), $0 / model.pageWidth)) }
            ?? CGFloat(model.page.index)
        EqualWidthRow(spacing: 2) {
            ForEach(NotchPage.allCases, id: \.self) { page in
                Button { model.setPage(page) } label: {
                    HStack(spacing: 6) {
                        IconView(icon: page.icon, size: 16)
                        Text(page.title).font(Lilt.font(13, .semibold)).tracking(0.13)
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .blendMode(.difference)
                .opacity(model.page == page ? 1 : 0.7)
                .accessibilityAddTraits(model.page == page ? [.isSelected] : [])
                .accessibilityLabel(page.title)
            }
        }
        .background(alignment: .leading) {
            GeometryReader { proxy in
                let width = (proxy.size.width - 4) / 3
                Capsule().fill(Lilt.ink)
                    .frame(width: width)
                    .offset(x: markerIndex * (width + 2))
                    .animation(model.swipePosition != nil || model.instantPage || model.reducedMotion ? nil : .tabMarker, value: markerIndex)
            }
        }
        .padding(3)
        .background(Capsule().fill(Lilt.ink.mix(8)))
        .compositingGroup()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notch views")
    }
}

/// Lays out children with the width of the widest one, like `grid-template-columns: repeat(n, 1fr)`.
struct EqualWidthRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let width = sizes.map(\.width).max() ?? 0
        let height = sizes.map(\.height).max() ?? 0
        return CGSize(width: width * CGFloat(subviews.count) + spacing * CGFloat(max(0, subviews.count - 1)), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = (bounds.width - spacing * CGFloat(max(0, subviews.count - 1))) / CGFloat(max(1, subviews.count))
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + CGFloat(index) * (width + spacing), y: bounds.minY),
                          proposal: ProposedViewSize(width: width, height: bounds.height))
        }
    }
}
