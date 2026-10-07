import CryptoKit
import Foundation

public struct FileFingerprint: Equatable, Sendable {
    public let sha256: Data

    public init(data: Data) {
        sha256 = Data(SHA256.hash(data: data))
    }

    /// Returns nil when the file does not exist. Follows symlinks.
    public static func of(fileAt url: URL) throws -> FileFingerprint? {
        do {
            return FileFingerprint(data: try Data(contentsOf: url))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }
}
