//
//  AudioDownloader.swift
//  Arbor
//
//  Shared helper for downloading audio via the embedded Python runtime.
//

import Foundation

enum DownloadError: Error {
    case invalidSelection
    case emptyResult(log: String?)
    case invalidResponse(log: String?)
    case pythonFailed(log: String)
}

struct AudioDownloader {
    private struct DownloadResponse: Decodable {
        let result: String?
        let log: String
    }

    static func download(
        from url: String,
        searchResult: SearchResult? = nil,
        completion: @escaping (Result<DownloadMeta, Error>) -> Void
    ) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.failure(DownloadError.invalidSelection))
            return
        }

        if let existingPath = getLocalAudioFilePath(originalUrl: trimmed) {
            if let result = searchResult {
                let meta = DownloadMeta(
                    path: existingPath,
                    original_url: trimmed,
                    title: result.title,
                    artists: result.artists,
                    thumbnail_url: result.thumbnailURL,
                    thumbnail_width: result.thumbnailWidth,
                    thumbnail_height: result.thumbnailHeight,
                    thumbnail_is_square: result.thumbnailIsSquare
                )
                
                completion(.success(meta))
                return
            }
            
            deleteLocalAudioFile(originalUrl: trimmed)
        }

        // Escape backslashes and single quotes for safe embedding in Python string literal
        let escaped = trimmed
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")

        let code = """
import json
from arbor import capture_logs, download
result, log = capture_logs(download, '\(escaped)')
result = json.dumps({"result": result, "log": log})
"""

        pythonExecAndGetStringAsync(
            code.trimmingCharacters(in: .whitespacesAndNewlines),
            "result"
        ) { result in
            guard let output = result, !output.isEmpty else {
                completion(.failure(DownloadError.emptyResult(log: nil)))
                return
            }

            guard let data = output.data(using: .utf8),
                  let response = try? JSONDecoder().decode(DownloadResponse.self, from: data) else {
                completion(.failure(DownloadError.invalidResponse(log: output)))
                return
            }

            guard let resultJSON = response.result, !resultJSON.isEmpty else {
                completion(.failure(DownloadError.pythonFailed(log: response.log)))
                return
            }

            guard let resultData = resultJSON.data(using: .utf8),
                  let meta = try? JSONDecoder().decode(DownloadMeta.self, from: resultData) else {
                completion(.failure(DownloadError.invalidResponse(log: response.log)))
                return
            }

            completion(.success(meta))
        }
    }
}
