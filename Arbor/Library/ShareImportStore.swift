import Foundation
import SwiftData

private enum ShareImportConstants {
    static let appGroupID = "group.com.armaana.arbor"
    static let pendingShareKey = "pending_share_payload"
    static let expectedScheme = "arbor"
    static let expectedHost = "import"
}

private struct PendingSharePayload: Codable {
    let url: String
    let timestamp: TimeInterval
}

enum ShareImportStore {
    static func handleOpenURL(
        _ url: URL,
        modelContext: ModelContext,
        player: PlayerCoordinator
    ) {
        guard url.scheme?.lowercased() == ShareImportConstants.expectedScheme,
              url.host?.lowercased() == ShareImportConstants.expectedHost else {
            return
        }

        guard let payload = loadAndClearPendingShare() else { return }
        let trimmed = payload.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        AudioDownloader.download(from: trimmed) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let meta):
                    let item = LibraryItem(meta: meta)
                    modelContext.insert(item)
                    player.startPlayback(libraryItem: item, filePath: meta.path)

                case .failure(let error):
                    debugPrint("Share import download failed:", error)
                }
            }
        }
    }

    private static func loadAndClearPendingShare() -> PendingSharePayload? {
        guard let defaults = UserDefaults(suiteName: ShareImportConstants.appGroupID),
              let data = defaults.data(forKey: ShareImportConstants.pendingShareKey),
              let payload = try? JSONDecoder().decode(PendingSharePayload.self, from: data) else {
            return nil
        }

        defaults.removeObject(forKey: ShareImportConstants.pendingShareKey)
        return payload
    }
}
