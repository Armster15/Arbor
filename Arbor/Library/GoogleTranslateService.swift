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
    private static let separator = "\u{E000}"

    static func encode(_ lines: [String]) -> String {
        lines.joined(separator: "\n\(separator)\n")
    }

    static func decode(_ text: String) -> [String] {
        if text.contains(separator) {
            return text
                .components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }

        return text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .newlines)
            .components(separatedBy: "\n")
    }
}

enum GoogleTranslateResult {
    case loaded(translations: [String]?, romanizations: [String]?)
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

        let translations = payload.translation.map(TranslationLines.decode)
        if let translations, translations.count != sourceLines.count {
            finish(.failed("Google Translate returned a different number of translated lyric lines."))
            return
        }

        let romanizations = payload.romanization.map(TranslationLines.decode)
        if let romanizations, romanizations.count != sourceLines.count {
            finish(.failed("Google Translate returned a different number of romanized lyric lines."))
            return
        }

        finish(.loaded(translations: translations, romanizations: romanizations))
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
        const element = document.querySelector(selector)
        return element?.innerText || null
    }

    const romanizationSelector = '\(romanizationSelector)'
    const translationSelector = '\(translationSelector)'
    var previousPayload = null
    var payloadChangedAt = Date.now()
    var translationStartedAt = null
    const startedAt = Date.now()
    const resultTimeout = \(resultTimeout * 1_000)
    const payloadStableInterval = \(payloadStableInterval * 1_000)
    const romanizationWaitTimeout = \(romanizationWaitTimeout * 1_000)

    const timer = setInterval(() => {
        const now = Date.now()
        const payload = {
            romanization: extractText(romanizationSelector),
            translation: extractText(translationSelector)
        }
        const serialized = JSON.stringify(payload)

        if (payload.translation && translationStartedAt === null) {
            translationStartedAt = now
        }

        if (serialized !== previousPayload) {
            previousPayload = serialized
            payloadChangedAt = now
        }

        const payloadIsStable = payload.translation
            && now - payloadChangedAt >= payloadStableInterval
        const romanizationWaitExpired = translationStartedAt !== null
            && now - translationStartedAt >= romanizationWaitTimeout
        const resultIsReady = payloadIsStable
            && (payload.romanization || romanizationWaitExpired)
        const resultTimedOut = now - startedAt >= resultTimeout

        if (resultIsReady || resultTimedOut) {
            clearInterval(timer)
            window.webkit.messageHandlers.translation.postMessage(serialized)
        }
    }, \(pollInterval * 1_000))
})()
"""
}

private struct WebTranslationPayload: Decodable {
    let translation: String?
    let romanization: String?
}
