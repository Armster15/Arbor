//
//  SharedURLQueue.swift
//  Arbor
//
//  URLs shared to Arbor from the share extension that the app still needs to download.
//  Compiled into both the app and the share extension.
//

import Foundation

enum SharedURLQueue {
    private static let defaults = UserDefaults(suiteName: "group.com.armaana.arbor")
    private static let key = "pendingSharedURLs"

    static func append(_ url: String) {
        let urls = defaults?.stringArray(forKey: key) ?? []
        defaults?.set(urls + [url], forKey: key)
    }

    static func takeAll() -> [String] {
        let urls = defaults?.stringArray(forKey: key) ?? []
        defaults?.removeObject(forKey: key)
        return urls
    }
}
