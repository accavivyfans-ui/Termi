import Foundation
import SwiftUI

@MainActor
final class SessionManager: ObservableObject {
    @Published var sessions: [SSHSession] = []
    /// 현재 전체화면으로 보고 있는 세션
    @Published var active: SSHSession?

    func open(host: SSHHost, password: String) -> SSHSession {
        let s = SSHSession(host: host, password: password)
        sessions.append(s)
        active = s
        return s
    }

    func close(_ session: SSHSession) {
        session.disconnect()
        sessions.removeAll { $0.id == session.id }
        if active?.id == session.id { active = nil }
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
    static let accentGreen = Color(hex: 0x21D07A)
    static let panel = Color(hex: 0x1D2136)
    static let appBackground = Color(hex: 0x141729)
}
