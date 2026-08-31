import Combine
import Foundation
import WebKit

private let googleTranslateRomanizationSelector = #"[jsname="toZopb"]"#
private let googleTranslateTranslationSelector = #"[jsname="W297wb"]"#
private let googleTranslateUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"
private let googleTranslatePageLoadTimeout: TimeInterval = 60
private let googleTranslateResultTimeout: TimeInterval = 30
private let googleTranslatePollInterval: TimeInterval = 0.25

enum GoogleTranslateResult {
    case loaded(translation: String?, romanization: String?)
    case failed(String)
}

@MainActor
final class GoogleTranslateService: ObservableObject {
    static let shared = GoogleTranslateService()

    @Published private(set) var activeWebView: WKWebView?
    private var activeRequest: GoogleTranslateRequest?

    private init() {}

    func translate(
        _ text: String,
        completion: @escaping (GoogleTranslateResult) -> Void
    ) {
        activeRequest?.cancel()

        let request = GoogleTranslateRequest(text: text, completion: completion)
        request.onFinish = { [weak self, weak request] in
            guard self?.activeRequest === request else { return }
            self?.activeRequest = nil
            self?.activeWebView = nil
        }
        activeRequest = request
        activeWebView = request.webView
        request.start()
    }

    func cancel() {
        activeRequest?.cancel()
    }
}

@MainActor
private final class GoogleTranslateRequest: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private static let messageHandlerName = "translation"

    private let text: String
    private var completion: ((GoogleTranslateResult) -> Void)?
    private var stageTimeoutTimer: Timer?
    private(set) var webView: WKWebView!

    var onFinish: (() -> Void)?

    init(text: String, completion: @escaping (GoogleTranslateResult) -> Void) {
        self.text = text
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
        webView.customUserAgent = googleTranslateUserAgent
        webView.isInspectable = true
        webView.navigationDelegate = self
    }

    func start() {
        guard let url = translationURL else {
            finish(.failed("Could not create the Google Translate URL."))
            return
        }

        startTimeout(
            after: googleTranslatePageLoadTimeout,
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
            after: googleTranslateResultTimeout + googleTranslatePollInterval,
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

        if let error = payload.error {
            finish(.failed(error))
        } else {
            finish(
                .loaded(
                    translation: payload.translation,
                    romanization: payload.romanization
                )
            )
        }
    }

    private var translationURL: URL? {
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.!~*'()"))
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

    let romanizationSelector = '\(googleTranslateRomanizationSelector)'
    let translationSelector = '\(googleTranslateTranslationSelector)'
    var previousPayload = null
    var stablePolls = 0
    var translationPolls = 0
    const startedAt = Date.now()
    const resultTimeout = \(googleTranslateResultTimeout * 1_000)

    const timer = setInterval(() => {
        const payload = {
            romanization: extractText(romanizationSelector),
            translation: extractText(translationSelector)
        }
        const serialized = JSON.stringify(payload)

        if (payload.translation) {
            translationPolls += 1
        }

        if (payload.translation && serialized === previousPayload) {
            stablePolls += 1
        } else {
            stablePolls = 0
            previousPayload = serialized
        }

        const romanizationReady = payload.romanization && stablePolls >= 4
        const romanizationWaitExpired = translationPolls >= 20 && stablePolls >= 4

        if (romanizationReady || romanizationWaitExpired) {
            clearInterval(timer)
            window.webkit.messageHandlers.translation.postMessage(serialized)
        } else if (Date.now() - startedAt >= resultTimeout) {
            clearInterval(timer)
            window.webkit.messageHandlers.translation.postMessage(serialized)
        }
    }, \(googleTranslatePollInterval * 1_000))
})()
"""
}

private struct WebTranslationPayload: Decodable {
    let translation: String?
    let romanization: String?
    let error: String?
}
