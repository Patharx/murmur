import MurmurCore
import SwiftUI

struct ListeningView: View {
    var library: Library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var session = ListeningSession()

    var body: some View {
        VStack(spacing: 22) {
            header
            Text(ListeningText.timer(session.elapsed))
                .font(MurmurType.timer)
                .foregroundStyle(Theme.text)
                .monospacedDigit()
                .tracking(-1.5)
                .accessibilityLabel("Listening for \(ListeningText.timer(session.elapsed))")
            Text(MurmurCopy.writtenDown)
                .font(MurmurType.secondary)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            waveform
            transcript
            Spacer(minLength: 8)
            controls
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .task { await session.start() }
    }

    private var header: some View {
        HStack {
            Button(MurmurCopy.neverMind) {
                session.abandon()
                dismiss()
            }
            .font(MurmurType.secondary)
            .foregroundStyle(Theme.textSecondary)
            Spacer()
            HStack(spacing: 8) {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 7, height: 7)
                    .shadow(color: Theme.accent.opacity(0.8), radius: 5)
                Text(MurmurCopy.listening)
                    .font(MurmurType.chip)
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.accent400)
            }
            Spacer()
            Color.clear.frame(width: 72, height: 1)
        }
    }

    private var waveform: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(session.levels.enumerated()), id: \.offset) { _, height in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.accent.opacity(0.85))
                    .frame(width: 3, height: height)
            }
        }
        .frame(height: 68)
        .animation(reduceMotion ? nil : .linear(duration: 0.1), value: session.levels)
        .accessibilityHidden(true)
    }

    private var transcript: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(MurmurCopy.asYouSpeak)
                .font(MurmurType.chip)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Theme.textTertiary)
            Group {
                if let failure = session.failure {
                    Text(failure)
                        .foregroundStyle(Theme.textSecondary)
                } else if session.liveText.isEmpty {
                    Text(" ")
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(Theme.accent)
                                .frame(width: 2, height: 18)
                        }
                } else {
                    Text(session.liveText)
                        .foregroundStyle(Theme.text.opacity(0.85))
                }
            }
            .font(MurmurType.body)
            .lineSpacing(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private var controls: some View {
        HStack(spacing: 28) {
            circleButton(system: session.isPaused ? "play" : "pause", label: session.isPaused ? "Carry on" : "Pause") {
                session.togglePause()
            }
            Button {
                if let captured = session.stop() {
                    library.keepVoiceNote(captured: captured)
                }
                dismiss()
            } label: {
                ZStack {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 74, height: 74)
                        .shadow(color: Theme.accent.opacity(0.45), radius: 16)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.bg)
                        .frame(width: 23, height: 23)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop listening")
            circleButton(system: "bookmark", label: "Drop a bookmark") {
                session.bookmark()
            }
        }
    }

    private func circleButton(system: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Theme.accent400)
                .frame(width: 52, height: 52)
                .overlay(Circle().stroke(Theme.outline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
