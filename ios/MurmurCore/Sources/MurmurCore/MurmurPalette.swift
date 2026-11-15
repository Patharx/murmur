import Foundation

public struct MurmurRGB: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(hex: UInt32) {
        red = Double((hex >> 16) & 0xff) / 255
        green = Double((hex >> 8) & 0xff) / 255
        blue = Double(hex & 0xff) / 255
    }
}

/// Nocturne tokens from DESIGN_SPEC §1. The only place these numbers live.
public enum MurmurPalette {
    public static let bg = MurmurRGB(hex: 0x161826)
    public static let surface = MurmurRGB(hex: 0x232532)
    public static let text = MurmurRGB(hex: 0xE9E9ED)
    public static let accent = MurmurRGB(hex: 0x9184D9)
    public static let accent400 = MurmurRGB(hex: 0xB5ABFC)
    public static let accent300 = MurmurRGB(hex: 0xD2CEFD)
    public static let accent700 = MurmurRGB(hex: 0x5D5294)
    public static let accent800 = MurmurRGB(hex: 0x423A6A)
    public static let neutral800 = MurmurRGB(hex: 0x3F424D)
    public static let section = MurmurRGB(hex: 0x262A60)
    public static let sectionGlow = MurmurRGB(hex: 0x353B80)

    public static let textSecondary = 0.60
    public static let textTertiary = 0.45
    public static let textQuaternary = 0.40
    public static let dividerOpacity = 0.08
}

public enum MurmurCopy {
    public static let neverMind = "Never mind"
    public static let keep = "Keep"
    public static let close = "Close"
    public static let listening = "Listening"
    public static let asYouSpeak = "As you speak"
    public static let theGist = "The gist"
    public static let whatYouSaid = "What you said"
    public static let readItBack = "Read it back to me"
    public static let onPhone = "On phone"
    public static let keptAsYouType = "Kept on this iPhone as you type — no connection needed"
    public static let writtenDown = "Written down on this iPhone — nothing sent yet"
    public static let startNotebook = "Start my notebook"
    public static let onboardingHeadline = "Say it or write it.\nI'll keep it either way."
    public static let sayItInstead = "Say it instead"
    public static let today = "Today"
    public static let ask = "Ask"
    public static let weekly = "Weekly"
    public static let you = "You"
    public static let rebuildIndex = "Rebuild the index"
    public static let rebuildDetail = "The notes stay in the files. This only refreshes the list."
    public static let notesLiveHere = "Just this iPhone"
    public static let weeklyEmpty = "On Sunday, a letter from the week."
    public static let askHint = "A word finds notes. A question gets an answer — either way it's all your own words."
    public static let copyWhatYouSaid = "Copy what you said"

    public static let allUserFacing = [
        neverMind, keep, close, listening, asYouSpeak, theGist, whatYouSaid, readItBack,
        onPhone, keptAsYouType, writtenDown, startNotebook, onboardingHeadline, sayItInstead,
        today, ask, weekly, you, rebuildIndex, rebuildDetail, notesLiveHere, weeklyEmpty,
        askHint, copyWhatYouSaid,
    ]
}
