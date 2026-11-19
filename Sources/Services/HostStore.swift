import Foundation
import SwiftUI

@MainActor
final class HostStore: ObservableObject {
    @Published var hosts: [SSHHost] = [] { didSet { save() } }

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("hosts.json")
    }()

    init() {
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([SSHHost].self, from: data) {
            hosts = decoded
        }
        BuiltInDefaults.seedHost(into: &hosts)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(hosts) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func password(for host: SSHHost) -> String? { Keychain.get("host-\(host.id.uuidString)") }
    func setPassword(_ pw: String, for host: SSHHost) { Keychain.set(pw, for: "host-\(host.id.uuidString)") }

    func upsert(_ host: SSHHost, password: String?) {
        if let i = hosts.firstIndex(where: { $0.id == host.id }) { hosts[i] = host } else { hosts.append(host) }
        if let password { setPassword(password, for: host) }
    }

    func delete(_ host: SSHHost) {
        hosts.removeAll { $0.id == host.id }
        Keychain.delete("host-\(host.id.uuidString)")
    }

    func markConnected(_ host: SSHHost) {
        if let i = hosts.firstIndex(where: { $0.id == host.id }) { hosts[i].lastConnected = Date() }
    }

    var groups: [String] {
        Array(Set(hosts.map { $0.group.trimmingCharacters(in: .whitespaces) })).sorted()
    }
}

/// known_hosts 저장소 (TOFU: 처음 본 서버는 사용자 확인 후 저장, 이후 키가 바뀌면 경고)
enum KnownHosts {
    private static let key = "knownHosts"
    static func get(_ id: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: String])?[id]
    }
    static func set(_ id: String, _ value: String?) {
        var d = (UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:]
        d[id] = value
        UserDefaults.standard.set(d, forKey: key)
    }
    static func all() -> [String: String] {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:]
    }
    static func removeAll() { UserDefaults.standard.removeObject(forKey: key) }
}
