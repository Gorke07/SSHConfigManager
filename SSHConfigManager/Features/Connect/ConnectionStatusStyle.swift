import SSHConfigKit
import SwiftUI

struct ConnectionStatusStyle {
    let symbol: String
    let tint: Color
    let title: String

    static func style(for status: ConnectionStatus) -> ConnectionStatusStyle {
        switch status {
        case .reachable: .init(symbol: "checkmark.circle.fill", tint: .green, title: String(localized: "status.reachable"))
        case .authenticationRequired: .init(symbol: "key.fill", tint: .yellow, title: String(localized: "status.authenticationRequired"))
        case .hostKeyChanged: .init(symbol: "exclamationmark.shield.fill", tint: .red, title: String(localized: "status.hostKeyChanged"))
        case .unknownHostKey: .init(symbol: "questionmark.circle.fill", tint: .yellow, title: String(localized: "status.unknownHostKey"))
        case .timeout: .init(symbol: "clock.badge.xmark", tint: .red, title: String(localized: "status.timeout"))
        case .dnsFailure: .init(symbol: "network.slash", tint: .red, title: String(localized: "status.dnsFailure"))
        case .connectionRefused: .init(symbol: "xmark.octagon.fill", tint: .red, title: String(localized: "status.connectionRefused"))
        case .other: .init(symbol: "exclamationmark.circle.fill", tint: .secondary, title: String(localized: "status.other"))
        }
    }

    static var testing: ConnectionStatusStyle {
        .init(symbol: "ellipsis.circle", tint: .secondary, title: String(localized: "status.testing"))
    }
}
