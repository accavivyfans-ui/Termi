import Foundation

/// 첫 실행 때 기본으로 넣어 두는 호스트 / 키.
/// 한 번 넣은 뒤 사용자가 지우면 다시 넣지 않는다 (UserDefaults 플래그).
enum BuiltInDefaults {
    static let keyID = UUID(uuidString: "6E1A3C2B-0F4D-4C59-9A0E-7D2B1F3A5C01")!
    static let hostID = UUID(uuidString: "6E1A3C2B-0F4D-4C59-9A0E-7D2B1F3A5C02")!

    static let publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG+jWfLzK84pYqBOUTwgz6mPSYKCC08UQde6hb1F79ni phone"

    static let host = SSHHost(
        id: hostID,
        label: "기본 서버",
        hostname: "130.94.30.97",
        port: 22,
        username: "administrator",
        auth: .key,
        keyID: keyID
    )

    private static let keySeededFlag = "defaults.keySeeded.v1"
    private static let hostSeededFlag = "defaults.hostSeeded.v2"

    static func seedKey(into keys: inout [SSHKeyItem]) {
        guard !UserDefaults.standard.bool(forKey: keySeededFlag) else { return }
        UserDefaults.standard.set(true, forKey: keySeededFlag)
        guard let pub = try? SSHWire.parsePublicKey(publicKey),
              !keys.contains(where: { $0.fingerprint == pub.fingerprint }) else { return }
        keys.append(SSHKeyItem(
            id: keyID,
            name: "phone",
            type: pub.type,
            publicKey: pub.line,
            fingerprint: pub.fingerprint,
            publicOnly: true
        ))
    }

    static func seedHost(into hosts: inout [SSHHost]) {
        guard !UserDefaults.standard.bool(forKey: hostSeededFlag) else { return }
        UserDefaults.standard.set(true, forKey: hostSeededFlag)
        guard !hosts.contains(where: { $0.hostname == host.hostname }) else { return }
        hosts.insert(host, at: 0)
    }
}
