//
//  pytestApp.swift
//  pytest
//
//  Created by Armaan Aggarwal on 10/16/25.
//

import SwiftUI
import SwiftData
import CloudKitSyncMonitor

@main
struct ArborApp: App {
    @StateObject private var player = PlayerCoordinator()
    @StateObject private var lastFM = LastFMSession()
    // Keep the library in the app's own container; with the App Group entitlement SwiftData would otherwise default to a new, empty store in the group container
    private let modelContainer = try! ModelContainer(
        for: LibraryItem.self,
        configurations: ModelConfiguration(groupContainer: .none)
    )
    
    init() {
        _ = start_python_runtime(CommandLine.argc, CommandLine.unsafeArgv)
        SyncMonitor.default.startMonitoring()
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(player)
                .environmentObject(lastFM)
        }
        .modelContainer(modelContainer)
    }
}
