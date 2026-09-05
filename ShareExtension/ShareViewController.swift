import UIKit
import UniformTypeIdentifiers

private enum ShareImportConstants {
    static let appGroupID = "group.com.armaana.arbor"
    static let pendingShareKey = "pending_share_payload"
    static let openURL = URL(string: "arbor://import")!
}

private struct PendingSharePayload: Codable {
    let url: String
    let timestamp: TimeInterval
}

class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        extractFirstURL { [weak self] url in
            guard let self = self, let url else {
                self?.close()
                return
            }

            self.persistSharedURL(url)
            self.openHostApp()
        }
    }
    
    /// Close the Share Extension
    func close() {
        self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func extractFirstURL(completion: @escaping (URL?) -> Void) {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            completion(nil)
            return
        }

        let providers = items.compactMap { $0.attachments }.flatMap { $0 }
        guard !providers.isEmpty else {
            completion(nil)
            return
        }

        let group = DispatchGroup()
        var foundURL: URL?

        for provider in providers {
            if foundURL != nil { break }

            group.enter()
            loadURL(from: provider) { url in
                if let url, foundURL == nil {
                    foundURL = url
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(foundURL)
        }
    }

    private func loadURL(from provider: NSItemProvider, completion: @escaping (URL?) -> Void) {
        if provider.canLoadObject(ofClass: URL.self) {
            provider.loadObject(ofClass: URL.self) { object, _ in
                completion(self.validateURL(object as? URL))
            }
            return
        }

        if provider.canLoadObject(ofClass: NSString.self) {
            provider.loadObject(ofClass: NSString.self) { object, _ in
                let text = (object as? NSString).map { String($0) }
                let url = text.flatMap { self.urlFromText($0) }
                completion(self.validateURL(url))
            }
            return
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.url.identifier) { data, _ in
                let url = data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                completion(self.validateURL(url))
            }
            return
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
                let url = data.flatMap { String(data: $0, encoding: .utf8) }.flatMap { self.urlFromText($0) }
                completion(self.validateURL(url))
            }
            return
        }

        completion(nil)
    }

    private func urlFromText(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    private func validateURL(_ url: URL?) -> URL? {
        guard let url else { return nil }
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    private func persistSharedURL(_ url: URL) {
        guard let defaults = UserDefaults(suiteName: ShareImportConstants.appGroupID) else { return }
        let payload = PendingSharePayload(
            url: url.absoluteString,
            timestamp: Date().timeIntervalSince1970
        )

        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: ShareImportConstants.pendingShareKey)
        }
    }

    private func openHostApp() {
        extensionContext?.open(ShareImportConstants.openURL, completionHandler: { [weak self] _ in
            self?.close()
        })
    }
}
