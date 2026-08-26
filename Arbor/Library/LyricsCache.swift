import Foundation

enum LyricsSource: String, Codable {
    case youtube = "YouTube"
    case genius = "Genius"
}

struct LyricsPayload: Codable, Equatable {
    let timed: Bool
    let lines: [LyricsLine]
    let source: LyricsSource?

    init(timed: Bool, lines: [LyricsLine], source: LyricsSource? = nil) {
        self.timed = timed
        self.lines = lines
        self.source = source
    }
}

struct LyricsLine: Codable, Equatable {
    let startMs: Int?
    let text: String

    enum CodingKeys: String, CodingKey {
        case startMs = "start_ms"
        case text
    }
}

enum LyricsFetchResult {
    case loaded(LyricsPayload)
    case empty
    case failed
}

struct LyricsTranslationPayload: Codable, Equatable {
    let translations: [String]
    let romanizations: [String]
}

private struct LyricsTranslationDecodedPayload: Codable, Equatable {
    let translations: [String]
    let romanizations: [String?]
}

private struct LyricsTranslationResponse: Decodable {
    let result: String?
    let log: String
}

enum LyricsTranslationResult {
    case loaded(LyricsTranslationPayload)
    case failed(log: String?)
}

final class LyricsCache {
    static let shared = LyricsCache()
    private init() {}

    private static let directoryName = "LyricsCache"
    private let lyricsCachePrefix = ["lyrics"]
    private let translationCachePrefix = ["lyricsTranslation"]

    static func cacheDirectoryPath() -> String? {
        shared.directoryURL?.path
    }

    static func youtubeVideoId(from urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }

        let host = url.host?.lowercased() ?? ""

        // https://youtu.be/e0Y39QnwRvY
        if host.contains("youtu.be") {
            return url.pathComponents.dropFirst().first
        }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems,
           let youtubeVideoId = queryItems.first(where: { $0.name == "v" })?.value {
            return youtubeVideoId
        }

        // https://www.youtube.com/watch?v=e0Y39QnwRvY
        if host.contains("youtube.com"),
           let shortsIndex = url.pathComponents.firstIndex(of: "shorts"),
           url.pathComponents.count > shortsIndex + 1 {
            return url.pathComponents[shortsIndex + 1]
        }

