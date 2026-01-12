//
//  EditMetadataSheet.swift
//  Arbor
//
//  Created by Armaan Aggarwal on 1/10/26.
//

import SwiftUI

struct EditMetadataSheet: View {
    @EnvironmentObject var player: PlayerCoordinator
    @Bindable var libraryItem: LibraryItem
    @ObservedObject var audioPlayer: AudioPlayerWithReverb
    let onLyricsInvalidated: () -> Void
    @Binding var isPresented: Bool

    @State private var draftTitle: String = ""
    @State private var draftScrobbleTitle: String = ""
    @State private var draftArtists: [String] = []
    @State private var editSheetHeight: CGFloat = 0
    @State private var editSheetContentHeight: CGFloat = 0
    @State private var editSheetButtonHeight: CGFloat = 0
    @State private var hasInitialized: Bool = false
    @State private var isScrobbleTitleOverridden: Bool = false

    private struct SheetHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0

        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    private struct SheetButtonHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0

        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    private var editSheetDetentHeight: CGFloat {
        let maxSheetHeight = UIScreen.main.bounds.height * 0.9
        let targetHeight = editSheetContentHeight + editSheetButtonHeight
        return min(max(targetHeight, 280), maxSheetHeight)
    }

    private func initializeDraftsIfNeeded() {
        guard !hasInitialized else { return }
        draftTitle = libraryItem.title
        draftScrobbleTitle = libraryItem.scrobbleTitle ?? ""
        isScrobbleTitleOverridden = libraryItem.scrobbleTitle != nil
        draftArtists = libraryItem.artists
        hasInitialized = true
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 32) {
                    Text("Edit Metadata")
                        .font(.headline)
                        .padding(.top, 24)

                    VStack(spacing: 24) {
                        LabeledTextField(
                            label: "Title",
                            placeholder: "Title",
                            text: $draftTitle,
                            isSecure: false,
                            textContentType: nil,
                            keyboardType: .default,
                            autocapitalization: .words,
                            disableAutocorrection: true
                        )

                        VStack(spacing: 12) {
                            ForEach(draftArtists.indices, id: \.self) { index in
                                HStack(alignment: .bottom) {
                                    LabeledTextField(
                                        label: "Artist \(index + 1)",
                                        placeholder: "Artist name",
                                        text: Binding(
                                            get: { draftArtists[index] },
                                            set: { draftArtists[index] = $0 }
                                        ),
                                        isSecure: false,
                                        textContentType: nil,
                                        keyboardType: .default,
                                        autocapitalization: .words,
                                        disableAutocorrection: true,
                                        horizontalPadding: 0
                                    )

                                    Button {
                                        draftArtists.remove(at: index)
                                        if draftArtists.isEmpty {
                                            draftArtists = [""]
                                        }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.title3)
                                            .tint(Color("PrimaryBg"))
                                    }
                                    .accessibilityLabel("Remove artist")
                                    .padding(.horizontal, 6)
                                    .padding(.bottom, 12)
                                }
                                .padding(.horizontal)
                            }

                            Button {
                                draftArtists.append("")
                                DispatchQueue.main.async {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        proxy.scrollTo("editSheetBottom", anchor: .bottom)
                                    }
                                }
                            } label: {
                                Label("Add Artist", systemImage: "plus.circle.fill")
                            }
                            .buttonStyle(.bordered)
                            .tint(Color("PrimaryBg"))
                            .padding(.top, 12)
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("editSheetBottom")
                }
                .padding(.bottom, 24)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: SheetHeightKey.self, value: proxy.size.height)
                    }
                )
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PrimaryActionButton(
                title: "Save",
                isLoading: false,
                isDisabled: false,
                action: {
                    let previousTitle = libraryItem.title
                    let previousArtists = libraryItem.artists
                    let trimmedArtists = draftArtists
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    let trimmedScrobbleTitle = draftScrobbleTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    let nextTitle = draftTitle
                    let nextArtists = trimmedArtists
                    let nextScrobbleTitle = isScrobbleTitleOverridden && !trimmedScrobbleTitle.isEmpty
                        ? trimmedScrobbleTitle
                        : nil

                    libraryItem.title = nextTitle
                    libraryItem.scrobbleTitle = nextScrobbleTitle
                    libraryItem.artists = trimmedArtists

                    audioPlayer.updateMetadataTitle(decoratedTitle(for: libraryItem, audioPlayer: audioPlayer))
                    audioPlayer.updateMetadataArtist(formatArtists(libraryItem.artists))
                    player.updateScrobbleSeed(for: libraryItem)

                    if previousTitle != nextTitle || previousArtists != nextArtists {
                        LyricsCache.shared.clearLyrics(originalURL: libraryItem.original_url)
                        onLyricsInvalidated()
                    }

                    isPresented = false
                }
            )
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: SheetButtonHeightKey.self, value: proxy.size.height)
                }
            )
        }
        .onAppear {
            initializeDraftsIfNeeded()
        }
        .onPreferenceChange(SheetHeightKey.self) { newValue in
            if newValue > 0 {
                editSheetContentHeight = newValue
                editSheetHeight = editSheetDetentHeight
            }
        }
        .onPreferenceChange(SheetButtonHeightKey.self) { newValue in
            if newValue > 0 {
                editSheetButtonHeight = newValue
                editSheetHeight = editSheetDetentHeight
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .presentationDetents([.height(max(editSheetHeight, 280)), .large])
        .presentationBackground(BackgroundColor)
        .presentationDragIndicator(.visible)
    }
}
