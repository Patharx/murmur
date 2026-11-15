import Foundation

struct CapturedAudio: Equatable {
    var url: URL
    var started: Date
    var duration: TimeInterval
    var liveText: String
    var bookmarks: [TimeInterval]
}
