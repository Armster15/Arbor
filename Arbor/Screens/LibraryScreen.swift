//
//  LibraryScreen.swift
//  Arbor
//
//  Created by Armaan Aggarwal on 11/11/25.
//

import SwiftUI
import SwiftData

struct LibraryScreen: View {
    @Environment(\.modelContext) var modelContext
    @EnvironmentObject var player: PlayerCoordinator
    
    @Query(sort: \LibraryItem.createdAt, order: .reverse) var libraryItems: [LibraryItem]
    
    @State private var downloadSource: SearchResult? = nil
    @State private var downloadingItem: LibraryItem? = nil
    @State private var showSettings = false
    
    func deleteLibraryItems(_ indexSet: IndexSet) {
        for index in indexSet {
            let model = libraryItems[index]
            modelContext.delete(model)
        }
    }
    
    func onTap(_ item: LibraryItem) {
        // if tapped item is the same as currently active library item, don't reset playback
        if player.libraryItem?.persistentModelID == item.id {
            player.open()
            return
        }
        
        if let absolutePath = getLocalAudioFilePath(originalUrl: item.original_url) {
            player.startPlayback(libraryItem: item, filePath: absolutePath)
            return
        }
        
        // No usable local file – fall back to re-downloading using the original URL.
        let result = SearchResult(
            title: item.title,
            artists: item.artists,
            url: item.original_url,
            views: nil,
            duration: nil,
            isExplicit: nil,
            isVerified: nil,
            thumbnailURL: item.thumbnail_url,
            thumbnailIsSquare: item.thumbnail_is_square,
            thumbnailWidth: item.thumbnail_width,
            thumbnailHeight: item.thumbnail_height
        )
        
        downloadSource = result
        downloadingItem = item
    }
    
    var body: some View {
        Group {
            if libraryItems.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "music.note.square.stack.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No songs in library")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    
                    Text("Start searching to find songs")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .multilineTextAlignment(.center)
            } else {
                List {
                    ForEach(libraryItems, id: \.persistentModelID) { item in
                        Button(action: {
                            onTap(item)
                        }) {
                            HStack(alignment: .center, spacing: 12) {
                                SongImage(
                                    width: 60,
                                    height: 60,
                                    thumbnailURL: item.thumbnail_url,
                                    thumbnailIsSquare: item.thumbnail_is_square
                                )
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(.headline)
                                        .foregroundColor(Color("PrimaryText"))
                                    
                                    Text(formatArtists(item.artists))
                                        .font(.subheadline)
                                        .foregroundColor(Color("PrimaryText"))
                                    
                                    HStack(spacing: 12) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "gauge.with.dots.needle.67percent")
                                                .font(.caption)
                                            Text(String(format: "%.2fx", item.speedRate))
                                                .font(.caption)
                                        }
                                        HStack(spacing: 4) {
                                            Image(systemName: "tuningfork")
                                                .font(.caption)
                                            Text(String(format: "%+.0f", item.pitchCents))
                                                .font(.caption)
                                        }
                                        HStack(spacing: 4) {
                                            Image(systemName: "dot.radiowaves.left.and.right")
                                                .font(.caption)
                                            Text("\(Int(item.reverbMix))%")
                                                .font(.caption)
                                        }
                                    }
                                    .foregroundColor(.secondary)
                                }
                            }
                        }
                        .listRowBackground(Color("SecondaryBg"))
                    }
                    .onDelete(perform: deleteLibraryItems)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("arbor")
        .toolbar {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gear")
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                ZStack {
                    BackgroundColor
                        .ignoresSafeArea()
                    
                    SettingsScreen()
                }
            }
        }
        .sheet(
            isPresented: Binding(
                get: { downloadSource != nil },
                set: { isPresented in
                    if !isPresented {
                        downloadSource = nil
                        downloadingItem = nil
                    }
                }
            )
        ) {
            if let libraryItem = downloadingItem {
                DownloadScreen(
                    onDownloaded: { meta in
                        let _ = ensureLocalAudioFile(
                            originalUrl: libraryItem.original_url,
                            sourcePath: meta.path,
                            title: libraryItem.title,
                            artists: libraryItem.artists,
                            onMissingPhysicalFile: {
                                debugPrint("Deleting outdated library item: \(libraryItem.title)")
                                modelContext.delete(libraryItem)
                            }
                        )
                        
                        player.startPlayback(libraryItem: libraryItem, filePath: meta.path)
                    },
                    selectedResult: Binding(
                        get: { downloadSource },
                        set: { newValue in
                            downloadSource = newValue
                        }
                    ),
                    clearSelectionOnFailure: false
                )
                .background(BackgroundColor.ignoresSafeArea(.all))
            } else {
                Color.clear
            }
        }
    }
}
