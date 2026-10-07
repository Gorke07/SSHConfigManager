extension StringProtocol {
    /// Lowercases ASCII A–Z only. ssh_config keywords are ASCII; locale-aware
    /// lowercasing would break under the Turkish locale (I → ı).
    var asciiLowercased: String {
        var scalars = String.UnicodeScalarView()
        for scalar in unicodeScalars {
            if (65...90).contains(scalar.value), let lower = Unicode.Scalar(scalar.value + 32) {
                scalars.append(lower)
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    /// True if any Unicode scalar is a control character: U+0000–U+001F (except U+0009 tab) or U+007F.
    var containsControlCharacter: Bool {
        unicodeScalars.contains { ($0.value < 0x20 && $0.value != 0x09) || $0.value == 0x7F }
    }
}
