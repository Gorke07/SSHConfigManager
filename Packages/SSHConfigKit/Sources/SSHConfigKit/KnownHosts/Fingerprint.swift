import CryptoKit
import Foundation

public enum Fingerprint {
    /// `ssh-keygen -lf` style: "SHA256:" + unpadded base64 of SHA-256 over the key blob.
    public static func sha256(base64Key: String) -> String? {
        guard let blob = Data(base64Encoded: base64Key) else { return nil }
        var digest = Data(SHA256.hash(data: blob)).base64EncodedString()
        while digest.hasSuffix("=") { digest.removeLast() }
        return "SHA256:" + digest
    }
}
