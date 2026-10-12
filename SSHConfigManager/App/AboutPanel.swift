import AppKit

enum AboutPanel {
    static let keyboardShortcutsLicense = """
    MIT License

    Copyright (c) Sindre Sorhus <sindresorhus@gmail.com> (https://sindresorhus.com)

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    """

    /// Sparkle's license with the licenses of the code it bundles, copied verbatim from the package checkout.
    static var sparkleLicense: String {
        guard let url = Bundle.main.url(forResource: "Sparkle-LICENSE", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }

    /// Spec §6.6: third-party licenses are listed in the About panel.
    static var credits: NSAttributedString {
        let result = NSMutableAttributedString()
        let bold: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.labelColor]
        let plain: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.labelColor]
        let heading = String(localized: "about.thirdParty")
        result.append(NSAttributedString(string: heading + "\n\n", attributes: bold))
        result.append(NSAttributedString(string: "KeyboardShortcuts\n", attributes: bold))
        result.append(NSAttributedString(string: keyboardShortcutsLicense + "\n\n", attributes: plain))
        result.append(NSAttributedString(string: "Sparkle\n", attributes: bold))
        result.append(NSAttributedString(string: sparkleLicense, attributes: plain))
        return result
    }

    @MainActor
    static func show() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
