//
//  PlayerCoordinator.swift
//  Arbor
//
//  Created by Armaan Aggarwal on 11/11/25.
//

import SwiftUI
import SDWebImage
import Combine

@MainActor
final class PlayerCoordinator: ObservableObject {
    @Published var isPresented: Bool = false
    @Published var audioPlayer: AudioPlayerWithReverb? = nil
    @Published var libraryItem: LibraryItem? = nil
    @Published var filePath: String? = nil
    @Published var artworkImage: UIImage? = nil
    @Published var artworkURL: URL? = nil
    @Published var lyricsDisplayMode: LyricsDisplayMode = .original
    @Published private(set) var isLastFMEnabled: Bool = false

    private var lastFM: LastFMSession?
    private let scrobbleCoordinator = ScrobbleCoordinator()
    private var audioPlayerCancellables = Set<AnyCancellable>() // for monitoring changes to `duration`, `currentTime`, and `isPlaying` properties
    private var lastFMCancellable: AnyCancellable? // for monitoring changes to `manager` and `isScrobblingEnabled` properties

    // for setting the global LastFM session
    func attach(lastFM: LastFMSession) {
        self.lastFM = lastFM
        lastFMCancellable = Publishers.CombineLatest3(
            lastFM.$manager,
            lastFM.$isScrobblingEnabled,
            lastFM.$isAuthenticated
        )
            .sink { [weak self] manager, isEnabled, isAuthenticated in
                guard let self = self else { return }
                let isLastFMEnabled = isAuthenticated && isEnabled && manager != nil
                self.isLastFMEnabled = isLastFMEnabled

                guard isLastFMEnabled else { return }
                Task {
                    await self.scrobbleCoordinator.flushIfNeeded(manager: manager)
                }
            }
    }

    public func open()  {
        if canShowPlayer {
            isPresented = true
        }
    }
    
    public func close() { isPresented = false }
    
    public var canShowPlayer: Bool { audioPlayer != nil && libraryItem != nil && filePath != nil }
    
    public func startPlayback(libraryItem: LibraryItem, filePath: String) {
        debugPrint(filePath, libraryItem)

        self.filePath = filePath
        self.libraryItem = libraryItem
        self.lyricsDisplayMode = .original

        // Load artwork image so we don't reconstruct it on every rerender in the bottom tab view accessory of ContentView
        let nextArtworkURL = libraryItem.thumbnail_url.flatMap { URL(string: $0) }
        if artworkURL != nextArtworkURL {
            artworkURL = nextArtworkURL
            artworkImage = nil
            if let url = nextArtworkURL {
                SDWebImageManager.shared.loadImage(
                    with: url,
                    options: [.highPriority, .retryFailed, .scaleDownLargeImages],
                    progress: nil
                ) { [weak self] image, _, error, _, finished, _ in
                    guard let self = self, error == nil, finished, let image else { return }
                    Task { @MainActor in
                        if self.artworkURL == url {
                            self.artworkImage = image
                        }
                    }
                }
            }
        }
        
        // Tear down any existing engine before creating a new one
        audioPlayer?.unsubscribeUpdates()
        audioPlayer = nil
        
        let newAudioPlayer = AudioPlayerWithReverb()
        
        let artworkURL = libraryItem.thumbnail_url.flatMap { URL(string: $0) }
        
        newAudioPlayer.startSavedAudio(filePath: filePath)
        
        newAudioPlayer.updateMetadataTitle(libraryItem.title)
        newAudioPlayer.updateMetadataArtist(formatArtists(libraryItem.artists))
        if let artworkURL = artworkURL {
            newAudioPlayer.updateMetadataArtwork(
                url: artworkURL,
                thumbnailIsSquare: libraryItem.thumbnail_is_square
            )
        }
        // Apply audio parameters from the library item
        newAudioPlayer.setSpeedRate(libraryItem.speedRate)
        newAudioPlayer.setPitchByCents(libraryItem.pitchCents)
        newAudioPlayer.setReverbMix(libraryItem.reverbMix)
        
        self.audioPlayer = newAudioPlayer

        let scrobbleSeed = makeScrobbleSeed(from: libraryItem)
        Task {
            await scrobbleCoordinator.startTrack(
                seed: scrobbleSeed,
                duration: newAudioPlayer.duration
            )
        }

        monitorAudioPlayerChanges(for: newAudioPlayer, libraryItem: libraryItem)
        
        open()
    }

    private func monitorAudioPlayerChanges(for audioPlayer: AudioPlayerWithReverb, libraryItem: LibraryItem) {
        audioPlayerCancellables.removeAll()

        debugPrint("Monitoring audio player changes for library item: \(libraryItem.title)")

        // monitor changes to `duration`
        audioPlayer.playback.$duration
            .sink { [weak self] duration in
                guard let self = self else { return }
                Task {
                    await self.scrobbleCoordinator.updateDuration(duration)
                }
            }
            .store(in: &audioPlayerCancellables)

        // monitor changes to `currentTime` and `isPlaying`
        Publishers.CombineLatest(audioPlayer.timeline.$currentTime, audioPlayer.playback.$isPlaying)
            .sink { [weak self] currentTime, isPlaying in
                self?.handleScrobbleProgress(currentTime: currentTime, isPlaying: isPlaying)
            }
            .store(in: &audioPlayerCancellables)
    }

    private func handleScrobbleProgress(currentTime: Double, isPlaying: Bool) {
        let isAuthenticated = lastFM?.isAuthenticated ?? false
        let isScrobblingEnabled = lastFM?.isScrobblingEnabled ?? false
        let isTrackScrobblingEnabled = !(libraryItem?.isScrobblingOptedOut ?? false)
        let manager = lastFM?.manager

        Task {
            await scrobbleCoordinator.handleProgress(
                currentTime: currentTime,
                isPlaying: isPlaying,
                isAuthenticated: isAuthenticated,
                isScrobblingEnabled: isScrobblingEnabled,
                isTrackScrobblingEnabled: isTrackScrobblingEnabled,
                manager: manager
            )
        }
    }

    private func makeScrobbleSeed(from libraryItem: LibraryItem) -> ScrobbleSeed {
        let trimmedScrobbleTitle = libraryItem.scrobbleTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (trimmedScrobbleTitle?.isEmpty == false) ? trimmedScrobbleTitle! : libraryItem.title
        
        return ScrobbleSeed(
            title: title,
            artist: libraryItem.artists.first,
            album: nil
        )
    }

    func updateScrobbleSeed(for libraryItem: LibraryItem) {
        let scrobbleSeed = makeScrobbleSeed(from: libraryItem)
        Task {
            await scrobbleCoordinator.updateSeed(scrobbleSeed)
        }
    }
}
