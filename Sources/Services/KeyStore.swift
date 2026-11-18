import Foundation
import CryptoKit
import Citadel

enum KeyError: LocalizedError {
    case notOpenSSH, unsupported(String), passphrase, missing, corrupt

    var errorDescription: String? {
        switch self {
        case .notOpenSSH:
            return "OpenSSH 개인키 형식이 아닙니다. (-----BEGIN OPENSSH PRIVATE KEY-----)\n.pub 파일은 공개키라서 로그인에 쓸 수 없어요. 짝이 되는 개인키(id_ed25519 등)를 가져오세요.\n옛 RSA 형식이면 PC에서 `ssh-keygen -p -f 키파일` 로 변환하세요."
        case .unsupported(let t): return "지원하지 않는 키 형식: \(t) (ED25519 / RSA 지원)"
        case .passphrase: return "암호(passphrase)가 필요하거나 틀렸습니다."
        case .missing: return "이 키의 개인키를 찾을 수 없습니다. 키를 다시 가져오세요."
        case .corrupt: return "키 파일이 손상되었습니다."
        }
    }
}

@MainActor
final class KeyStore: ObservableObject {
    @Published var keys: [SSHKeyItem] = [] { didSet { save() } }

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("keys.json")
    }()

    init() {
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([SSHKeyItem].self, from: data) {
            keys = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(keys) { try? data.write(to: url, options: .atomic) }
    }

    func key(_ id: UUID?) -> SSHKeyItem? {
        guard let id else { return nil }
        return keys.first { $0.id == id }
    }

    // MARK: - Create

    @discardableResult
    func generateEd25519(name: String) -> SSHKeyItem {
        let priv = Curve25519.Signing.PrivateKey()
        let blob = SSHWire.string("ssh-ed25519") + SSHWire.string(priv.publicKey.rawRepresentation)
        let comment = name.replacingOccurrences(of: " ", with: "-")
        let item = SSHKeyItem(
            name: name,
            type: "ssh-ed25519",
            publicKey: "ssh-ed25519 \(blob.base64EncodedString()) \(comment)@termi",
            fingerprint: SSHWire.fingerprint(blob)
        )
        Keychain.set("raw-ed25519:" + priv.rawRepresentation.base64EncodedString(), for: "key-\(item.id.uuidString)")
        keys.append(item)
        return item
    }

    /// OpenSSH 개인키 텍스트 가져오기. 파싱/암호까지 검증한 뒤 저장.
    @discardableResult
    func importPrivateKey(_ text: String, name: String, passphrase: String) throws -> SSHKeyItem {
        let pem = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pem.hasPrefix("-----BEGIN OPENSSH PRIVATE KEY-----") else { throw KeyError.notOpenSSH }
        let (type, blob) = try SSHWire.publicBlob(fromOpenSSH: pem)
        // 실제로 열리는지 확인
        _ = try Self.authMethod(pem: pem, passphrase: passphrase, username: "check")
        let item = SSHKeyItem(
            name: name.isEmpty ? type : name,
            type: type,
            publicKey: "\(type) \(blob.base64EncodedString()) \(name.isEmpty ? "imported" : name.replacingOccurrences(of: " ", with: "-"))",
            fingerprint: SSHWire.fingerprint(blob)
        )
        Keychain.set(pem, for: "key-\(item.id.uuidString)")
        if !passphrase.isEmpty { Keychain.set(passphrase, for: "keypass-\(item.id.uuidString)") }
        keys.append(item)
        return item
    }

    func delete(_ item: SSHKeyItem) {
        keys.removeAll { $0.id == item.id }
        Keychain.delete("key-\(item.id.uuidString)")
        Keychain.delete("keypass-\(item.id.uuidString)")
    }

    func rename(_ item: SSHKeyItem, to name: String) {
        if let i = keys.firstIndex(where: { $0.id == item.id }) { keys[i].name = name }
    }

    // MARK: - Auth

    nonisolated static func authMethod(for item: SSHKeyItem, username: String) throws -> SSHAuthenticationMethod {
        guard let stored = Keychain.get("key-\(item.id.uuidString)") else { throw KeyError.missing }
        if stored.hasPrefix("raw-ed25519:") {
            guard let raw = Data(base64Encoded: String(stored.dropFirst("raw-ed25519:".count))) else { throw KeyError.corrupt }
            let priv = try Curve25519.Signing.PrivateKey(rawRepresentation: raw)
            return .ed25519(username: username, privateKey: priv)
        }
        return try authMethod(pem: stored, passphrase: Keychain.get("keypass-\(item.id.uuidString)") ?? "", username: username)
    }

    nonisolated static func authMethod(pem: String, passphrase: String, username: String) throws -> SSHAuthenticationMethod {
        let pass = passphrase.isEmpty ? nil : Data(passphrase.utf8)
        let type: SSHKeyType
        do { type = try SSHKeyDetection.detectPrivateKeyType(from: pem) } catch { throw KeyError.notOpenSSH }
        do {
            switch type {
            case .ed25519:
                return .ed25519(username: username, privateKey: try Curve25519.Signing.PrivateKey(sshEd25519: pem, decryptionKey: pass))
            case .rsa:
                return .rsa(username: username, privateKey: try Insecure.RSA.PrivateKey(sshRsa: pem, decryptionKey: pass))
            default:
                throw KeyError.unsupported(type.description)
            }
        } catch let e as KeyError {
            throw e
        } catch {
            throw KeyError.passphrase
        }
    }
}

/// SSH wire format 도우미
enum SSHWire {
    static func string(_ s: String) -> Data { string(Data(s.utf8)) }
    static func string(_ d: Data) -> Data {
        var len = UInt32(d.count).bigEndian
        return Data(bytes: &len, count: 4) + d
    }

    static func fingerprint(_ blob: Data) -> String {
        "SHA256:" + Data(SHA256.hash(data: blob)).base64EncodedString().replacingOccurrences(of: "=", with: "")
    }

    /// openssh-key-v1 파일 헤더에서 (암호화돼 있어도 평문인) 공개키 blob을 읽는다.
    static func publicBlob(fromOpenSSH pem: String) throws -> (String, Data) {
        let body = pem
            .replacingOccurrences(of: "-----BEGIN OPENSSH PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END OPENSSH PRIVATE KEY-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines).joined()
        guard let data = Data(base64Encoded: body) else { throw KeyError.corrupt }
        let bytes = [UInt8](data)
        let magic = Array("openssh-key-v1\0".utf8)
        guard bytes.count > magic.count, Array(bytes[0..<magic.count]) == magic else { throw KeyError.notOpenSSH }
        var off = magic.count

        func readU32() throws -> Int {
            guard off + 4 <= bytes.count else { throw KeyError.corrupt }
            let v = bytes[off..<off + 4].reduce(0) { ($0 << 8) | Int($1) }
            off += 4
            return v
        }
        func readString() throws -> [UInt8] {
            let n = try readU32()
            guard n >= 0, off + n <= bytes.count else { throw KeyError.corrupt }
            defer { off += n }
            return Array(bytes[off..<off + n])
        }

        _ = try readString() // cipher
        _ = try readString() // kdf
        _ = try readString() // kdf options
        _ = try readU32()    // number of keys
        let blob = try readString()
        // blob 안의 첫 string = 키 타입
        guard blob.count >= 4 else { throw KeyError.corrupt }
        let tlen = blob[0..<4].reduce(0) { ($0 << 8) | Int($1) }
        guard 4 + tlen <= blob.count, let type = String(bytes: blob[4..<4 + tlen], encoding: .utf8) else { throw KeyError.corrupt }
        return (type, Data(blob))
    }
}
