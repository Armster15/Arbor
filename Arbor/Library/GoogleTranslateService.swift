import Combine
import Foundation
import WebKit

private let romanizationSelector = #"[jsname="toZopb"]"#
private let translationSelector = #"[jsname="W297wb"]"#

// https://webkit.org/blog/17333/webkit-features-in-safari-26-0/
private let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"

private let pageLoadTimeout: TimeInterval = 60
private let resultTimeout: TimeInterval = 30
private let pollInterval: TimeInterval = 0.25
private let payloadStableInterval: TimeInterval = 1
private let romanizationWaitTimeout: TimeInterval = 5

private enum TranslationLines {
    private static let markerPattern = try! NSRegularExpression(pattern: #"\[(\d+)\]"#)

    static func encode(_ lines: [String]) -> String {
        lines.enumerated().map { "[\($0.offset + 1)] \($0.element)" }.joined(separator: "\n")
    }

    static func decode(_ text: String, expectedLineCount: Int) -> [String]? {
        let text = text as NSString
        let markers = markerPattern.matches(in: text as String, range: NSRange(location: 0, length: text.length))
        guard markers.count == expectedLineCount else { return nil }

        var lines: [String] = []
        for (index, marker) in markers.enumerated() {
            guard text.substring(with: marker.range(at: 1)) == String(index + 1) else { return nil }
            let start = NSMaxRange(marker.range)
            let end = index + 1 < markers.count ? markers[index + 1].range.location : text.length
            let line = text.substring(with: NSRange(location: start, length: end - start))
            lines.append(line.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return lines
    }
}

enum GoogleTranslateResult {
    case loaded(translations: [String], romanizations: [String])
    case incomplete(translations: [String], romanizations: [String])
    case failed(String)
}

@MainActor
final class GoogleTranslateService: ObservableObject {
    static let shared = GoogleTranslateService()

    @Published private var activeRequest: GoogleTranslateRequest?

    var activeWebView: WKWebView? {
        activeRequest?.webView
    }

    private init() {}

    func translate(
        _ lines: [String],
        completion: @escaping (GoogleTranslateResult) -> Void
    ) {
        activeRequest?.cancel()

        let request = GoogleTranslateRequest(lines: lines, completion: completion)
        request.onFinish = { [weak self, weak request] in
            guard self?.activeRequest === request else { return }
            self?.activeRequest = nil
        }
        activeRequest = request
        request.start()
    }

    func cancel() {
        activeRequest?.cancel()
    }
}

@MainActor
private final class GoogleTranslateRequest: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private static let messageHandlerName = "translation"

    private let sourceLines: [String]
    private var completion: ((GoogleTranslateResult) -> Void)?
    private var stageTimeoutTimer: Timer?
    private(set) var webView: WKWebView!

    var onFinish: (() -> Void)?

    init(lines: [String], completion: @escaping (GoogleTranslateResult) -> Void) {
        sourceLines = lines
        self.completion = completion
        super.init()

        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.extractionScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.add(
            self,
            name: Self.messageHandlerName
        )

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = userAgent
        webView.navigationDelegate = self
    }

    func start() {
        guard let url = translationURL else {
            finish(.failed("Could not create the Google Translate URL."))
            return
        }

        startTimeout(
            after: pageLoadTimeout,
            result: .failed("Google Translate page load timed out.")
        )
        webView.load(URLRequest(url: url))
    }

    func cancel() {
        finish(.failed("Translation was cancelled."))
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        startTimeout(
            after: resultTimeout + pollInterval,
            result: .failed("Google Translate result timed out.")
        )
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: any Error
    ) {
        finish(.failed(error.localizedDescription))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        finish(.failed(error.localizedDescription))
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.messageHandlerName,
              let json = message.body as? String else {
            finish(.failed("Google Translate returned an invalid response."))
            return
        }

        debugPrint("GoogleTranslateService: received payload", json)

        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(WebTranslationPayload.self, from: data) else {
            finish(.failed("Google Translate returned an invalid response."))
            return
        }

        let translations = payload.translation.flatMap { TranslationLines.decode($0, expectedLineCount: sourceLines.count) }
        let romanizations = payload.romanization.flatMap { TranslationLines.decode($0, expectedLineCount: sourceLines.count) }

        // A result must retain every numbered line in order before we can align it with timestamps.
        if (payload.translation != nil && translations == nil)
            || (payload.romanization != nil && romanizations == nil) {
            finish(.failed("""
                Google Translate did not preserve the numbered lyric lines.
                Expected lines numbered 1 through \(sourceLines.count).

                <SOURCE_LINES>
                \(sourceLines.joined(separator: "\n"))
                </SOURCE_LINES>

                <TRANSLATED_LINES>
                \(payload.translation ?? "No translation returned")
                </TRANSLATED_LINES>

                <ROMANIZED_LINES>
                \(payload.romanization ?? "No romanization returned")
                </ROMANIZED_LINES>
                """))
            return
        }

        let missingTranslation = "No translations found "
            + "(translation=null, selector=\(translationSelector), "
            + "resultTimeout=\(Int(resultTimeout))s, sourceLineCount=\(sourceLines.count))"
        let missingRomanization = "No romanizations found "
            + "(romanization=null, selector=\(romanizationSelector), "
            + "romanizationWaitTimeout=\(Int(romanizationWaitTimeout))s, "
            + "sourceLineCount=\(sourceLines.count))"

        let translationLines = translations
            ?? Array(repeating: missingTranslation, count: sourceLines.count)
        let rawRomanizationLines = romanizations
            ?? Array(repeating: missingRomanization, count: sourceLines.count)
        let romanizationLines = rawRomanizationLines.enumerated().map { index, line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty else { return trimmed }
            return "No romanization found "
                + "(romanization=empty, selector=\(romanizationSelector), "
                + "lineIndex=\(index), sourceLineCount=\(sourceLines.count))"
        }

        if translations == nil || romanizations == nil {
            finish(.incomplete(translations: translationLines, romanizations: romanizationLines))
        } else {
            finish(.loaded(translations: translationLines, romanizations: romanizationLines))
        }
    }

    private var translationURL: URL? {
        // Intentionally avoid URLComponents to preserve how Google Translate writes this URL in a browser.
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.!~*'()"))
        let text = TranslationLines.encode(sourceLines)
        guard let encodedText = text.addingPercentEncoding(withAllowedCharacters: unreserved) else {
            return nil
        }
        return URL(
            string: "https://translate.google.com/?sl=auto&tl=en&text=\(encodedText)&op=translate"
        )
    }

    private func finish(_ result: GoogleTranslateResult) {
        guard let completion else { return }
        self.completion = nil

        stageTimeoutTimer?.invalidate()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Self.messageHandlerName
        )

        completion(result)
        onFinish?()
        onFinish = nil
    }

    private func startTimeout(
        after interval: TimeInterval,
        result: GoogleTranslateResult
    ) {
        stageTimeoutTimer?.invalidate()
        stageTimeoutTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.finish(result)
            }
        }
    }

    private static let extractionScript = """
(() => {
    function extractText(selector) {
        return Array.from(document.querySelectorAll(selector), element => element.textContent)
            .join(' ') || null
    }

    const romanizationSelector = '\(romanizationSelector)'
    const translationSelector = '\(translationSelector)'
    const resultTimeout = \(resultTimeout * 1_000)
    const payloadStableInterval = \(payloadStableInterval * 1_000)
    const romanizationWaitTimeout = \(romanizationWaitTimeout * 1_000)
    const startedAt = Date.now()

    let previousPayloadJSON = null
    let payloadChangedAt = startedAt
    let translationStartedAt = null

    const timer = setInterval(() => {
        // Google withholds source romanization while its editor is focused.
        if (document.activeElement?.tagName === 'TEXTAREA') {
            document.activeElement.blur()
        }

        const now = Date.now()
        const payload = {
            romanization: extractText(romanizationSelector),
            translation: extractText(translationSelector)
        }
        const payloadJSON = JSON.stringify(payload)

        if (payload.translation !== null && translationStartedAt === null) {
            translationStartedAt = now
        }

        if (payloadJSON !== previousPayloadJSON) {
            previousPayloadJSON = payloadJSON
            payloadChangedAt = now
        }

        const translationIsStable = payload.translation !== null
            && now - payloadChangedAt >= payloadStableInterval
        const romanizationIsReady = payload.romanization !== null
            || (translationStartedAt !== null
                && now - translationStartedAt >= romanizationWaitTimeout)
        const resultIsReady = translationIsStable && romanizationIsReady
        const resultTimedOut = now - startedAt >= resultTimeout

        if (!resultIsReady && !resultTimedOut) {
            return
        }

        clearInterval(timer)
        window.webkit.messageHandlers.translation.postMessage(payloadJSON)
    }, \(pollInterval * 1_000))
})()
"""
}

private struct WebTranslationPayload: Decodable {
    let translation: String?
    let romanization: String?
}
