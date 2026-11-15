import AVFoundation
import MurmurCore
import SwiftUI

struct NoteDetailView: View {
    var library: Library
    var path: String
    @Environment(\.dismiss) private var dismiss
    @State private var player = NoteAudioPlayer()

    private var document: NoteDocument? { library.load(path: path) }
    private var row: NoteRow? { library.notes.first { $0.path == path } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let document {
                    Text(document.title.isEmpty ? "Untitled" : document.title)
                        .font(MurmurType.noteTitle)
                        .foregroundStyle(Theme.text)
                        .tracking(-0.4)
                    meta(document)
                    if let audio = library.audioURL(for: path, filename: document.audioFilename) {
                        playerCard(url: audio, duration: document.durationSeconds ?? 0)
                    }
                    gist(document)
                    transcript(document)
                } else {
                    Text("This note isn't in the files anymore.")
                        .font(MurmurType.body)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(Theme.bg)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text(MurmurCopy.today)
                    }
                    .font(MurmurType.secondary)
                    .foregroundStyle(Theme.textSecondary)
                }
            }
            if let url = library.fileURL(path: path) {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 34, height: 34)
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.chipEdge, lineWidth: 1))
                    }
                    .accessibilityLabel("Export this note")
                }
            }
        }
        .toolbarBackground(Theme.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private func meta(_ document: NoteDocument) -> some View {
        HStack(spacing: 6) {
            Text(Self.clock.string(from: document.created.date))
            if let duration = document.durationSeconds, duration > 0 {
                Text("·")
                Text(ListeningText.timer(TimeInterval(duration)))
            }
            Text("·")
            Text(NotebookLayout.chipLabel(for: document.folder))
            if row?.onPhoneOnly != false {
                Text(MurmurCopy.onPhone)
                    .font(MurmurType.chip)
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .overlay(Capsule().stroke(Theme.accent.opacity(0.55), lineWidth: 1))
                    .foregroundStyle(Theme.accent400)
            }
        }
        .font(MurmurType.meta)
        .foregroundStyle(Theme.textTertiary)
        .monospacedDigit()
    }

    private func playerCard(url: URL, duration: Int) -> some View {
        HStack(spacing: 12) {
            Button {
                player.toggle(url: url)
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.accent400)
                    .frame(width: 38, height: 38)
                    .background(Theme.accent.opacity(0.16), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            GeometryReader { proxy in
                let progress = player.progress
                HStack(spacing: 2) {
                    ForEach(0..<32, id: \.self) { index in
                        let played = Double(index) / 32 < progress
                        RoundedRectangle(cornerRadius: 1)
                            .fill(played ? Theme.accent400 : Theme.accent.opacity(0.4))
                            .frame(width: 3, height: 8 + CGFloat(index % 5) * 3)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
            }
            .frame(height: 32)
            .accessibilityHidden(true)
            Text(ListeningText.timer(player.isPlaying ? player.elapsed : TimeInterval(duration)))
                .font(MurmurType.meta)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.neutral800, lineWidth: 1))
    }

    @ViewBuilder
    private func gist(_ document: NoteDocument) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "sparkle")
                    .foregroundStyle(Theme.accent400)
                Text(MurmurCopy.theGist)
                    .font(MurmurType.chip)
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.accent400)
                Spacer()
            }
            if let gist = document.gist, !gist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(gist)
                    .font(MurmurType.custom(14, weight: .regular, relativeTo: .subheadline))
                    .foregroundStyle(Theme.text.opacity(0.9))
                    .lineSpacing(5)
            } else {
                OutlinedButton(title: MurmurCopy.readItBack) {}
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Theme.accent800.opacity(0.5), Theme.surface.opacity(0.65)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.accent.opacity(0.28), lineWidth: 1))
    }

    private func transcript(_ document: NoteDocument) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(MurmurCopy.whatYouSaid)
                .font(MurmurType.chip)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Theme.textTertiary)
            Text(document.said.isEmpty ? " " : document.said)
                .font(MurmurType.body)
                .foregroundStyle(Theme.text.opacity(0.78))
                .lineSpacing(8)
                .textSelection(.enabled)
        }
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "H:mm"
        return formatter
    }()
}

@MainActor
@Observable
final class NoteAudioPlayer {
    var isPlaying = false
    var progress = 0.0
    var elapsed: TimeInterval = 0
    private var player: AVAudioPlayer?
    private var timer: Timer?

    func toggle(url: URL) {
        if isPlaying {
            player?.pause()
            isPlaying = false
            timer?.invalidate()
            return
        }
        if player == nil || player?.url != url {
            player = try? AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player?.play()
        isPlaying = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                self.elapsed = player.currentTime
                let duration = max(player.duration, 0.01)
                self.progress = player.currentTime / duration
                if !player.isPlaying {
                    self.isPlaying = false
                    self.timer?.invalidate()
                }
            }
        }
    }
}
