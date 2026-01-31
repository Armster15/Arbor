//
//  SearchScreen.swift
//  pytest
//

import SwiftUI
import SDWebImage
import SDWebImageSwiftUI

enum SearchProvider: String, Hashable {
    case youtube
    case soundcloud
}


struct SearchResultsView: View {
    let searchResults: [SearchResult]
    let searchQuery: String
    let isSearching: Bool
    let onResultSelected: (SearchResult) -> Void
    let onDismiss: () -> Void
    @Binding var searchProvider: SearchProvider
    @State private var searchVisible: Bool = false
    
    var body: some View {
        let isSearchQueryURL = isValidURL(searchQuery)
        
        VStack(spacing: 0) {
            Picker("Provider", selection: $searchProvider) {
                Text("YouTube Music").tag(SearchProvider.youtube)
                Text("SoundCloud").tag(SearchProvider.soundcloud)
            }
            .pickerStyle(.segmented)
            .disabled(isSearchQueryURL)
            .padding()
            .opacity(searchVisible ? 1 : 0)
            .offset(y: searchVisible ? 0 : -8)
            .animation(.easeInOut(duration: 0.28), value: searchVisible)
            
            // Results List
            if searchQuery.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("Search for a song or artist")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isSearchQueryURL {
                // Show URL box for direct URL input
                VStack(spacing: 16) {
                    let result = SearchResult(
                        title: searchQuery,
                        artists: ["Raw URL"],
                        url: searchQuery,
                        views: nil,
                        duration: nil,
                        isExplicit: nil,
                        isVerified: nil,
                        thumbnailURL: nil,
                        thumbnailIsSquare: nil,
                        thumbnailWidth: nil,
                        thumbnailHeight: nil
                    )

                    SearchResultRow(result: result) {
                        onResultSelected(result)
                    }
                }
                .padding(.bottom, 16)
            } else if isSearching && searchResults.isEmpty {
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                        .progressViewStyle(CircularProgressViewStyle(tint: .secondary))
                        .accessibilityLabel("Searching...")
                    
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searchResults.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No results found")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    
                    Text("Try searching for a song title or artist")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(searchResults, id: \.url) { result in
                            SearchResultRow(result: result) {
                                onResultSelected(result)
                            }
                            
                            if result != searchResults.last {
                                Divider()
                                    .padding(.leading, 74)
                            }
                        }
                    }
                    .padding(.bottom, 16) // 16px padding
                }
            }
        }
        .onAppear {
            searchVisible = true
        }
        .onDisappear {
            searchVisible = false
        }
    }
}

struct SearchResultRow: View {
    let result: SearchResult
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Thumbnail
                SongImage(
                    width: 50,
                    height: 50,
                    thumbnailURL: result.thumbnailURL,
                    thumbnailIsSquare: result.thumbnailIsSquare
                )
                
                // Content
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    HStack(spacing: 6) {
                        if result.isExplicit == true {
                            Text("E")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .accessibilityLabel("Explicit")
                        }

                        HStack(spacing: 4) {
                            Text(formatArtists(result.artists))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            if result.isVerified == true {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .accessibilityLabel("Verified artist")
                            }
                        }
                    }
                    
