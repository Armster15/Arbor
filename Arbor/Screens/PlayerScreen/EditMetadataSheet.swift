//
//  EditMetadataSheet.swift
//  Arbor
//
//  Created by Armaan Aggarwal on 1/10/26.
//

import SwiftUI

struct EditMetadataSheet: View {
    @EnvironmentObject var player: PlayerCoordinator
    @EnvironmentObject var lastFM: LastFMSession
    @Bindable var libraryItem: LibraryItem
    @ObservedObject var audioPlayer: AudioPlayerWithReverb
    @Environment(\.colorScheme) private var colorScheme
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

    private var shouldShowScrobbleMenu: Bool {
        lastFM.isAuthenticated && lastFM.isScrobblingEnabled && lastFM.manager != nil
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
                        VStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Title")
                                .fontWeight(.semibold)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color("PrimaryText"))

                            HStack(alignment: .center, spacing: 12) {
                                TextField("Title", text: $draftTitle)
                                    .textContentType(nil)
                                    .textInputAutocapitalization(.words)
                                    .disableAutocorrection(true)
                                    .keyboardType(.default)
                                    .padding(12)
                                    .background(colorScheme == .light ? Color("Elevated") : Color.clear)
                                    .glassEffect()
                                    .cornerRadius(24)
                                    .foregroundStyle(Color("PrimaryText"))
                                    .tint(Color("PrimaryText"))

                                if shouldShowScrobbleMenu {
                                    Menu {
                                        Button {
                                            isScrobbleTitleOverridden.toggle()
                                        } label: {
                                            if isScrobbleTitleOverridden {
                                                Label("Override scrobble title", systemImage: "checkmark")
                                            } else {
                                                Text("Override scrobble title")
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(Color("PrimaryText"))
                                            .frame(width: 32, height: 44, alignment: .center)
                                            .contentShape(Rectangle())
                                    }
                                    .accessibilityLabel("Title options")
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                        if isScrobbleTitleOverridden {
                            LabeledTextField(
                                label: "Scrobble title",
                                    placeholder: "Scrobble title",
                                    text: $draftScrobbleTitle,
                                    isSecure: false,
                                    textContentType: nil,
                                    keyboardType: .default,
                                    autocapitalization: .words,
                                    disableAutocorrection: true
                                )
                            }
                        }

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
