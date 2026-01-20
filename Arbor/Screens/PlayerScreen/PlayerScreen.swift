//
//  PlayerView.swift
//  pytest
//

import SwiftUI
import Foundation
import SwiftData
import SDWebImage
import SDWebImageSwiftUI

// this is so we can provide the actual PlayerScreen (__PlayerScreen)
// with non-nullable values for libraryItem, audioPlayer, and filePath
struct PlayerScreen: View {
    @EnvironmentObject var player: PlayerCoordinator
        
    var body: some View {
        Group {
            if let libraryItem = player.libraryItem,
               let audioPlayer = player.audioPlayer,
               let filePath = player.filePath {
                __PlayerScreen(
                    libraryItem: libraryItem,
                    audioPlayer: audioPlayer,
                    filePath: Binding(
                        get: { filePath },
                        set: { player.filePath = $0 }
                    ),
                    lyricsDisplayMode: $player.lyricsDisplayMode
                )
            } else {
                EmptyView()
            }
        }
    }
}

func decoratedTitle(for libraryItem: LibraryItem, audioPlayer: AudioPlayerWithReverb) -> String {
    var tags: [String] = []
    if audioPlayer.speedRate > 1.0 {
        tags.append("sped up")
    } else if audioPlayer.speedRate < 1.0 {
        tags.append("slowed")
    }
    if audioPlayer.reverbMix > 0.0 {
        tags.append("reverb")
    }
    guard !tags.isEmpty else { return libraryItem.title }
    return "\(libraryItem.title) (\(tags.joined(separator: " + ")))"
}

struct __PlayerScreen: View {
    @Bindable var libraryItem: LibraryItem
    let audioPlayer: AudioPlayerWithReverb
    @Binding var filePath: String
    @Binding var lyricsDisplayMode: LyricsDisplayMode
    
    @State private var isEditSheetPresented: Bool = false
    @State private var lyricsState: LyricsState = .idle
    @State private var currentLyricsTaskId: UUID?
    @State private var isLyricsFullScreenPresented: Bool = false
    @State private var activeLyricsPayload: LyricsPayload?
    
    // Track last saved settings locally (not persisted to iCloud)
    @State private var savedSpeedRate: Float?
    @State private var savedPitchCents: Float?
    @State private var savedReverbMix: Float?

    @Environment(\.modelContext) var modelContext

    private enum LyricsState: Equatable {
        case idle
        case loading
        case loaded(LyricsPayload)
        case empty
        case failed
    }

    private var isDownloaded: Bool {
        getLocalAudioFilePath(originalUrl: libraryItem.original_url) != nil
    }
    
    init(
        libraryItem: LibraryItem,
        audioPlayer: AudioPlayerWithReverb,
        filePath: Binding<String>,
        lyricsDisplayMode: Binding<LyricsDisplayMode>
    ) {
        self.libraryItem = libraryItem
        self.audioPlayer = audioPlayer
        self._filePath = filePath
        self._lyricsDisplayMode = lyricsDisplayMode
    }

    private func fetchLyricsIfNeeded() {
        let taskId = UUID()
        currentLyricsTaskId = taskId
        lyricsState = .loading

        LyricsCache.shared.fetchLyrics(
            originalUrl: libraryItem.original_url,
            title: libraryItem.title,
            artists: libraryItem.artists
        ) { result in
            guard taskId == currentLyricsTaskId else { return }

            switch result {
            case .loaded(let payload):
                lyricsState = .loaded(payload)
            case .empty:
                lyricsState = .empty
            case .failed:
                lyricsState = .failed
            }
        }
    }

    private var lyricsSection: some View {
        Group {
            if case .loaded(let payload) = lyricsState, !payload.lines.isEmpty {
                LyricsView(
                    payload: payload,
                    audioPlayer: audioPlayer,
                    originalUrl: libraryItem.original_url,
                    lyricsDisplayMode: $lyricsDisplayMode,
                    onExpand: {
                        activeLyricsPayload = payload
                        isLyricsFullScreenPresented = true
                    }
                )
            }
        }
        .animation(.easeOut(duration: 0.35), value: lyricsState)
    }
    
