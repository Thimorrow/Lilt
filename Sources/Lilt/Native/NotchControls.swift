import SwiftUI

/// `.icon-btn`: round, hover tint, 0.96 press scale over 160 ms, half opacity when disabled.
struct IconButtonStyle: ButtonStyle {
    var diameter: CGFloat = 44
    var prominent = false
    var rest: Color = Lilt.ink

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, style: self)
    }

    private struct Styled: View {
        let configuration: Configuration
        let style: IconButtonStyle
        @State private var hover = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .foregroundStyle(style.prominent ? Color.black : hover && enabled ? Lilt.ink : style.rest)
                .frame(width: style.diameter, height: style.diameter)
                .background(Circle().fill(background))
                .contentShape(Circle())
                .scaleEffect(configuration.isPressed && enabled ? 0.96 : 1)
                .opacity(enabled ? 1 : 0.5)
                .animation(.liltEaseOut(0.16), value: configuration.isPressed)
                .animation(.linear(duration: 0.16), value: hover)
                .onHover { hover = $0 }
        }

        private var background: Color {
            if style.prominent { return hover && enabled ? .white : Lilt.ink }
            return hover && enabled ? Lilt.ink.mix(12) : .clear
        }
    }
}

/// Square or capsule icon target that tints its glyph and background on hover (settings, shelf actions).
struct HoverIconStyle: ButtonStyle {
    var size: CGSize
    var rest: Color
    var hoverBackground: Color
    var radius: CGFloat = 999

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, style: self)
    }

    private struct Styled: View {
        let configuration: Configuration
        let style: HoverIconStyle
        @State private var hover = false

        var body: some View {
            configuration.label
                .foregroundStyle(hover ? Lilt.ink : style.rest)
                .frame(width: style.size.width, height: style.size.height)
                .background(RoundedRectangle(cornerRadius: min(style.radius, style.size.height / 2), style: .continuous)
                    .fill(hover ? style.hoverBackground : .clear))
                .contentShape(Rectangle())
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .animation(.linear(duration: 0.14), value: hover)
                .animation(.liltEaseOut(0.15), value: configuration.isPressed)
                .onHover { hover = $0 }
        }
    }
}

/// `.focus-extend`, `.focus-end`, `.shelf-command`: small tinted pills.
struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration) }

    private struct Styled: View {
        let configuration: Configuration
        @State private var hover = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .font(Lilt.font(12))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(minHeight: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Lilt.ink.mix(hover && enabled ? 15 : 8)))
                .opacity(enabled ? 1 : 0.4)
                .contentShape(Rectangle())
                .scaleEffect(configuration.isPressed && enabled ? 0.96 : 1)
                .animation(.liltEaseOut(0.15), value: configuration.isPressed)
                .animation(.linear(duration: 0.14), value: hover)
                .onHover { hover = $0 }
        }
    }
}

/// Underlined inline text action (`Open Spotify`, `Open Settings`).
struct LinkButtonStyle: ButtonStyle {
    var size: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration, size: size) }

    private struct Styled: View {
        let configuration: Configuration
        let size: CGFloat
        @State private var hover = false

        var body: some View {
            configuration.label
                .font(Lilt.font(size))
                .underline(true, color: Lilt.ink.mix(hover ? 100 : 45))
                .foregroundStyle(Lilt.ink)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .contentShape(Rectangle())
                .animation(.linear(duration: 0.14), value: hover)
                .onHover { hover = $0 }
        }
    }
}

/// Rows inside the in-notch dropdowns.
struct MenuRowStyle: ButtonStyle {
    var destructive = false

    func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration, destructive: destructive) }

    private struct Styled: View {
        let configuration: Configuration
        let destructive: Bool
        @State private var hover = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .font(Lilt.font(13, .medium))
                .lineLimit(1)
                .foregroundStyle(!enabled ? Lilt.ink.mix(35) : destructive ? Lilt.destructive : Lilt.ink)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hover && enabled ? Lilt.ink.mix(9) : .clear))
                .contentShape(Rectangle())
                .onHover { hover = $0 }
        }
    }
}

/// Shared surface of the focus and shelf dropdowns.
struct MenuSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Lilt.menu))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Lilt.ink.mix(14), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 10, y: 8)
    }
}

/// Interruptible dropdown motion anchored at the trigger: 200 ms open, 150 ms ease-in close.
struct MenuTransition: ViewModifier {
    let shown: Bool
    let anchor: UnitPoint

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown ? 1 : 0.95, anchor: anchor)
            .opacity(shown ? 1 : 0)
    }
}

extension AnyTransition {
    static func menu(anchor: UnitPoint) -> AnyTransition {
        .modifier(active: MenuTransition(shown: false, anchor: anchor), identity: MenuTransition(shown: true, anchor: anchor))
    }
}

/// Numeric minute input in the dropdown forms.
struct MinuteField: View {
    @Binding var value: String
    var label: String
    var onSubmit: () -> Void

    var body: some View {
        TextField(label, text: $value)
            .textFieldStyle(.plain)
            .font(Lilt.font(16))
            .monospacedDigit()
            .padding(.horizontal, 5)
            .frame(width: 58, height: 28)
            .background(RoundedRectangle(cornerRadius: 6).fill(Lilt.field))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Lilt.fieldBorder, lineWidth: 1))
            .accessibilityLabel(label)
            .onSubmit(onSubmit)
    }
}

/// Play ⇄ pause: both glyphs stay mounted and cross-fade with a deep scale and a little blur, so either direction animates.
struct PlayPauseIcon: View {
    let playing: Bool
    let animate: Bool

    var body: some View {
        ZStack {
            glyph(.play, shown: !playing)
            glyph(.pause, shown: playing)
        }
        .animation(animate ? .spring(duration: 0.35, bounce: 0) : nil, value: playing)
    }

    private func glyph(_ icon: NotchIcon, shown: Bool) -> some View {
        IconView(icon: icon)
            .scaleEffect(shown ? 1 : 0.3)
            .opacity(shown ? 1 : 0)
            .blur(radius: shown ? 0 : 3)
    }
}
