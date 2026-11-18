import Foundation
import SwiftUI

@MainActor
final class SessionManager: ObservableObject {
    @Published var sessions: [SSHSession] = []
    /// 현재 전체화면으로 보고 있는 세션
    @Published var active: SSHSession?

    func open(host: SSHHost, credential: SSHCredential) -> SSHSession {
        let s = SSHSession(host: host, credential: credential)
        sessions.append(s)
        active = s
        return s
    }

    func close(_ session: SSHSession) {
        session.disconnect()
        let idx = sessions.firstIndex { $0.id == session.id }
        sessions.removeAll { $0.id == session.id }
        if active?.id == session.id {
            if let idx, !sessions.isEmpty {
                active = sessions[min(idx, sessions.count - 1)]
            } else {
                active = nil
            }
        }
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

    // Termi 팔레트
    static let appBackground = Color(hex: 0x0E1016)
    static let panel = Color(hex: 0x171A22)
    static let panelRaised = Color(hex: 0x1F232D)
    static let hairline = Color.white.opacity(0.07)
    static let accent = Color(hex: 0x5B8CFF)
    static let accentGreen = Color(hex: 0x3DD68C)
    static let textDim = Color(hex: 0x8A91A3)

    /// 호스트 아이콘용 색 (이름 기반으로 고정)
    static func tag(for seed: String) -> Color {
        let palette: [UInt32] = [0x5B8CFF, 0x3DD68C, 0xF5A524, 0xF76E6E, 0xA77BFF, 0x2BC4D9, 0xFF8AC5]
        let h = seed.unicodeScalars.reduce(UInt32(7)) { ($0 &* 31) &+ $1.value }
        return Color(hex: palette[Int(h % UInt32(palette.count))])
    }
}
