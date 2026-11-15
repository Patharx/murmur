import Foundation

/// 26-character Crockford ULID. Offline, sortable by creation time, the only identity a note has.
public struct ULID: Equatable, Sendable, Hashable, CustomStringConvertible {
    public let description: String

    public init() {
        var bytes = [UInt8](repeating: 0, count: 10)
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: 0...255)
        }
        self.init(timestamp: Date(), randomness: bytes)
    }

    public init(timestamp: Date, randomness: [UInt8]) {
        let millis = UInt64(max(0, timestamp.timeIntervalSince1970 * 1000))
        var data = [UInt8](repeating: 0, count: 16)
        data[0] = UInt8((millis >> 40) & 0xff)
        data[1] = UInt8((millis >> 32) & 0xff)
        data[2] = UInt8((millis >> 24) & 0xff)
        data[3] = UInt8((millis >> 16) & 0xff)
        data[4] = UInt8((millis >> 8) & 0xff)
        data[5] = UInt8(millis & 0xff)
        for index in 0..<10 {
            data[6 + index] = index < randomness.count ? randomness[index] : 0
        }
        description = Self.encode(data)
    }

    public init?(parsing text: String) {
        guard text.count == 26 else { return nil }
        guard text.unicodeScalars.allSatisfy({ Self.alphabet.contains($0) }) else { return nil }
        description = text
    }

    public var timestamp: Date? {
        guard let parsed = Self.decode(description) else { return nil }
        let millis = (UInt64(parsed[0]) << 40)
            | (UInt64(parsed[1]) << 32)
            | (UInt64(parsed[2]) << 24)
            | (UInt64(parsed[3]) << 16)
            | (UInt64(parsed[4]) << 8)
            | UInt64(parsed[5])
        return Date(timeIntervalSince1970: Double(millis) / 1000)
    }

    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ".unicodeScalars)

    /// Crockford base32 of a 128-bit value, two zero pad bits on the left, 26 characters.
    private static func encode(_ data: [UInt8]) -> String {
        var bits: [Bool] = [false, false]
        for byte in data {
            for shift in stride(from: 7, through: 0, by: -1) {
                bits.append(((byte >> shift) & 1) == 1)
            }
        }
        var out = ""
        var index = 0
        while index + 5 <= bits.count {
            var value = 0
            for offset in 0..<5 {
                value = (value << 1) | (bits[index + offset] ? 1 : 0)
            }
            out.unicodeScalars.append(alphabet[value])
            index += 5
        }
        return out
    }

    private static func decode(_ text: String) -> [UInt8]? {
        var bits: [Bool] = []
        for scalar in text.unicodeScalars {
            guard let index = alphabet.firstIndex(of: scalar) else { return nil }
            for shift in stride(from: 4, through: 0, by: -1) {
                bits.append(((index >> shift) & 1) == 1)
            }
        }
        guard bits.count >= 130 else { return nil }
        let dataBits = Array(bits.dropFirst(2).prefix(128))
        var bytes: [UInt8] = []
        var index = 0
        while index + 8 <= dataBits.count {
            var byte: UInt8 = 0
            for offset in 0..<8 {
                byte = (byte << 1) | (dataBits[index + offset] ? 1 : 0)
            }
            bytes.append(byte)
            index += 8
        }
        return bytes
    }
}