        return nil
    }

    static func activeLyricIndex(for payload: LyricsPayload, currentTimeMs: Int) -> Int? {
        guard payload.timed, !payload.lines.isEmpty else { return nil }

        var activeIndex: Int?
        for (index, line) in payload.lines.enumerated() {
            guard let startMs = line.startMs else { continue }
            if startMs <= currentTimeMs {
                activeIndex = index
            } else {
                break
            }
        }
        return activeIndex
    }

    func fetchLyrics(
        originalUrl: String,
        title: String,
        artists: [String],
        completion: @escaping (LyricsFetchResult) -> Void
    ) {
        if let cached = getFromMemory(originalURL: originalUrl) {
            completion(.loaded(cached))
            return
        }

        if let data = loadFromDisk(originalURL: originalUrl) {
            if let payload = try? JSONDecoder().decode(LyricsPayload.self, from: data) {
                setInMemory(payload, originalURL: originalUrl)
                completion(.loaded(payload))
                return
            } else {
                removeFromDisk(originalURL: originalUrl)
            }
        }

        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let primaryArtist = artists.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        func fetchFromGenius() {
            guard !title.isEmpty, !primaryArtist.isEmpty else {
                debugPrint("LyricsCache: skipping Genius lookup (missing artist/query) for \(originalUrl)")
                completion(.empty)
                return
            }

            debugPrint("LyricsCache: fetching Genius lyrics for \(originalUrl) with title '\(title)' by artist '\(primaryArtist)'")
            
            let escapedTitle = escapeForPythonString(title)
            let escapedPrimaryArtist = escapeForPythonString(primaryArtist)
            let geniusCode = """
from arbor import get_lyrics_from_genius
result = get_lyrics_from_genius('\(escapedTitle)', '\(escapedPrimaryArtist)')
"""

            pythonExecAndGetStringAsync(
                geniusCode.trimmingCharacters(in: .whitespacesAndNewlines),
                "result"
            ) { result in
                guard let output = result, !output.isEmpty else {
                    debugPrint("LyricsCache: Genius returned empty result for \(originalUrl)")
                    completion(.empty)
                    return
                }

                guard let data = output.data(using: .utf8),
                      let payload = try? JSONDecoder().decode(LyricsPayload.self, from: data) else {
                    debugPrint("LyricsCache: failed to decode Genius lyrics for \(originalUrl)")
                    completion(.failed)
                    return
                }

                guard !payload.lines.isEmpty else {
                    debugPrint("LyricsCache: Genius returned no lyric lines for \(originalUrl)")
                    completion(.empty)
                    return
                }

                let attributedPayload = LyricsPayload(
                    timed: payload.timed,
                    lines: payload.lines,
                    source: .genius
                )
                if let encoded = try? JSONEncoder().encode(attributedPayload) {
                    self.saveToDisk(data: encoded, originalURL: originalUrl)
                }
                self.setInMemory(attributedPayload, originalURL: originalUrl)
                completion(.loaded(attributedPayload))
            }
        }

        func fetchFromYouTube(youtubeVideoId: String) {
            let escaped = escapeForPythonString(youtubeVideoId)
            let code = """
from arbor.lyrics import get_lyrics_from_youtube
result = get_lyrics_from_youtube('\(escaped)')
"""

            pythonExecAndGetStringAsync(
                code.trimmingCharacters(in: .whitespacesAndNewlines),
                "result"
            ) { result in
                guard let output = result, !output.isEmpty else {
                    debugPrint("LyricsCache: YouTube returned empty result for \(originalUrl); falling back to Genius")
                    fetchFromGenius()
                    return
                }

                guard let data = output.data(using: .utf8),
                      let payload = try? JSONDecoder().decode(LyricsPayload.self, from: data) else {
                    debugPrint("LyricsCache: failed to decode YouTube lyrics for \(originalUrl); falling back to Genius")
                    fetchFromGenius()
                    return
                }

                guard !payload.lines.isEmpty else {
                    debugPrint("LyricsCache: YouTube returned no lyric lines for \(originalUrl); falling back to Genius")
                    fetchFromGenius()
                    return
                }

            let attributedPayload = LyricsPayload(
                timed: payload.timed,
                lines: payload.lines,
                source: .youtube
            )
            if let encoded = try? JSONEncoder().encode(attributedPayload) {
                self.saveToDisk(data: encoded, originalURL: originalUrl)
            }
            self.setInMemory(attributedPayload, originalURL: originalUrl)
            completion(.loaded(attributedPayload))
        }
    }

        let youtubeVideoId = Self.youtubeVideoId(from: originalUrl)
        guard let youtubeVideoId else {
            debugPrint("LyricsCache: non-YouTube URL; trying Genius for \(originalUrl)")
            fetchFromGenius()
            return
        }
        fetchFromYouTube(youtubeVideoId: youtubeVideoId)
    }

    func translateLyrics(
        originalUrl: String,
        payload: LyricsPayload,
        completion: @escaping (LyricsTranslationResult) -> Void
    ) {
        guard let youtubeVideoId = Self.youtubeVideoId(from: originalUrl) else {
            completion(.failed(log: nil))
            return
        }
        translateLyrics(youtubeVideoId: youtubeVideoId, payload: payload, completion: completion)
    }

    func translateLyrics(
        youtubeVideoId: String,
        payload: LyricsPayload,
        completion: @escaping (LyricsTranslationResult) -> Void
    ) {
        if let cached = getTranslationFromMemory(youtubeVideoId: youtubeVideoId) {
            completion(.loaded(cached))
            return
        }

        if let data = loadTranslationFromDisk(youtubeVideoId: youtubeVideoId) {
            if let payload = try? JSONDecoder().decode(LyricsTranslationPayload.self, from: data) {
                setTranslationInMemory(payload, youtubeVideoId: youtubeVideoId)
                completion(.loaded(payload))
                return
            } else {
                removeTranslationFromDisk(youtubeVideoId: youtubeVideoId)
            }
        }

        let texts = payload.lines.map { $0.text }
        guard let data = try? JSONSerialization.data(withJSONObject: texts, options: []),
              let jsonString = String(data: data, encoding: .utf8) else {
            completion(.failed(log: nil))
            return
        }

        let escaped = escapeForPythonString(jsonString)
        let code = """
import json
import sys
from arbor import capture_logs
from arbor.translate import translate
payload = json.loads('\(escaped)')
translation, log = capture_logs(translate, payload)
if translation is None and log:
    print(log, file=sys.stderr, end="")
result = json.dumps({"result": translation, "log": log})
"""

        pythonExecAndGetStringAsync(
            code.trimmingCharacters(in: .whitespacesAndNewlines),
            "result"
        ) { result in
            guard let output = result, !output.isEmpty else {
                completion(.failed(log: nil))
                return
            }

            guard let responseData = output.data(using: .utf8),
                  let response = try? JSONDecoder().decode(LyricsTranslationResponse.self, from: responseData) else {
                completion(.failed(log: output))
                return
            }

            let capturedLog = response.log.trimmingCharacters(in: .whitespacesAndNewlines)
            let failureLog = capturedLog.isEmpty ? nil : response.log

            guard let translation = response.result, !translation.isEmpty else {
                completion(.failed(log: failureLog))
                return
            }

            guard let translationData = translation.data(using: .utf8),
                  let parsed = try? JSONDecoder().decode(LyricsTranslationDecodedPayload.self, from: translationData),
                  parsed.romanizations.count == texts.count,
                  parsed.translations.count == texts.count else {
                completion(.failed(log: failureLog ?? translation))
                return
            }

            let romanizedLines = parsed.romanizations.enumerated().map { index, value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? texts[index] : trimmed
            }
            let sanitizedPayload = LyricsTranslationPayload(
                translations: parsed.translations,
                romanizations: romanizedLines
            )
            if let encoded = try? JSONEncoder().encode(sanitizedPayload) {
                self.saveTranslationToDisk(data: encoded, youtubeVideoId: youtubeVideoId)
            }
            self.setTranslationInMemory(sanitizedPayload, youtubeVideoId: youtubeVideoId)
            completion(.loaded(sanitizedPayload))
        }
    }

    func clearAll() {
        clearMemory()
        clearDisk()
    }

    func clearLyrics(originalURL: String) {
        QueryCache.shared.invalidateQueries(lyricsCachePrefix + [originalURL])
        removeFromDisk(originalURL: originalURL)

        if let youtubeVideoId = Self.youtubeVideoId(from: originalURL) {
            QueryCache.shared.invalidateQueries(translationCachePrefix + [youtubeVideoId])
            removeTranslationFromDisk(youtubeVideoId: youtubeVideoId)
        }
    }

    private func getFromMemory(originalURL: String) -> LyricsPayload? {
        QueryCache.shared.get(for: lyricsCachePrefix + [originalURL], as: LyricsPayload.self)
    }

    private func setInMemory(_ payload: LyricsPayload, originalURL: String) {
        QueryCache.shared.set(payload, for: lyricsCachePrefix + [originalURL])
    }

    private func getTranslationFromMemory(youtubeVideoId: String) -> LyricsTranslationPayload? {
        QueryCache.shared.get(
            for: translationCachePrefix + [youtubeVideoId],
            as: LyricsTranslationPayload.self
        )
    }

    private func setTranslationInMemory(_ payload: LyricsTranslationPayload, youtubeVideoId: String) {
        QueryCache.shared.set(payload, for: translationCachePrefix + [youtubeVideoId])
    }

    private func clearMemory() {
        QueryCache.shared.invalidateQueries(lyricsCachePrefix)
        QueryCache.shared.invalidateQueries(translationCachePrefix)
    }

    private var directoryURL: URL? {
        let tmpPath = NSTemporaryDirectory()
        guard !tmpPath.isEmpty else { return nil }
        return URL(fileURLWithPath: tmpPath, isDirectory: true)
            .appendingPathComponent(Self.directoryName, isDirectory: true)
    }

    private func loadFromDisk(originalURL: String) -> Data? {
        guard let url = fileURL(for: originalURL) else { return nil }
        return try? Data(contentsOf: url)
    }

    private func saveToDisk(data: Data, originalURL: String) {
        guard let url = fileURL(for: originalURL) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    private func removeFromDisk(originalURL: String) {
        guard let url = fileURL(for: originalURL) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func loadTranslationFromDisk(youtubeVideoId: String) -> Data? {
        guard let url = translationFileURL(for: youtubeVideoId) else { return nil }
        return try? Data(contentsOf: url)
    }

    private func saveTranslationToDisk(data: Data, youtubeVideoId: String) {
        guard let url = translationFileURL(for: youtubeVideoId) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    private func removeTranslationFromDisk(youtubeVideoId: String) {
        guard let url = translationFileURL(for: youtubeVideoId) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func clearDisk() {
        guard let dirURL = directoryURL else { return }
        guard FileManager.default.fileExists(atPath: dirURL.path) else { return }
        let contents = try? FileManager.default.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: nil
        )
        contents?.forEach { item in
            try? FileManager.default.removeItem(at: item)
        }
    }

    private func fileURL(for originalURL: String) -> URL? {
        guard let dirURL = ensureDirectory() else { return nil }
        let filename = sanitizedFileName(originalURL)
        return dirURL.appendingPathComponent(filename).appendingPathExtension("json")
    }

    private func translationFileURL(for youtubeVideoId: String) -> URL? {
        guard let dirURL = ensureDirectory() else { return nil }
        let filename = sanitizedFileName(youtubeVideoId) + ".translations"
        return dirURL.appendingPathComponent(filename).appendingPathExtension("json")
    }

    private func ensureDirectory() -> URL? {
        guard let dirURL = directoryURL else { return nil }
        if !FileManager.default.fileExists(atPath: dirURL.path) {
            try? FileManager.default.createDirectory(
                at: dirURL,
                withIntermediateDirectories: true
            )
        }
        return dirURL
    }

    private func sanitizedFileName(_ value: String) -> String {
        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_."
        )
        var result = ""
        for scalar in value.unicodeScalars {
            if allowed.contains(scalar) {
                result.unicodeScalars.append(scalar)
            } else {
                result.append("_")
            }
        }
        return result.isEmpty ? "lyrics" : result
    }

    private func escapeForPythonString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
    }
}
