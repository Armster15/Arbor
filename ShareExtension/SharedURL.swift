//
//  SharedURL.swift
//  Arbor
//
//  The latest URL shared to Arbor from the share extension that the app still needs to play.
//  Compiled into both the app and the share extension.
//

import Foundation

enum SharedURL {
    private static let defaults = UserDefaults(suiteName: "group.com.armaana.arbor")
    private static let key = "pendingSharedURL"

    static func set(_ url: String) {
        defaults?.set(url, forKey: key)
    }

    static func take() -> String? {
        let url = defaults?.string(forKey: key)
        defaults?.removeObject(forKey: key)
        return url
    }
}
