import Foundation

struct SSHHost: Identifiable, Codable, Hashable {
    var id = UUID()
    var label: String = ""
    var hostname: String = ""
    var port: Int = 22
    var username: String = ""
    var group: String = ""
    var lastConnected: Date?

    var displayName: String { label.isEmpty ? hostname : label }
    var subtitle: String { "\(username)@\(hostname)\(port == 22 ? "" : ":\(port)")" }
    var knownHostKey: String { "\(hostname.lowercased()):\(port)" }
}

enum TerminalTheme: String, CaseIterable, Identifiable {
    case midnight, dark, solarized, light
    var id: String { rawValue }
    var title: String {
        switch self {
        case .midnight: return "Midnight"
        case .dark: return "Dark"
        case .solarized: return "Solarized"
        case .light: return "Light"
        }
    }
    /// (background, foreground, caret) as hex
    var colors: (bg: UInt32, fg: UInt32, caret: UInt32) {
        switch self {
        case .midnight:  return (0x141729, 0xE6E9F2, 0x21D07A)
        case .dark:      return (0x000000, 0xDDDDDD, 0xFFFFFF)
        case .solarized: return (0x002B36, 0x93A1A1, 0x268BD2)
        case .light:     return (0xFAFAFA, 0x222222, 0x0060DF)
        }
    }
}
