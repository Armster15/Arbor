//
//  SettingsScreen.swift
//  Arbor
//
//  Created by Armaan Aggarwal on 12/2/25.
//


import SwiftUI
import CloudKitSyncMonitor

struct SettingsScreen: View {
    @StateObject private var syncMonitor = SyncMonitor.default
    @EnvironmentObject private var lastFM: LastFMSession

    var body: some View {
        List {
            Section {
                SyncStatusRow(syncMonitor: syncMonitor)
                    .listRowBackground(Color("SecondaryBg"))
            }

            NavigationLink {
                ZStack {
                    BackgroundColor
                        .ignoresSafeArea()

                    LastFMScreen()
                }
                .navigationTitle("last.fm")
                .navigationBarTitleDisplayMode(.inline)
            } label: {
                IntegrationRow(
                    title: "last.fm",
                    subtitle: lastFM.isAuthenticated ? lastFM.username : "Connect to start scrobbling",
                    showsDisabledBadge: lastFM.isAuthenticated && !lastFM.isScrobblingEnabled
                )
            }
            .listRowBackground(Color("SecondaryBg"))

            Section {
                NavigationLink("Manage Dependencies") {
                    ZStack {
                        BackgroundColor
                            .ignoresSafeArea()

                        ManageDependenciesScreen()
                    }
                    .navigationTitle("Manage Dependencies")
                    .navigationBarTitleDisplayMode(.inline)
                }
                .listRowBackground(Color("SecondaryBg"))
                .foregroundColor(Color("PrimaryText"))

                NavigationLink("Manage Cache") {
                    ZStack {
                        BackgroundColor
                            .ignoresSafeArea()

                        ManageCacheScreen()
                    }
                    .navigationTitle("Manage Cache")
                    .navigationBarTitleDisplayMode(.inline)
                }
                .listRowBackground(Color("SecondaryBg"))
                .foregroundColor(Color("PrimaryText"))
            }

#if DEBUG
            Section("Developer") {
                NavigationLink("Python REPL") {
                    ZStack {
                        BackgroundColor
                            .ignoresSafeArea()

                        DeveloperPythonReplScreen()
                    }
                    .navigationTitle("Python REPL")
                    .navigationBarTitleDisplayMode(.inline)
                }
                .listRowBackground(Color("SecondaryBg"))
                .foregroundColor(Color("PrimaryText"))
            }
#endif
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Settings")
    }
}

private struct IntegrationRow: View {
    let title: String
    let subtitle: String
    var showsDisabledBadge: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image("LastFM")
                .resizable()
                .scaledToFill()
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(Color("PrimaryText"))

                    if showsDisabledBadge {
                        Text("Disabled")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(Color("PrimaryText"))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color("Elevated"))
                            .clipShape(Capsule())
                    }
                }

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(Color("PrimaryText").opacity(0.8))
                    .lineLimit(2)
            }
        }
    }
}

private struct SyncStatusRow: View {
    @ObservedObject var syncMonitor: SyncMonitor

    var body: some View {
        Button {
            if syncMonitor.hasSyncError {
                if let error = syncMonitor.setupError {
                    showAlert(title: "iCloud Sync Error", message: "Unable to set up iCloud sync, changes won't be saved! \(error.localizedDescription)")
                }
                if let error = syncMonitor.importError {
                    showAlert(title: "iCloud Sync Error", message: "Import is broken: \(error.localizedDescription)")
                }
                if let error = syncMonitor.exportError {
                    showAlert(title: "iCloud Sync Error", message: "Export is broken - your changes aren't being saved! \(error.localizedDescription)")
                }
            } else if syncMonitor.isNotSyncing {
                showAlert(title: "iCloud Sync Error", message: "Sync should be working, but isn't. Look for a badge on Settings or other possible issues.")
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: syncMonitor.syncStateSummary.symbolName)
                    .font(.title2)
                    .foregroundColor(syncMonitor.syncStateSummary.symbolColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text("iCloud Sync")
                        .font(.headline)
                        .foregroundColor(Color("PrimaryText"))

                    Text(syncMonitor.syncStateSummary.description)
                        .font(.subheadline)
                        .foregroundColor(Color("PrimaryText").opacity(0.8))
                }

                Spacer()

                if syncMonitor.syncStateSummary.isInProgress {
                    ProgressView()
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ZStack {
            BackgroundColor.ignoresSafeArea()
            SettingsScreen()
        }
    }
}
