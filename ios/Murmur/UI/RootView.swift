import SwiftUI

struct RootView: View {
    @Bindable var library: Library
    @AppStorage("murmur.notebookStarted") private var started = false

    var body: some View {
        Group {
            if started {
                MainShell(library: library)
            } else {
                OnboardingView {
                    started = true
                }
            }
        }
        .environment(library)
        .background(Theme.bg)
    }
}

struct OnboardingView: View {
    var start: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 24)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Theme.accent400, Theme.accent700],
                        center: UnitPoint(x: 0.35, y: 0.3),
                        startRadius: 0,
                        endRadius: 40
                    )
                )
                .frame(width: 62, height: 62)
                .accessibilityHidden(true)
            Text(MurmurCopy.onboardingHeadline)
                .font(MurmurType.onboarding)
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .tracking(-0.8)
            Text("The thought you had on a walk. The letter you drafted at midnight. The three lines you copied out of a book. Murmur holds all of it in one notebook, and once a week reads it back to you.")
                .font(MurmurType.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
            VStack(alignment: .leading, spacing: 16) {
                OnboardingPoint(number: "01", text: "Spoken or typed, it all lands in the same place. Transcription happens on your iPhone.")
                OnboardingPoint(number: "02", text: "Everything is kept on this iPhone as you write it. Nothing has to leave the phone for a note to exist.")
                OnboardingPoint(number: "03", text: "It's open source. Nothing here is a subscription to your own thoughts.")
            }
            Spacer(minLength: 12)
            OutlinedButton(title: MurmurCopy.startNotebook, action: start)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }
}

private struct OnboardingPoint: View {
    var number: String
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(MurmurType.meta)
                .foregroundStyle(Theme.accent)
                .frame(width: 24, alignment: .leading)
            Text(text)
                .font(MurmurType.secondary)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

enum AppTab: Hashable {
    case today
    case ask
    case weekly
    case you
}

struct MainShell: View {
    @Bindable var library: Library
    @State private var tab: AppTab = .today
    @State private var listening = false
    @State private var composing = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.bg.ignoresSafeArea()
            Group {
                switch tab {
                case .today:
                    TodayView(library: library, compose: { composing = true })
                case .ask:
                    AskView(library: library)
                case .weekly:
                    WeeklyView()
                case .you:
                    YouView(library: library)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 96)
            MurmurTabBar(tab: $tab) {
                listening = true
            }
        }
        .fullScreenCover(isPresented: $listening) {
            ListeningView(library: library)
        }
        .fullScreenCover(isPresented: $composing) {
            ComposeView(library: library)
        }
    }
}

struct MurmurTabBar: View {
    @Binding var tab: AppTab
    var listen: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            HStack {
                tabButton(.today, system: "sun.max", title: MurmurCopy.today)
                tabButton(.ask, system: "sparkle", title: MurmurCopy.ask)
                Color.clear.frame(width: 72, height: 44)
                tabButton(.weekly, system: "envelope", title: MurmurCopy.weekly)
                tabButton(.you, system: "person", title: MurmurCopy.you)
            }
            .padding(.top, 28)
            .padding(.horizontal, 8)
            .frame(height: 86)
            .background(Theme.bg.opacity(0.88))
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) { Theme.divider.frame(height: 1) }

            Button(action: listen) {
                ZStack {
                    if !reduceMotion {
                        Circle()
                            .stroke(Theme.accent.opacity(0.5), lineWidth: 1)
                            .frame(width: 56, height: 56)
                            .modifier(RecordPulse())
                    }
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 56, height: 56)
                        .shadow(color: Theme.accent.opacity(0.4), radius: 11, y: 6)
                    Image(systemName: "waveform")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Theme.bg)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start listening")
            .offset(y: -22)
        }
    }

    private func tabButton(_ value: AppTab, system: String, title: String) -> some View {
        Button {
            tab = value
        } label: {
            VStack(spacing: 4) {
                Image(systemName: system)
                    .font(.system(size: 18, weight: .regular))
                Text(title)
                    .font(MurmurType.custom(10, weight: .medium, relativeTo: .caption2))
            }
            .foregroundStyle(tab == value ? Theme.accent400 : Theme.text.opacity(0.42))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(tab == value ? .isSelected : [])
    }
}

private struct RecordPulse: ViewModifier {
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(on ? 1.7 : 1)
            .opacity(on ? 0 : 0.5)
            .onAppear { on = true }
            .animation(.easeOut(duration: 2).repeatForever(autoreverses: false), value: on)
    }
}