    private func saveToLibrary() {
        let SHOULD_COPY = true

        // if SHOULD_COPY is true, it will save a new library item
        // else if false it will edit the existing library item
        let item = SHOULD_COPY ? LibraryItem(copyOf: libraryItem) : libraryItem
        
        item.speedRate = audioPlayer.speedRate
        item.pitchCents = audioPlayer.pitchCents
        item.reverbMix = audioPlayer.reverbMix
        
        let originalUrl = item.original_url
        
        let absolutePath = ensureLocalAudioFile(
            originalUrl: originalUrl,
            sourcePath: filePath,
            title: item.title,
            artists: item.artists,
            onMissingPhysicalFile: {
                debugPrint("Deleting outdated library item: \(item.title)")
                modelContext.delete(item)
            }
        )
        
        self.filePath = absolutePath
        
        if SHOULD_COPY {
            modelContext.insert(item)
        }
        
        // Track saved settings locally so isModified reflects the saved state
        savedSpeedRate = audioPlayer.speedRate
        savedPitchCents = audioPlayer.pitchCents
        savedReverbMix = audioPlayer.reverbMix
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                VStack(spacing: 20) {
                    SongInfo(
                        title: libraryItem.title,
                        artists: libraryItem.artists,
                        thumbnailURL: libraryItem.thumbnail_url,
                        thumbnailIsSquare: libraryItem.thumbnail_is_square,
                        thumbnailForceSquare: false,
                        thumbnailHasContextMenu: true
                    )
                    
                    PlayerControlsSection(audioPlayer: audioPlayer)
                }
                
                PlayerAdjustmentsSection(audioPlayer: audioPlayer)
                lyricsSection
                PlayerMetadataSyncView(libraryItem: libraryItem, audioPlayer: audioPlayer)
            }
            .padding()
        }
        .toolbar {
            PlayerToolbar(
                audioPlayer: audioPlayer,
                isDownloaded: isDownloaded,
                libraryItemSpeedRate: libraryItem.speedRate,
                libraryItemPitchCents: libraryItem.pitchCents,
                libraryItemReverbMix: libraryItem.reverbMix,
                savedSpeedRate: savedSpeedRate,
                savedPitchCents: savedPitchCents,
                savedReverbMix: savedReverbMix,
                onSave: { saveToLibrary() },
                onEdit: { isEditSheetPresented = true }
            )
        }
        .task(id: libraryItem.original_url) {
            lyricsState = .idle
            fetchLyricsIfNeeded()
        }
        .background(
            EditMetadataSheet(
                libraryItem: libraryItem,
                audioPlayer: audioPlayer,
                onLyricsInvalidated: { fetchLyricsIfNeeded() },
                isPresented: $isEditSheetPresented
            )
        )
        .fullScreenCover(isPresented: $isLyricsFullScreenPresented, onDismiss: {
            activeLyricsPayload = nil
        }) {
            if let activeLyricsPayload {
                FullScreenLyricsView(
                    payload: activeLyricsPayload,
                    audioPlayer: audioPlayer,
                    title: libraryItem.title,
                    artistSummary: libraryItem.artists.joined(separator: ", "),
                    originalUrl: libraryItem.original_url,
                    lyricsDisplayMode: $lyricsDisplayMode
                )
            }
        }
    }
}

private struct PlayerControlsSection: View {
    @ObservedObject var audioPlayer: AudioPlayerWithReverb

