//
//  ContentView.swift
//  pytest
//
//  Created by Armaan Aggarwal on 10/16/25.
//

import SwiftUI
import SwiftData
import UIKit

public let BackgroundColor = LinearGradient(
    gradient: Gradient(colors: [
        Color("GradientStart"),
        Color("GradientEnd"),
    ]),
    startPoint: .top,
    endPoint: .bottom
)

struct ContentView: View {
    @EnvironmentObject var player: PlayerCoordinator
    @EnvironmentObject var lastFM: LastFMSession
    
    init() {
        let titleColor = UIColor(named: "PrimaryText")!
        let normalTitleFont = UIFont(name: "Spicy Rice", size: 24)!
        let largeTitleFont = UIFont(name: "Spicy Rice", size: 32)!
        
        UINavigationBar.appearance().titleTextAttributes = [.foregroundColor: titleColor, .font: normalTitleFont]
        UINavigationBar.appearance().largeTitleTextAttributes = [.foregroundColor: titleColor, .font: largeTitleFont]
    }
        
    var body: some View {
        TabView {
            Tab("Search", systemImage: "magnifyingglass", role: .search) {
                NavigationStack() {
                    SearchScreen(
                        onDownloaded: { meta in
                            let item = LibraryItem(meta: meta)
                            player.startPlayback(libraryItem: item, filePath: meta.path)
                        }
                    )
                    .background(BackgroundColor.ignoresSafeArea(.all)) // for root view
                }
            }

            Tab("Library", systemImage: "music.note.square.stack.fill") {
                NavigationStack() {
                    LibraryScreen()
                        .background(BackgroundColor.ignoresSafeArea(.all)) // for root view
                }
            }
        }
        .onAppear {
            player.attach(lastFM: lastFM)
        }
        .tabViewBottomAccessory {
            if player.canShowPlayer == true, let libraryItem = player.libraryItem {
                HStack(spacing: 8) {
                    Button(action: { player.open() }) {
                        HStack(spacing: 12) {
                            SongImage(
                                width: 40,
                                height: 40,
                                thumbnailURL: libraryItem.thumbnail_url,
                                thumbnailIsSquare: libraryItem.thumbnail_is_square,
                                preloadedImage: player.artworkImage
                            )
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(libraryItem.title)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .lineLimit(1)
                                
                                Text(formatArtists(libraryItem.artists))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    if let audioPlayer = player.audioPlayer {
                        PlayPauseButton(audioPlayer: audioPlayer)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 12) {
                    SongImage(
                        width: 40,
                        height: 40,
                        thumbnailURL: nil,
                        thumbnailIsSquare: nil
                    )
                    
                    Text("Not Playing")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(isPresented: $player.isPresented) {
            if player.canShowPlayer {
                NavigationStack {
                    ZStack {
                        BackgroundColor
                            .ignoresSafeArea()
                        
                        PlayerScreen()
                    }
                }
            } else if true {
                
            } else {
                EmptyView()
            }
        }
    }
}

private struct PlayPauseButton: View {
    // required so we can observe changes to the audio player's isPlaying property
    @ObservedObject var audioPlayer: AudioPlayerWithReverb
    
    var body: some View {
        Button(action: {
            if audioPlayer.isPlaying {
                audioPlayer.pause()
            } else {
                audioPlayer.play()
            }
        }) {
            Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                .font(.title3)
                .foregroundStyle(Color("PrimaryText"))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(audioPlayer.isPlaying ? "Pause" : "Play")
    }
}

#Preview {
    @Previewable @StateObject var lastFM = LastFMSession()
    @Previewable @StateObject var player = PlayerCoordinator()
    
    // dummy in-memory model container for preview environments
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: LibraryItem.self, configurations: config)
    
    ContentView()
        .modelContainer(container)
        .environmentObject(player)
        .environmentObject(lastFM)
}
