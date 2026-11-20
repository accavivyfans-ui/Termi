import UIKit
import UniformTypeIdentifiers

/// SwiftUI `.fileImporter`는 시트 안의 시트(호스트 편집 → 키 추가)에서 열리지 않거나
/// 선택 후 콜백이 오지 않는 경우가 있어, UIKit 문서 선택기를 최상단 화면에서 직접 띄운다.
final class DocumentPicker: NSObject, UIDocumentPickerDelegate {
    private static var current: DocumentPicker?
    private let completion: (Result<Data, Error>, URL?) -> Void

    private init(completion: @escaping (Result<Data, Error>, URL?) -> Void) {
        self.completion = completion
    }

    static func present(completion: @escaping (Result<Data, Error>, URL?) -> Void) {
        guard let top = topViewController() else { return }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = false
        let handler = DocumentPicker(completion: completion)
        picker.delegate = handler
        current = handler
        top.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        defer { Self.current = nil }
        guard let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            completion(.success(data), url)
        } catch {
            completion(.failure(error), url)
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        Self.current = nil
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