    @State private var isScrubbing: Bool = false
    @State private var scrubberTime: Double = 0

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                HStack(spacing: 16) {
                    Button(action: {
                        audioPlayer.seek(to: 0)
                    }) {
                        Image(systemName: "backward.end.circle.fill")
                            .font(.system(size: 44))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(
                                Color("PrimaryText"),
                                Color("SecondaryBg")
                            )
                    }

                    Button(action: {
                        if audioPlayer.isPlaying {
                            audioPlayer.pause()
                        } else {
                            audioPlayer.play()
                        }
                    }) {
                        Image(
                            systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill"
                        )
                        .font(.system(size: 56))
                        .foregroundColor(Color("PrimaryBg"))
                    }

                    Button(action: {
                        audioPlayer.stop()
                    }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(
                                Color("PrimaryText"),
                                Color("SecondaryBg")
                            )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                HStack {
                    Spacer()

                    Button(action: {
                        audioPlayer.toggleLoop()
                    }) {
                        Image(
                            systemName: audioPlayer.isLooping ? "repeat.1.circle.fill" : "repeat.circle.fill"
                        )
                        .font(.system(size: 40))
                        .foregroundStyle(
                            Color("PrimaryText").opacity(0.8),
                            .clear
                        )
                        .accessibilityLabel(
                            audioPlayer.isLooping ? "Disable Loop" : "Enable Loop"
                        )
                    }
                }
            }

            Scrubber(
                value: $scrubberTime,
                inRange: 0...max(audioPlayer.duration, 0.01),
                activeFillColor: Color("PrimaryBg"),
                fillColor: Color("PrimaryBg").opacity(0.8),
                emptyColor: Color("PrimaryBg").opacity(0.2),
                height: 30,
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if editing {
                        scrubberTime = audioPlayer.currentTime
                    }
                    if !editing {
                        audioPlayer.seek(to: scrubberTime)
                    }
                }
            )
            .onChange(of: audioPlayer.currentTime) { _, newValue in
                guard !isScrubbing else { return }
                scrubberTime = newValue
            }
            .onAppear {
                scrubberTime = audioPlayer.currentTime
            }
        }
    }
}

private struct PlayerAdjustmentsSection: View {
    @ObservedObject var audioPlayer: AudioPlayerWithReverb

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Speed")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(Color("PrimaryText"))

                    Button("Reset") {
                        audioPlayer.setSpeedRate(1.0)
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .tint(Color("PrimaryBg"))
                    .opacity(audioPlayer.speedRate == 1.0 ? 0 : 1)

                    Spacer()

                    Text(String(format: "%.2fx", audioPlayer.speedRate))
                        .font(.subheadline)
                        .foregroundColor(Color("PrimaryBg"))
                }

                HStack {
                    Slider(
                        value: Binding(
                            get: {
                                Double(audioPlayer.speedRate)
                            },
                            set: { newVal in
                                let snapped = (newVal / 0.05).rounded() * 0.05
                                audioPlayer.setSpeedRate(Float(snapped))
                            }
                        ),
                        in: 0.25...2.0,
                        step: 0.05
                    )
                    .accentColor(Color("PrimaryBg"))
                    .frame(maxWidth: .infinity)

                    Stepper(
                        value: Binding(
                            get: {
                                Double(audioPlayer.speedRate)
                            },
                            set: { newVal in
                                audioPlayer.setSpeedRate(Float(newVal))
                            }
                        ),
                        in: 0.25...2.0,
                        step: 0.01,
                    ) {}
                    .fixedSize()
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Pitch")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(Color("PrimaryText"))

                    Button("Reset") {
                        audioPlayer.setPitchByCents(0.0)
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .tint(Color("PrimaryBg"))
                    .opacity(audioPlayer.pitchCents.isZero ? 0 : 1)

                    Spacer()

                    Text("\(Int(audioPlayer.pitchCents)) cents")
                        .font(.subheadline)
                        .foregroundColor(Color("PrimaryBg"))
                }

                HStack {
                    Slider(
                        value: Binding(
                            get: {
                                Double(audioPlayer.pitchCents)
                            },
                            set: { newVal in
                                let snapped = (newVal / 50.0).rounded() * 50.0
                                audioPlayer.setPitchByCents(Float(snapped))
                            }
                        ),
                        in: -800.0...800.0,
                        step: 50
                    )
                    .accentColor(Color("PrimaryBg"))
                    .frame(maxWidth: .infinity)

                    Stepper(
                        value: Binding(
                            get: {
                                Double(audioPlayer.pitchCents)
                            },
                            set: { newVal in
                                audioPlayer.setPitchByCents(Float(newVal))
                            }
                        ),
                        in: -800.0...800.0,
                        step: 10,
                    ) {}
                    .fixedSize()
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Reverb")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(Color("PrimaryText"))

                    Button("Reset") {
                        audioPlayer.setReverbMix(0.0)
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .tint(Color("PrimaryBg"))
                    .opacity(audioPlayer.reverbMix > 0 ? 1 : 0)

                    Spacer()

                    Text("\(Int(audioPlayer.reverbMix))%")
                        .font(.subheadline)
                        .foregroundColor(Color("PrimaryBg"))
                }

                HStack {
                    Slider(
                        value: Binding(
                            get: {
                                Double(audioPlayer.reverbMix)
                            },
                            set: { newVal in
                                let snapped = (newVal / 5.0).rounded() * 5.0
                                audioPlayer.setReverbMix(Float(snapped))
                            }
                        ),
                        in: 0.0...100.0,
                        step: 5
                    )
                    .accentColor(Color("PrimaryBg"))
                    .frame(maxWidth: .infinity)

                    Stepper(
                        value: Binding(
                            get: {
                                Double(audioPlayer.reverbMix)
                            },
                            set: { newVal in
                                audioPlayer.setReverbMix(Float(newVal))
                            }
                        ),
                        in: 0.0...100.0,
                        step: 1,
                    ) {}
                    .fixedSize()
                }
            }
        }
    }
}

