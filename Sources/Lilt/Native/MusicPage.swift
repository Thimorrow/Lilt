import SwiftUI

struct MusicPage: View {
    @Bindable var model: NotchModel

    var body: some View {
        let music = model.music
        let provider = model.sourceName
        let note = music.error?.message ?? (music.buffering ? "Loading \(provider)…" : music.pending != nil ? "Waiting for \(provider)…" : "")
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                CoverView(image: model.musicCover, revision: model.coverRevision, animate: !model.reducedMotion)
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.connected ? music.title : provider)
                        .font(Lilt.font(18, .bold)).tracking(-0.18)
                    Text(subtitle(provider: provider))
                        .font(Lilt.font(14)).foregroundStyle(Lilt.ink.mix(70))
                }
                .lineLimit(1)
                .contentTransition(.opacity)
                .animation(model.motion(.liltEaseOut(0.2)), value: music.title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(model.connected ? [music.title, music.artist, music.album].filter { !$0.isEmpty }.joined(separator: " · ") : subtitle(provider: provider))
                controls(provider: provider)
            }
            .frame(height: 54)
            Group {
                if !note.isEmpty || !model.connected {
                    HStack(spacing: 8) {
                        Text(note).lineLimit(1).truncationMode(.tail).help(note)
                        if !model.connected || music.error != nil {
                            Button("Open \(provider)") { model.openPlayer() }.buttonStyle(LinkButtonStyle())
                        }
                        Spacer(minLength: 0)
                    }
                    .font(Lilt.font(12))
                    .foregroundStyle(Lilt.ink.mix(70))
                    .accessibilityElement(children: .combine)
                } else {
                    ProgressRow(model: model, provider: provider)
                }
            }
            .frame(height: 18)
        }
    }

    private func subtitle(provider: String) -> String {
        if model.connected { return [model.music.artist, provider].filter { !$0.isEmpty }.joined(separator: " · ") }
        switch model.music.availability {
        case .checking: return "Connecting…"
        case .offline: return "Not running"
        case .empty: return "Choose a song in \(provider)"
        case .unavailable: return "Connection unavailable"
        case .disabled: return "Player disabled in this test"
        case .ready: return provider
        }
    }

    private func controls(provider: String) -> some View {
        let music = model.music
        let busy = music.pending != nil
        return HStack(spacing: 4) {
            Button { model.musicCommand("previous") } label: { IconView(icon: .previous) }
                .buttonStyle(IconButtonStyle())
                .disabled(busy || !model.connected || !music.canPrevious)
                .accessibilityLabel("Previous \(provider) track")
            Button { model.togglePlayback() } label: { PlayPauseIcon(playing: music.playing, animate: !model.reducedMotion) }
                .buttonStyle(IconButtonStyle(diameter: 48, prominent: true))
                .disabled(busy || music.buffering || !model.connected || !(music.playing ? music.canPause : music.canPlay))
                .accessibilityLabel(busy ? "Waiting for \(provider)" : music.playing ? "Pause \(provider)" : "Play \(provider)")
                .help(music.playing ? "Pause \(provider)" : "Play \(provider)")
            Button { model.musicCommand("next") } label: { IconView(icon: .next) }
                .buttonStyle(IconButtonStyle())
                .disabled(busy || !model.connected || !music.canNext)
                .accessibilityLabel("Next \(provider) track")
        }
    }
}

/// Artwork with the study's track-change entrance: from 10 pt right, 0.9 scale and 0.4 opacity over 320 ms.
private struct CoverView: View {
    let image: NSImage?
    let revision: Int
    let animate: Bool

    var body: some View {
        ZStack {
            Lilt.ink.mix(8)
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                IconView(icon: .music, size: 28)
            }
        }
        .frame(width: 54, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .keyframeAnimator(initialValue: CoverMotion(), trigger: revision) { content, motion in
            content.offset(x: motion.x).scaleEffect(motion.scale).opacity(motion.opacity)
        } keyframes: { _ in
            let curve = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.16, y: 1), endControlPoint: UnitPoint(x: 0.3, y: 1))
            KeyframeTrack(\.x) {
                MoveKeyframe(animate ? 10 : 0)
                LinearKeyframe(0, duration: animate ? 0.32 : 0, timingCurve: curve)
            }
            KeyframeTrack(\.scale) {
                MoveKeyframe(animate ? 0.9 : 1)
                LinearKeyframe(1, duration: animate ? 0.32 : 0, timingCurve: curve)
            }
            KeyframeTrack(\.opacity) {
                MoveKeyframe(animate ? 0.4 : 1)
                LinearKeyframe(1, duration: animate ? 0.32 : 0, timingCurve: curve)
            }
        }
        .accessibilityHidden(true)
    }

    struct CoverMotion {
        var x: CGFloat = 0
        var scale: CGFloat = 1
        var opacity: Double = 1
    }
}

private struct ProgressRow: View {
    let model: NotchModel
    let provider: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let music = model.music
            let elapsed = music.elapsed(at: ProcessInfo.processInfo.systemUptime)
            let fraction = music.duration > 0 ? elapsed / music.duration : 0
            HStack(spacing: 10) {
                Text(liltClock(elapsed)).frame(width: 40, alignment: .leading)
                Capsule().fill(Lilt.ink.mix(18))
                    .frame(height: 5)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule().fill(Lilt.accent1).frame(width: proxy.size.width * fraction)
                        }
                    }
                    .clipShape(Capsule())
                Text(music.duration > 0 ? liltClock(music.duration) : "–:––").frame(width: 40, alignment: .trailing)
            }
            .font(Lilt.font(12))
            .monospacedDigit()
            .foregroundStyle(Lilt.ink.mix(70))
            .accessibilityElement()
            .accessibilityLabel("\(provider) playback position")
            .accessibilityValue("\(liltClock(elapsed))\(music.duration > 0 ? " of \(liltClock(music.duration))" : ", duration unknown")")
        }
    }
}
