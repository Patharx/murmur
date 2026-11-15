import SwiftUI

@main
struct MurmurApp: App {
    @State private var library = Library.live()

    var body: some Scene {
        WindowGroup {
            Group {
                if let library {
                    RootView(library: library)
                } else {
                    Text("The notebook couldn't be opened on this iPhone.")
                        .font(MurmurType.body)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.bg)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}
