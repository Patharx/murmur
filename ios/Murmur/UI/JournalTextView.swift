import SwiftUI
import UIKit

/// The written body. While words are still coming in, they sit at the cursor in the accent colour.
struct JournalTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var cursor: Int
    var pending: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.delegate = context.coordinator
        view.font = UIFont(name: "Inter Variable", size: 15.5) ?? .preferredFont(forTextStyle: .body)
        view.textColor = UIColor(red: 0.914, green: 0.914, blue: 0.929, alpha: 0.8)
        view.tintColor = UIColor(red: 0.710, green: 0.671, blue: 0.988, alpha: 1)
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.keyboardAppearance = .dark
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        let ns = text as NSString
        let location = min(max(0, cursor), ns.length)
        if pending.isEmpty {
            if view.attributedText.string != text {
                view.attributedText = NSAttributedString(string: text, attributes: Self.bodyAttributes)
            }
            view.isEditable = true
            if !context.coordinator.editing, view.selectedRange.location != location {
                view.selectedRange = NSRange(location: location, length: 0)
            }
        } else {
            let shown = NSMutableAttributedString(string: ns.substring(to: location), attributes: Self.bodyAttributes)
            shown.append(NSAttributedString(string: pending, attributes: Self.pendingAttributes))
            shown.append(NSAttributedString(string: ns.substring(from: location), attributes: Self.bodyAttributes))
            if view.attributedText != shown {
                view.attributedText = shown
            }
            view.isEditable = false
        }
    }

    private static let bodyAttributes: [NSAttributedString.Key: Any] = [
        .font: UIFont(name: "Inter Variable", size: 15.5) ?? .preferredFont(forTextStyle: .body),
        .foregroundColor: UIColor(red: 0.914, green: 0.914, blue: 0.929, alpha: 0.8),
    ]

    private static let pendingAttributes: [NSAttributedString.Key: Any] = [
        .font: UIFont(name: "Inter Variable", size: 15.5) ?? .preferredFont(forTextStyle: .body),
        .foregroundColor: UIColor(red: 0.710, green: 0.671, blue: 0.988, alpha: 0.95),
    ]

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: JournalTextView
        var editing = false

        init(_ parent: JournalTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
            parent.cursor = textView.selectedRange.location
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard parent.pending.isEmpty else { return }
            parent.cursor = textView.selectedRange.location
        }

        func textViewDidBeginEditing(_ textView: UITextView) { editing = true }
        func textViewDidEndEditing(_ textView: UITextView) { editing = false }
    }
}
