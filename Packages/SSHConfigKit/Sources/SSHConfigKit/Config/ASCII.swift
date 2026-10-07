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
}
