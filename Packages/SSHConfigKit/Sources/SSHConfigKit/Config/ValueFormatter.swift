/// Converts between the raw text of a directive value and the form shown/edited in the UI.
/// Only keys that take exactly one argument are unquoted/quoted; multi-argument
/// values (LocalForward, SendEnv, ProxyCommand …) are shown and written verbatim.
public enum ValueFormatter {
    static let singleValueKeys: Set<String> = [
        "hostname", "user", "port", "identityfile", "certificatefile",
        "identityagent", "controlpath", "hostkeyalias", "proxyjump",
    ]

    public static func display(key: String, rawValue: String) -> String {
        guard singleValueKeys.contains(key.asciiLowercased) else { return rawValue }
        let args = LineTokenizer.arguments(of: rawValue)
        return args.count == 1 ? args[0] : rawValue
    }

    public static func encode(key: String, value: String) -> String {
        guard singleValueKeys.contains(key.asciiLowercased),
              value.unicodeScalars.contains(where: LineTokenizer.isSpace) else { return value }

        let scalars = Array(value.unicodeScalars)
        let isProperlyQuoted = scalars.count >= 2 && scalars.first == "\"" && scalars.last == "\""

        guard !isProperlyQuoted else { return value }
        return "\"" + value + "\""
    }
}
