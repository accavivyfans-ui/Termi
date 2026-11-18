import Foundation
import AVFoundation
import UIKit

/// 앱이 백그라운드로 가도 SSH 세션이 끊기지 않게 유지.
/// 세션이 열려 있는 동안만 무음 오디오를 재생(다른 앱 음악과 섞임)해서 iOS가 앱을 정지시키지 않게 한다.
@MainActor
final class BackgroundKeeper {
    static let shared = BackgroundKeeper()

    private var player: AVAudioPlayer?
    private var task: UIBackgroundTaskIdentifier = .invalid
    var hasSessions: () -> Bool = { false }

    static var enabled: Bool {
        UserDefaults.standard.object(forKey: "keepAlive") as? Bool ?? true
    }

    private init() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { BackgroundKeeper.shared.enterBackground() }
        }
        nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { BackgroundKeeper.shared.enterForeground() }
        }
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { note in
            // 전화 등으로 끊겼다가 끝나면 다시 재생
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            MainActor.assumeIsolated {
                if UIApplication.shared.applicationState == .background { BackgroundKeeper.shared.player?.play() }
            }
        }
    }

    func start() {} // 싱글톤 초기화용

    private func enterBackground() {
        guard hasSessions() else { return }
        task = UIApplication.shared.beginBackgroundTask { [weak self] in
            guard let self else { return }
            UIApplication.shared.endBackgroundTask(self.task)
            self.task = .invalid
        }
        guard Self.enabled else { return }
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playback, options: [.mixWithOthers])
            try s.setActive(true)
            if player == nil {
                player = try AVAudioPlayer(data: Self.silentWAV())
                player?.numberOfLoops = -1
                player?.volume = 0
            }
            player?.play()
        } catch {
            // 실패하면 기본 30초 백그라운드 작업만 유지
        }
    }

    private func enterForeground() {
        player?.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        if task != .invalid {
            UIApplication.shared.endBackgroundTask(task)
            task = .invalid
        }
    }

    /// 1초짜리 무음 16-bit mono WAV
    private static func silentWAV() -> Data {
        let rate: UInt32 = 8000
        let samples = Data(count: Int(rate) * 2)
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + UInt32(samples.count))
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(rate); u32(rate * 2); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(UInt32(samples.count))
        d.append(samples)
        return d
    }
}