                    HStack(spacing: 8) {
                        if let duration = result.duration {
                            Text(duration)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        if let views = result.views {
                            HStack(spacing: 2) {
                                Image(systemName: "eye")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(views)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 16)
    }
}

struct DownloadScreen: View {
    let onDownloaded: (DownloadMeta) -> Void
    @Binding var selectedResult: SearchResult?
    var clearSelectionOnFailure: Bool = true
    
    @State private var isLoading: Bool = false
    @State private var idleOpacity: Double = 1.0
    @State private var showDownloadErrorAlert = false
    @State private var downloadErrorMessage = ""
    @State private var downloadLogText: String? = nil
    @State private var showDownloadLogSheet = false

    var body: some View {
        VStack(spacing: 20) {
            if isLoading {
                ZStack {
                    VStack(spacing: 32) {
                        if let result = selectedResult {
                            SongInfo(
                                title: result.title,
                                artists: result.artists,
                                thumbnailURL: result.thumbnailURL,
                                thumbnailIsSquare: result.thumbnailIsSquare
                            )
                        }
                        
                        HStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .progressViewStyle(CircularProgressViewStyle(tint: .secondary))
                                .accessibilityLabel("Downloading...")
                            Text("Downloading...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            else {
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("Start searching to find songs")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .opacity(idleOpacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    idleOpacity = 0
                    withAnimation(.easeInOut(duration: 0.25)) {
                        idleOpacity = 1
                    }
                }
            }
        }
        .padding()
        .alert("Download Failed", isPresented: $showDownloadErrorAlert) {
            if downloadLogText?.isEmpty == false {
                Button("View Logs") {
                    showDownloadLogSheet = true
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(downloadErrorMessage)
        }
        .sheet(isPresented: $showDownloadLogSheet) {
            NavigationStack {
                LogViewer(
                    title: "View Logs",
                    logText: downloadLogText,
                    showClose: true
                )
            }
        }
        .onAppear {
            triggerDownloadIfPossible()
        }
        .onChange(of: selectedResult?.url) { _, _ in
            triggerDownloadIfPossible()
        }
    }
    
    private func triggerDownloadIfPossible() {
        guard !isLoading, let url = selectedResult?.url else { return }
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        downloadAudio(with: trimmed)
    }
    
    private func downloadAudio(with url: String) {
        isLoading = true
        downloadLogText = nil
        showDownloadLogSheet = false
        
        AudioDownloader.download(from: url, searchResult: selectedResult) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                
                switch result {
                case .success(let meta):
                    self.onDownloaded(meta)
                    self.selectedResult = nil
                    
                case .failure(let error):
                    var message: String
                    var logText: String? = nil
                    
                    if let downloadError = error as? DownloadError {
                        switch downloadError {
                        case .invalidSelection:
                            message = "Invalid selection."
                        case .emptyResult(let log):
                            message = "Failed to download audio. Please check the URL and try again."
                            logText = log
                        case .invalidResponse(let log):
                            message = "Invalid response from downloader."
                            logText = log
                        case .pythonFailed(let log):
                            message = "Failed to download audio. Please check the URL and try again."
                            logText = log
                        }
                    } else {
                        message = "Failed to download audio. Please check the URL and try again."
                    }

                    message += "\n\nIf the problem persists, try updating the dependencies in Settings."

                    downloadErrorMessage = message
                    downloadLogText = logText
                    showDownloadErrorAlert = true
                    if clearSelectionOnFailure {
                        self.selectedResult = nil
                    }
                }
            }
        }
    }
}

struct SearchScreen: View {
    let onDownloaded: (DownloadMeta) -> Void

    @State private var searchQuery: String = ""
    @State private var searchResults: [SearchResult] = []
    @State private var searchIsActive = false
    @State private var isSearching = false
    @State private var currentSearchTaskId: UUID = UUID()
    @State private var searchDebounceTimer: Timer?
    @AppStorage("homeScreenSearchProvider") var searchProvider: SearchProvider = .youtube
    @State private var selectedResult: SearchResult? = nil

    var body: some View {
        Group {
            if searchIsActive {
                // Search Results View
                SearchResultsView(
                    searchResults: searchResults,
                    searchQuery: searchQuery,
                    isSearching: isSearching,
                    onResultSelected: { result in
                        selectedResult = result
                        searchIsActive = false
                        searchQuery = ""
                        searchResults = []
                        isSearching = false
                    },
                    onDismiss: {
                        searchIsActive = false
                        searchQuery = ""
                        searchResults = []
                        isSearching = false
                    },
                    searchProvider: $searchProvider
                )
            } else {
                // Download / idle screen when no search is active
                DownloadScreen(
                    onDownloaded: onDownloaded,
                    selectedResult: $selectedResult
                )
            }
        }
        .navigationTitle("Search")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .searchable(
            text: $searchQuery,
            isPresented: $searchIsActive,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Search for music"
        )
        .onSubmit(of: .search) {
            performDebouncedSearch()
        }
        .onChange(of: searchQuery) { _, newValue in
            if newValue.isEmpty {
                // Cancel any pending search and clear results immediately
                searchResults = []
                isSearching = false
                searchDebounceTimer?.invalidate()
                searchDebounceTimer = nil
            } else {
                performDebouncedSearch()
            }
        }
        .onChange(of: searchProvider) { _, _ in
            // Clear existing results when switching providers
            searchResults = []
            
            if !searchQuery.isEmpty {
                performDebouncedSearch()
            }
        }
        .onChange(of: searchIsActive) { _, isActive in
            if !isActive {
                // Cancel any pending search when dismissing search
                searchQuery = ""
                searchResults = []
                isSearching = false
                searchDebounceTimer?.invalidate()
                searchDebounceTimer = nil
            }
        }
        .onDisappear {
            searchDebounceTimer?.invalidate()
            searchDebounceTimer = nil
        }
    }
    
    private func performDebouncedSearch() {
        isSearching = true
        searchDebounceTimer?.invalidate()
        searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
            performSearch()
        }
    }

    private func performSearch() {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        // If query is a URL, don't perform search
        if isValidURL(trimmed) {
            searchResults = []
            isSearching = false
            return
        }

        // Build cache key and return cached results if available
        let cacheKey = ["search", searchProvider.rawValue, trimmed.lowercased()]
        if let cached: [SearchResult] = QueryCache.shared.get(for: cacheKey) {
            searchResults = cached
            isSearching = false
            return
        }

        // Generate a new unique task ID for this search request
        let taskId = UUID()
        currentSearchTaskId = taskId
        isSearching = true

        // Escape backslashes and single quotes for safe embedding in Python string literal
        let escaped = trimmed
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")

        let code: String
        switch searchProvider {
        case .youtube:
            code = """
from arbor import search_youtube
result = search_youtube('\(escaped)')
"""
        case .soundcloud:
            code = """
from arbor import search_soundcloud
result = search_soundcloud('\(escaped)')
"""
        }

        pythonExecAndGetStringAsync(
            code.trimmingCharacters(in: .whitespacesAndNewlines),
            "result"
        ) { result in            
            defer { 
                if taskId == currentSearchTaskId {
                    isSearching = false
                }
             }
             
            guard let output = result, !output.isEmpty,
                  let data = output.data(using: .utf8),
                  let items = try? JSONDecoder().decode([SearchResult].self, from: data) else {
                // silently ignore and clear suggestions on failure
                
                if taskId == currentSearchTaskId {
                    searchResults = []
                }
                
                return
            }
            
            QueryCache.shared.set(items, for: cacheKey)

            if taskId == currentSearchTaskId {
                searchResults = items
            }
        }
    }
}
