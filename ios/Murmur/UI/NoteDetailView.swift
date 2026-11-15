import AVFoundation
import MurmurCore
import SwiftUI

struct NoteDetailView: View {
    var library: Library
    var id: String
    @Environment(\.dismiss) private var dismiss
    @State private var player = NoteAudioPlayer()
    @State private var editing = false
    @State private var title = ""
    @State private var said = ""
    @State private var folder = ""
    @State private var phoneOnly = false

    private var path: String? { library.notes.first { $0.id == id }?.path }
    private var document: NoteDocument? { path.flatMap { library.load(path: $0) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let document, let path {
                    if editing {
                        editor()
                    } else {
                        Text(document.title.isEmpty ? "Untitled" : document.title)
                            .font(MurmurType.noteTitle)
                            .foregroundStyle(Theme.text)
                            .tracking(-0.4)
                        meta(document)
                        ForEach(Array(library.audioFiles(path: path).enumerated()), id: \.offset) { _, audio in
                            playerCard(url: audio, duration: document.durationSeconds ?? 0)
                        }
                        gist(document)
                        transcript(document)
                    }
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
                        PhosphorIcon(name: "caret-left", size: 16)
                        Text(MurmurCopy.today)
                    }
                    .font(MurmurType.secondary)
                    .foregroundStyle(Theme.textSecondary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    Button(editing ? MurmurCopy.keep : "Edit") {
                        if editing {
                            keepEdits()
                        } else if let document {
                            title = document.title
                            said = document.said
                            folder = document.folder
                            phoneOnly = document.phoneOnly
                            editing = true
                        }
                    }
                    .font(MurmurType.secondary)
                    .foregroundStyle(Theme.accent400)
                    if let path, let url = library.fileURL(path: path) {
                        ShareLink(item: url) {
                            PhosphorIcon(name: "export", size: 16)
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 34, height: 34)
                                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.chipEdge, lineWidth: 1))
                        }
                        .accessibilityLabel("Export this note")
                    }
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
                PhosphorIcon(name: player.isPlaying ? "pause" : "play", size: 16)
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
        if let gist = document.gist, !gist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            gistCard(gist)
        }
    }

    private func gistCard(_ gist: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                PhosphorIcon(name: "sparkle", size: 14)
                    .foregroundStyle(Theme.accent400)
                Text(MurmurCopy.theGist)
                    .font(MurmurType.chip)
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.accent400)
                Spacer()
            }
            Text(gist)
                .font(MurmurType.custom(14, weight: .regular, relativeTo: .subheadline))
                .foregroundStyle(Theme.text.opacity(0.9))
                .lineSpacing(5)
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

    private func editor() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Title", text: $title)
                .font(MurmurType.noteTitle)
                .foregroundStyle(Theme.text)
            TextEditor(text: $said)
                .font(MurmurType.body)
                .foregroundStyle(Theme.text.opacity(0.85))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 180)
            Toggle(isOn: $phoneOnly) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep on this phone only")
                        .font(MurmurType.rowTitle)
                        .foregroundStyle(Theme.text)
                    Text("A later sync leaves it here. A copy already in Drive stays there.")
                        .font(MurmurType.meta)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .tint(Theme.accent)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(NotebookLayout.chipFolders, id: \.self) { name in
                        FolderChip(title: NotebookLayout.chipLabel(for: name), active: folder == name) {
                            folder = name
                        }
                    }
                }
            }
        }
    }

    private func keepEdits() {
        guard let path, var document = library.load(path: path) else { return }
        document.title = title
        document.said = said
        document.folder = folder
        document.phoneOnly = phoneOnly
        document.modified = NoteClock.stamp()
        _ = library.save(document, path: path)
        editing = false
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
