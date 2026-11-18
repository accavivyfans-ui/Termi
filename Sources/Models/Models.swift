import Foundation

enum AuthKind: String, Codable, CaseIterable, Identifiable {
    case password, key
    var id: String { rawValue }
    var title: String { self == .password ? "비밀번호" : "SSH 키" }
}

struct SSHHost: Identifiable, Codable, Hashable {
    var id = UUID()
    var label: String = ""
    var hostname: String = ""
    var port: Int = 22
    var username: String = ""
    var group: String = ""
    var lastConnected: Date?
    /// nil = 비밀번호 (이전 버전 호환)
    var auth: AuthKind?
    var keyID: UUID?

    var authKind: AuthKind { auth ?? .password }
    var displayName: String { label.isEmpty ? hostname : label }
    var subtitle: String { "\(username)@\(hostname)\(port == 22 ? "" : ":\(port)")" }
    var knownHostKey: String { "\(hostname.lowercased()):\(port)" }
    var initial: String { String(displayName.prefix(1)).uppercased() }
}

/// 키체인에 저장되는 SSH 키의 메타데이터. 개인키 자체는 iOS 키체인에 따로 보관.
struct SSHKeyItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var type: String          // ssh-ed25519, ssh-rsa ...
    var publicKey: String     // OpenSSH 한 줄 형식
    var fingerprint: String
    var created = Date()

    var typeLabel: String {
        switch type {
        case "ssh-ed25519": return "ED25519"
        case "ssh-rsa": return "RSA"
        default: return type.uppercased()
        }
    }
}

enum TerminalTheme: String, CaseIterable, Identifiable {
    case midnight, graphite, dark, solarized, light
    var id: String { rawValue }
    var title: String {
        switch self {
        case .midnight: return "Midnight"
        case .graphite: return "Graphite"
        case .dark: return "Black"
        case .solarized: return "Solarized"
        case .light: return "Light"
        }
    }
    /// (background, foreground, caret) as hex
    var colors: (bg: UInt32, fg: UInt32, caret: UInt32) {
        switch self {
        case .midnight:  return (0x10131C, 0xE4E8F1, 0x5B8CFF)
        case .graphite:  return (0x1B1C20, 0xDADCE0, 0x3DD68C)
        case .dark:      return (0x000000, 0xDDDDDD, 0xFFFFFF)
        case .solarized: return (0x002B36, 0x93A1A1, 0x268BD2)
        case .light:     return (0xFAFAFA, 0x222222, 0x0060DF)
        }
    }
    var isLight: Bool { self == .light }
}
