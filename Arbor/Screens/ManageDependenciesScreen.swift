import Darwin
import Foundation
import SwiftUI

private enum DependencyUpdateStatus {
    case idle
    case running
    case success
    case failure
}

private struct DependencyInfo: Identifiable, Decodable {
    let name: String
    let baseVersion: String?
    let updatedVersion: String?

    var id: String { name }

    private enum CodingKeys: String, CodingKey {
        case name
        case baseVersion = "base_version"
        case updatedVersion = "updated_version"
    }
}

private struct DependencyUpdateResponse: Decodable {
    let success: Bool
    let log: String
}

struct ManageDependenciesScreen: View {
    @State private var dependencyInfo: [DependencyInfo] = []
    @State private var updateStatus: DependencyUpdateStatus = .idle
    @State private var updateLog: String?
    @State private var isLoadingVersions = false
    @State private var isDisclosureExpanded = false
    @State private var showDeleteConfirm = false
    @State private var showRestartPrompt = false
    @State private var restartRequired = false
    @State private var showRawDate = false
    @State private var lastUpdatedDate: Date?
    @State private var hasUpdatedDependencies = false
    @State private var didLoad = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        "Arbor relies on third-party dependencies that occasionally require updates."
                    )
                    .font(.subheadline)
                    .foregroundColor(Color("PrimaryText").opacity(0.8))
                }
                .padding(.vertical, 4)
                .listRowBackground(Color("SecondaryBg"))
            }

            Section {
                lastUpdatedRow
                    .listRowBackground(Color("SecondaryBg"))

                updateActionRow
                    .listRowBackground(Color("SecondaryBg"))

                updateResultRow
                    .listRowBackground(Color("SecondaryBg"))

                deleteUpdatedRow
                    .listRowBackground(Color("SecondaryBg"))
            }

            Section {
                DisclosureGroup(isExpanded: $isDisclosureExpanded) {
                    if isLoadingVersions {
                        HStack {
                            ProgressView()
                            Text("Loading versions...")
                                .font(.subheadline)
                                .foregroundColor(Color("PrimaryText").opacity(0.8))
                        }
                        .padding(.vertical, 6)
                    } else {
                        ForEach(dependencyInfo) { dependency in
                            dependencyRow(dependency)
                                .padding(.vertical, 4)
                        }
                    }
                } label: {
                    Text("Installed Versions")
                        .foregroundColor(Color("PrimaryText"))
                        .font(.headline)
                }
            }
            .listRowBackground(Color("SecondaryBg"))

        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) {
            if restartRequired {
                Button {
                    requestAppRestart()
                } label: {
                    Text("Restart Arbor")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .primaryActionButtonStyle(isLoading: false, isDisabled: false)
                .padding(.top, 8)
            }
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            refreshUpdateMetadata()
            loadDependencyVersions()
        }
        .alert("Delete updated dependencies?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                deleteUpdatedDependencies()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove any updated packages and require a restart.")
        }
        .alert("Restart Required", isPresented: $showRestartPrompt) {
            Button("Restart Now", role: .destructive) {
                requestAppRestart()
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Dependency changes require restarting Arbor. You can still view update logs before restarting.")
        }
    }

    private var lastUpdatedRow: some View {
        let relativeText = lastUpdatedDate.map(relativeDateString) ?? "never"
        let rawDateText = lastUpdatedDate.map(rawDateString)

        return HStack {
            Text("Last updated:")
                .foregroundColor(Color("PrimaryText"))

            Spacer()

            Text(showRawDate ? (rawDateText ?? relativeText) : relativeText)
                .foregroundColor(Color("PrimaryText").opacity(0.8))
                .onTapGesture {
                    guard lastUpdatedDate != nil else { return }
                    showRawDate.toggle()
                }
        }
    }

    private var updateActionRow: some View {
        Button {
            runDependencyUpdate()
        } label: {
            HStack {
                Text("Update dependencies")
                Spacer()
                if updateStatus == .running {
                    ProgressView()
                }
            }
        }
        .tint(.blue)
        .disabled(updateStatus == .running)
    }

    @ViewBuilder
    private var updateResultRow: some View {
        if updateStatus == .success || updateStatus == .failure {
            NavigationLink {
                DependencyUpdateLogView(
                    logText: updateLog,
                    showRestartButton: restartRequired,
                    onRestart: requestAppRestart
                )
            } label: {
                Text(updateStatus == .success ? "Update complete" : "Update failed")
            }
        }
    }

    private var deleteUpdatedRow: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            Text("Delete updated dependencies")
        }
        .disabled(!hasUpdatedDependencies || updateStatus == .running)
    }

    private func dependencyRow(_ dependency: DependencyInfo) -> some View {
        HStack {
            Text(dependency.name)
                .foregroundColor(Color("PrimaryText"))

            Spacer()

            if let updatedVersion = dependency.updatedVersion,
               updatedVersion != dependency.baseVersion {
                HStack(spacing: 6) {
                    if let baseVersion = dependency.baseVersion {
                        Text(baseVersion)
                            .strikethrough()
                            .foregroundColor(Color("PrimaryText").opacity(0.5))
                    }

                    Text(updatedVersion)
                        .foregroundColor(Color.green)
                }
            } else if let baseVersion = dependency.baseVersion {
                Text(baseVersion)
                    .foregroundColor(Color("PrimaryText").opacity(0.8))
            } else {
                Text("Unknown")
                    .foregroundColor(Color("PrimaryText").opacity(0.6))
            }
        }
    }

    private func loadDependencyVersions() {
        isLoadingVersions = true
        let code = """
import json
from arbor import get_dependency_versions
result = json.dumps(get_dependency_versions())
"""
        pythonExecAndGetStringAsync(code, "result") { result in
            defer { isLoadingVersions = false }
            guard let result,
                  let data = result.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([DependencyInfo].self, from: data) else {
                dependencyInfo = []
                return
            }
            dependencyInfo = decoded
        }
    }

    private func runDependencyUpdate() {
        updateStatus = .running
        let code = """
import json
from arbor import update_pkgs
success, log = update_pkgs()
result = json.dumps({"success": success, "log": log})
"""
        pythonExecAndGetStringAsync(code, "result") { result in
            guard let result,
                  let data = result.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(DependencyUpdateResponse.self, from: data) else {
                updateStatus = .failure
                refreshUpdateMetadata()
                return
            }

            updateLog = decoded.log
            updateStatus = decoded.success ? .success : .failure
            refreshUpdateMetadata()
            loadDependencyVersions()
            if decoded.success {
                restartRequired = true
                showRestartPrompt = true
            }
        }
    }

    private func deleteUpdatedDependencies() {
        let code = """
from arbor import delete_updated_pkgs
delete_updated_pkgs()
result = "ok"
"""
        pythonExecAndGetStringAsync(code, "result") { _ in
            hasUpdatedDependencies = false
            lastUpdatedDate = nil
            refreshUpdateMetadata()
            loadDependencyVersions()
            restartRequired = true
            showRestartPrompt = true
        }
    }

    private func refreshUpdateMetadata() {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return
        }

        let updatedDir = appSupportURL.appendingPathComponent("updated_python_modules")

        hasUpdatedDependencies = fileManager.fileExists(atPath: updatedDir.path)
        if let attrs = try? fileManager.attributesOfItem(atPath: updatedDir.path),
           let date = attrs[.modificationDate] as? Date {
            lastUpdatedDate = date
        } else {
            lastUpdatedDate = nil
        }
    }

    private func relativeDateString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func rawDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func requestAppRestart() {
        exit(0)
    }
}

private struct DependencyUpdateLogView: View {
    let logText: String?
    let showRestartButton: Bool
    let onRestart: () -> Void

    var body: some View {
        let displayText = logText?.isEmpty == false ? (logText ?? "") : "No update logs yet."
        ScrollView {
            Text(displayText)
                .font(.system(.footnote, design: .monospaced))
                .foregroundColor(Color("PrimaryText"))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .background(BackgroundColor.ignoresSafeArea())
        .navigationTitle("Update Logs")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if showRestartButton {
                Button {
                    onRestart()
                } label: {
                    Text("Restart Arbor")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .primaryActionButtonStyle(isLoading: false, isDisabled: false)
                .padding(.top, 8)
            }
        }
    }
}