private struct PlayerToolbar: ToolbarContent {
    @ObservedObject var audioPlayer: AudioPlayerWithReverb
    let isDownloaded: Bool
    let libraryItemSpeedRate: Float
    let libraryItemPitchCents: Float
    let libraryItemReverbMix: Float
    let savedSpeedRate: Float?
    let savedPitchCents: Float?
    let savedReverbMix: Float?
    let onSave: () -> Void
    let onEdit: () -> Void

    private var isModified: Bool {
        let refSpeed = savedSpeedRate ?? libraryItemSpeedRate
        let refPitch = savedPitchCents ?? libraryItemPitchCents
        let refReverb = savedReverbMix ?? libraryItemReverbMix

        return audioPlayer.speedRate != refSpeed ||
            audioPlayer.pitchCents != refPitch ||
            audioPlayer.reverbMix != refReverb
    }

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                onSave()
            } label: {
                Label(
                    "Download",
                    systemImage: !isDownloaded ? "arrow.down.circle" :
                        isModified ? "arrow.down.circle.dotted" :
                        "checkmark.circle"
                )
            }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                onEdit()
            } label: {
                Label("Edit Metadata", systemImage: "pencil")
            }
        }
    }
}

private struct PlayerMetadataSyncView: View {
    let libraryItem: LibraryItem
    @ObservedObject var audioPlayer: AudioPlayerWithReverb

    var body: some View {
        EmptyView()
            .onChange(of: audioPlayer.speedRate) { _, _ in
                audioPlayer.updateMetadataTitle(decoratedTitle(for: libraryItem, audioPlayer: audioPlayer))
            }
            .onChange(of: audioPlayer.reverbMix) { _, _ in
                audioPlayer.updateMetadataTitle(decoratedTitle(for: libraryItem, audioPlayer: audioPlayer))
            }
    }
}


#Preview {
	NavigationStack {
		ZStack {
			BackgroundColor
				.ignoresSafeArea()
			
            __PlayerScreen(
                libraryItem: LibraryItem(
                    original_url: "https://www.youtube.com/watch?v=Sxu8wHE97Rk",
                    title: "Ude Dil Befikre (From \"Befikre\")",
                    artists: ["Vishal and Sheykhar", "Benny Dayal"],
                    thumbnail_url: "https://lh3.googleusercontent.com/viaCZKRr1hCygO8JQS6lLmhBqUVFXctO_9sOE7hwI-rS_JlYcCdqel9sAaGdQoFEFUR2R6ldsrr_c2L5=w544-h544-l90-rj",
                    thumbnail_width: 544,
                    thumbnail_height: 544,
                    thumbnail_is_square: true
                ),
				audioPlayer: AudioPlayerWithReverb(),
                filePath: Binding(
                    get: { "" },
                    set: { _ in }
                ),
                lyricsDisplayMode: .constant(.original)
			)
		}
	}
}
