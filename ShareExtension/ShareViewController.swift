//
//  ShareViewController.swift
//  ShareExtension
//
//  Hands a shared link to Arbor and opens it, which downloads and plays the link.
//

import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await handleShare() }
    }

    private func handleShare() async {
        guard let url = await sharedURL() else {
            showMessage(title: "No Link Found", message: "Arbor can only download shared links.")
            return
        }

        SharedURL.set(url.absoluteString)

        openArbor { opened in
            if opened {
                self.done()
            } else {
                self.showMessage(title: "Added to Arbor", message: "It will play the next time you open Arbor.")
            }
        }
    }

    private func sharedURL() async -> URL? {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let providers = items.flatMap { $0.attachments ?? [] }

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
               !url.isFileURL {
                return url
            }

            // Some apps share a link as text, sometimes with other text around it
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
               let url = firstLink(in: text) {
                return url
            }
        }

        return nil
    }

    private func firstLink(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        return detector?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))?.url
    }

    // Extensions can't access UIApplication.shared, but the app instance is reachable through the responder chain
    private func openArbor(completion: @escaping (Bool) -> Void) {
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(URL(string: "arbor://")!, options: [:], completionHandler: completion)
                return
            }
            responder = current.next
        }
        completion(false)
    }

    private func showMessage(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in self.done() })
        present(alert, animated: true)
    }

    private func done() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
