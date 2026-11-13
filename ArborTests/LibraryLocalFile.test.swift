import Foundation
import XCTest
@testable import Arbor

final class LibraryLocalFileTests: XCTestCase {
    func testSuccessfulCopyCreatesDurableFileAndMapping() throws {
        let testID = UUID().uuidString
        let originalURL = "https://example.com/\(testID)"
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(testID).mp3")
        let audioData = Data("audio".utf8)
        try audioData.write(to: sourceURL)

        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            deleteLocalAudioFile(originalUrl: originalURL)
        }

        let savedPath = try ensureLocalAudioFile(
            originalUrl: originalURL,
            sourcePath: sourceURL.path,
            title: "Test Song \(testID)",
            artists: ["Test Artist"]
        )

        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: savedPath)), audioData)
        XCTAssertEqual(getLocalAudioFilePath(originalUrl: originalURL), savedPath)
    }

    func testFailedCopyDoesNotCreateMapping() {
        let originalURL = "https://example.com/\(UUID().uuidString)"
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .path

        defer { deleteLocalAudioFile(originalUrl: originalURL) }

        XCTAssertThrowsError(
            try ensureLocalAudioFile(
                originalUrl: originalURL,
                sourcePath: missingPath,
                title: "Missing Song",
                artists: ["Test Artist"]
            )
        )
        XCTAssertNil(getLibraryLocalFile(originalUrl: originalURL))
    }
}
