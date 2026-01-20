//
//  LyricsView.swift
//  Arbor
//
//  Created by Armaan Aggarwal on 1/10/26.
//

import SwiftUI
import UIKit

public enum LyricsDisplayMode: String, CaseIterable {
    case original = "Original"
    case romanized = "Romanized"
    case translated = "Translated"
}

public struct LyricsView: View {
    let payload: LyricsPayload
    @ObservedObject var audioPlayer: AudioPlayerWithReverb
    let originalUrl: String
    @Binding var lyricsDisplayMode: LyricsDisplayMode
    let onExpand: () -> Void

    @State private var romanizedLyricLines: [String]?
    @State private var translatedLyricLines: [String]?
    @State private var isTranslatingLyrics: Bool = false
    @State private var currentTranslateTaskId: UUID?

    private func translateLyrics() {
        guard !isTranslatingLyrics else { return }
        isTranslatingLyrics = true
        let taskId = UUID()
        currentTranslateTaskId = taskId
        LyricsCache.shared.translateLyrics(originalUrl: originalUrl, payload: payload) { result in
            guard taskId == currentTranslateTaskId else { return }
            isTranslatingLyrics = false

            switch result {
            case .loaded(let translationPayload):
                romanizedLyricLines = translationPayload.romanizations
                translatedLyricLines = translationPayload.translations
            case .failed:
                break
            }
        }
    }

    private func resetTranslationState() {
        romanizedLyricLines = nil
        translatedLyricLines = nil
        lyricsDisplayMode = .original
        isTranslatingLyrics = false
        currentTranslateTaskId = nil
    }

    private func ensureTranslationIfNeeded(for mode: LyricsDisplayMode) {
        let needsTranslation = (mode == .romanized || mode == .translated)
            && (romanizedLyricLines == nil || translatedLyricLines == nil)
        if needsTranslation {
            DispatchQueue.main.async {
                translateLyrics()
            }
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LyricsHeaderView(
                isTranslatingLyrics: isTranslatingLyrics,
                lyricsDisplayMode: lyricsDisplayMode,
                lyricsSource: payload.source,
                showsExpand: true,
                onExpand: {
                    onExpand()
                }
            ) { mode in
                lyricsDisplayMode = mode
                ensureTranslationIfNeeded(for: mode)
            }

            LyricsLinesView(
                payload: payload,
                audioPlayer: audioPlayer,
                lyricsDisplayMode: lyricsDisplayMode,
                romanizedLyricLines: romanizedLyricLines,
                translatedLyricLines: translatedLyricLines,
                isAutoScrollEnabled: .constant(true),
                allowsUserScroll: false,
                timedLineFont: lyricUIFont(textStyle: .title3, weight: .semibold),
                untimedLineFont: lyricUIFont(textStyle: .title3, weight: .semibold),
                itemSpacing: 10,
                lineSpacing: 4,
                maxHeight: 260,
                seeksOnTap: false,
                onLineTap: { _, _ in
                    onExpand()
                }
            )
            .onChange(of: lyricsDisplayMode) { _, newValue in
                ensureTranslationIfNeeded(for: newValue)
            }
            .onChange(of: payload) { _, _ in
                resetTranslationState()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color("SecondaryBg"))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear {
            ensureTranslationIfNeeded(for: lyricsDisplayMode)
        }
    }
}

// Minimal UIKit label wrapper to fix SwiftUI Text horizontal scrolling bug
private struct UIKitLyricLabel: UIViewRepresentable {
    let text: String
    let font: UIFont
    let textColor: Color
    let isActive: Bool
    let onTap: () -> Void
    
    func makeUIView(context: Context) -> UILabel {
        let label = UIWrappingLabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.textAlignment = .left
        label.isUserInteractionEnabled = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        label.addGestureRecognizer(tapGesture)
        
        return label
    }
    
    func updateUIView(_ label: UILabel, context: Context) {
        label.text = text
        label.textColor = UIColor(textColor)
        label.font = font
        context.coordinator.onTap = onTap
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }
    
    class Coordinator: NSObject {
        var onTap: () -> Void
        
        init(onTap: @escaping () -> Void) {
            self.onTap = onTap
        }
        
        @objc func handleTap() {
            onTap()
        }
    }
    
}

private final class UIWrappingLabel: UILabel {
    override func layoutSubviews() {
        super.layoutSubviews()
        let targetWidth = bounds.width
        guard targetWidth > 0, preferredMaxLayoutWidth != targetWidth else { return }
        preferredMaxLayoutWidth = targetWidth
        invalidateIntrinsicContentSize()
    }
}

private func lyricUIFont(textStyle: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
    let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: textStyle)
    let baseFont = UIFont.systemFont(ofSize: descriptor.pointSize, weight: weight)
    return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: baseFont)
}

private struct LyricsLinesView: View {
    let payload: LyricsPayload
    @ObservedObject var audioPlayer: AudioPlayerWithReverb
    let lyricsDisplayMode: LyricsDisplayMode
    let romanizedLyricLines: [String]?
    let translatedLyricLines: [String]?
    @Binding var isAutoScrollEnabled: Bool
    let allowsUserScroll: Bool
    let timedLineFont: UIFont
    let untimedLineFont: UIFont
    let itemSpacing: CGFloat
    let lineSpacing: CGFloat
    let maxHeight: CGFloat?
    let seeksOnTap: Bool
    let onLineTap: (LyricsLine, Int) -> Void

    @State private var lastActiveLyricIndex: Int?
    @State private var lastPlaybackTimeMs: Int?
    @State private var pendingTapLyricIndex: Int?
    @State private var suppressAutoScrollUntil: Date?

    private func seekToLine(_ line: LyricsLine) {
        guard payload.timed, let startMs = line.startMs else { return }
        audioPlayer.seek(to: Double(startMs) / 1000.0)
    }

    private func shouldSuppressAutoScroll(for activeIndex: Int?) -> Bool {
        guard let suppressUntil = suppressAutoScrollUntil else { return false }
        if Date() > suppressUntil {
            suppressAutoScrollUntil = nil
            pendingTapLyricIndex = nil
            return false
        }
        if let tappedIndex = pendingTapLyricIndex, activeIndex == tappedIndex {
            suppressAutoScrollUntil = nil
            pendingTapLyricIndex = nil
            return false
        }
        return true
    }

    private func scrollToActiveLyric(
        _ proxy: ScrollViewProxy,
        activeIndex: Int?,
        shouldAnimate: Bool
    ) {
        guard let activeIndex else { return }
        lastActiveLyricIndex = activeIndex
        if shouldAnimate {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo(activeIndex, anchor: .center)
            }
        } else {
            proxy.scrollTo(activeIndex, anchor: .center)
        }
    }

    @ViewBuilder
    private func lyricsContent(
        selectedLyricLines: [String]?,
        activeIndex: Int?,
        proxy: ScrollViewProxy?
    ) -> some View {
        VStack(alignment: .leading, spacing: itemSpacing) {
            ForEach(payload.lines.indices, id: \.self) { index in
                let line = payload.lines[index]
                let isActive = payload.timed && index == activeIndex
                let displayText = selectedLyricLines?[index] ?? line.text
                UIKitLyricLabel(
                    text: displayText.isEmpty ? " " : displayText,
                    font: payload.timed ? timedLineFont : untimedLineFont,
                    textColor: payload.timed
                        ? (isActive ? Color("PrimaryText") : Color("PrimaryText").opacity(0.1))
                        : Color("PrimaryText"),
                    isActive: isActive,
                    onTap: {
                        onLineTap(line, index)
                        guard seeksOnTap else { return }
                        pendingTapLyricIndex = index
                        suppressAutoScrollUntil = Date().addingTimeInterval(0.5)
                        lastActiveLyricIndex = index
                        lastPlaybackTimeMs = line.startMs
                        isAutoScrollEnabled = true
                        seekToLine(line)
                        if let proxy {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(index, anchor: .center)
                            }
                        }
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(index)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lineSpacing(lineSpacing)
        .padding(.vertical, 8)
    }

    var body: some View {
        let currentMs = Int(audioPlayer.currentTime * 1000)
        let shouldShowActive = payload.timed
            && (currentMs > 0 || audioPlayer.isPlaying || lastPlaybackTimeMs != nil)
        let activeIndex = shouldShowActive
            ? LyricsCache.activeLyricIndex(for: payload, currentTimeMs: currentMs)
            : nil
        let selectedLyricLines: [String]? = {
            switch lyricsDisplayMode {
            case .original:
                return nil
            case .romanized:
                return romanizedLyricLines
            case .translated:
                return translatedLyricLines
            }
        }()

        return ScrollViewReader { proxy in
            ScrollView(.vertical) {
                lyricsContent(
                    selectedLyricLines: selectedLyricLines,
                    activeIndex: activeIndex,
                    proxy: proxy
                )
            }
            .frame(maxHeight: maxHeight)
            .scrollDisabled(!allowsUserScroll)
            .allowsHitTesting(allowsUserScroll)
            .scrollIndicators(.hidden)
            .onChange(of: activeIndex) { _, newValue in
                guard payload.timed, isAutoScrollEnabled else { return }
                guard !shouldSuppressAutoScroll(for: newValue) else { return }
                guard let newValue, newValue != lastActiveLyricIndex else { return }
                scrollToActiveLyric(proxy, activeIndex: newValue, shouldAnimate: true)
            }
            .onChange(of: audioPlayer.currentTime) { _, newValue in
                guard payload.timed, isAutoScrollEnabled else { return }
                guard !shouldSuppressAutoScroll(for: activeIndex) else { return }
                let newMs = Int(newValue * 1000)
                if let lastMs = lastPlaybackTimeMs {
                    let jumped = abs(newMs - lastMs) > 1500
                    if jumped {
                        let jumpedIndex = LyricsCache.activeLyricIndex(
                            for: payload,
                            currentTimeMs: newMs
                        )
                        if let jumpedIndex {
                            lastActiveLyricIndex = jumpedIndex
                        }
                        scrollToActiveLyric(proxy, activeIndex: jumpedIndex, shouldAnimate: false)
                    }
                    if newMs < lastMs && newMs < 500 {
                        lastActiveLyricIndex = 0
                        scrollToActiveLyric(proxy, activeIndex: 0, shouldAnimate: false)
                    }
                }
                lastPlaybackTimeMs = newMs
            }
            .onChange(of: lyricsDisplayMode) { _, _ in
                guard payload.timed, isAutoScrollEnabled else { return }
                DispatchQueue.main.async {
                    scrollToActiveLyric(proxy, activeIndex: activeIndex, shouldAnimate: false)
                }
            }
            .onChange(of: romanizedLyricLines) { _, _ in
                guard payload.timed, isAutoScrollEnabled else { return }
                DispatchQueue.main.async {
                    scrollToActiveLyric(proxy, activeIndex: activeIndex, shouldAnimate: false)
                }
            }
            .onChange(of: translatedLyricLines) { _, _ in
                guard payload.timed, isAutoScrollEnabled else { return }
                DispatchQueue.main.async {
                    scrollToActiveLyric(proxy, activeIndex: activeIndex, shouldAnimate: false)
                }
            }
            // scroll to the active lyric on appear (e.g. when player is reopened)
            .onAppear {
                guard payload.timed, isAutoScrollEnabled else { return }
                withAnimation(.none) {
                    scrollToActiveLyric(proxy, activeIndex: activeIndex, shouldAnimate: false)
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 2).onChanged { _ in
                    guard allowsUserScroll, payload.timed else { return }
                    isAutoScrollEnabled = false
                }
            )
            .onScrollPhaseChange { _, newPhase, _ in
                guard allowsUserScroll, payload.timed else { return }
                if newPhase == .interacting || newPhase == .tracking {
                    isAutoScrollEnabled = false
                }
            }
            .onChange(of: isAutoScrollEnabled) { _, newValue in
                guard payload.timed, newValue else { return }
                scrollToActiveLyric(proxy, activeIndex: activeIndex, shouldAnimate: true)
            }
        }
    }
}

private struct LyricsHeaderView: View, Equatable {
    let isTranslatingLyrics: Bool
    let lyricsDisplayMode: LyricsDisplayMode
    let lyricsSource: LyricsSource?
    let showsExpand: Bool
    let onExpand: () -> Void
    let onSelect: (LyricsDisplayMode) -> Void

    static func == (lhs: LyricsHeaderView, rhs: LyricsHeaderView) -> Bool {
        lhs.isTranslatingLyrics == rhs.isTranslatingLyrics
            && lhs.lyricsDisplayMode == rhs.lyricsDisplayMode
            && lhs.lyricsSource == rhs.lyricsSource
            && lhs.showsExpand == rhs.showsExpand
    }

    var body: some View {
        HStack {
            Text("Lyrics")
                .font(.headline)
                .foregroundColor(Color("PrimaryText"))

            Spacer()

            if isTranslatingLyrics {
                ProgressView()
                    .scaleEffect(0.7)
            }

            Menu {
                ForEach(LyricsDisplayMode.allCases, id: \.self) { mode in
                    Button {
                        onSelect(mode)
                    } label: {
                        if lyricsDisplayMode == mode {
                            Label(mode.rawValue, systemImage: "checkmark")
                        } else {
                            Text(mode.rawValue)
                        }
                    }
                }
                if let lyricsSource {
                    Divider()
                    Button {} label: {
                        Text("Source: \(lyricsSource.rawValue)")
                    }
                    .disabled(true)
                }
            } label: {
                Image(systemName: "translate")
                    .font(.callout)
                    .foregroundColor(lyricsDisplayMode != .original && !isTranslatingLyrics ? .blue : Color("PrimaryText"))
            }
            .disabled(isTranslatingLyrics)
            .padding(.horizontal, 6)

            if showsExpand {
                Button(action: onExpand) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.callout)
                        .foregroundColor(Color("PrimaryText"))
                }
                .accessibilityLabel("Open full screen lyrics")
                .padding(.horizontal, 6)
            }
        }
    }
}

public struct FullScreenLyricsView: View {
    let payload: LyricsPayload
    let audioPlayer: AudioPlayerWithReverb
    let title: String
    let artistSummary: String
    let originalUrl: String
    @Binding var lyricsDisplayMode: LyricsDisplayMode

    @Environment(\.dismiss) private var dismiss
    @State private var isAutoScrollEnabled: Bool = true
    @State private var romanizedLyricLines: [String]?
    @State private var translatedLyricLines: [String]?
    @State private var isTranslatingLyrics: Bool = false
    @State private var currentTranslateTaskId: UUID?

    private func translateLyricsIfNeeded() {
        guard !isTranslatingLyrics else { return }
        isTranslatingLyrics = true
        let taskId = UUID()
        currentTranslateTaskId = taskId
        LyricsCache.shared.translateLyrics(originalUrl: originalUrl, payload: payload) { result in
            guard taskId == currentTranslateTaskId else { return }
            isTranslatingLyrics = false

            switch result {
            case .loaded(let translationPayload):
                romanizedLyricLines = translationPayload.romanizations
                translatedLyricLines = translationPayload.translations
            case .failed:
                break
            }
        }
    }

    private func handleLyricsDisplayModeChange(_ mode: LyricsDisplayMode) {
        lyricsDisplayMode = mode
        ensureTranslationIfNeeded(for: mode)
    }

    private func ensureTranslationIfNeeded(for mode: LyricsDisplayMode) {
        let needsTranslation = (mode == .romanized || mode == .translated)
            && (romanizedLyricLines == nil || translatedLyricLines == nil)
        if needsTranslation {
            DispatchQueue.main.async {
                translateLyricsIfNeeded()
            }
        }
    }

    public var body: some View {
        ZStack {
            BackgroundColor
                .ignoresSafeArea()

            VStack(spacing: 24) {
                ZStack {
                    VStack(spacing: 2) {
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(Color("PrimaryText"))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(artistSummary)
                            .font(.caption)
                            .foregroundColor(Color("PrimaryText").opacity(0.7))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .padding(.horizontal, 52)

                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "chevron.down")
                                .font(.title2)
                                .foregroundColor(Color("PrimaryBg"))
                                .padding(8)
                        }
                        .accessibilityLabel("Close lyrics")

                        Spacer()
                    }
                }

                LyricsLinesView(
                    payload: payload,
                    audioPlayer: audioPlayer,
                    lyricsDisplayMode: lyricsDisplayMode,
                    romanizedLyricLines: romanizedLyricLines,
                    translatedLyricLines: translatedLyricLines,
                    isAutoScrollEnabled: $isAutoScrollEnabled,
                    allowsUserScroll: true,
                    timedLineFont: UIFont.systemFont(ofSize: 24, weight: .semibold),
                    untimedLineFont: UIFont.systemFont(ofSize: 24, weight: .semibold),
                    itemSpacing: 14,
                    lineSpacing: 6,
                    maxHeight: nil,
                    seeksOnTap: true,
                    onLineTap: { _, _ in }
                )

                VStack(spacing: 18) {
                    FullScreenLyricsFooterControls(
                        isAutoScrollEnabled: isAutoScrollEnabled,
                        lyricsDisplayMode: lyricsDisplayMode,
                        isTranslatingLyrics: isTranslatingLyrics,
                        lyricsSource: payload.source,
                        onSync: { isAutoScrollEnabled = true },
                        onSelectMode: { mode in
                            handleLyricsDisplayModeChange(mode)
                        }
                    )
                    .equatable()

                    FullScreenLyricsPlaybackControls(audioPlayer: audioPlayer)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .onChange(of: lyricsDisplayMode) { _, newValue in
            ensureTranslationIfNeeded(for: newValue)
        }
        .onAppear {
            ensureTranslationIfNeeded(for: lyricsDisplayMode)
        }
    }
}

private struct FullScreenLyricsPlaybackControls: View {
    @ObservedObject var audioPlayer: AudioPlayerWithReverb

    @State private var isScrubbing: Bool = false
    @State private var scrubberTime: Double = 0

    var body: some View {
        VStack(spacing: 18) {
            Scrubber(
                value: $scrubberTime,
                inRange: 0...max(audioPlayer.duration, 0.01),
                activeFillColor: Color("PrimaryBg"),
                fillColor: Color("PrimaryBg").opacity(0.8),
                emptyColor: Color("PrimaryBg").opacity(0.2),
                height: 28,
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

            Button(action: {
                if audioPlayer.isPlaying {
                    audioPlayer.pause()
                } else {
                    audioPlayer.play()
                }
            }) {
                Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 56))
                    .foregroundColor(Color("PrimaryBg"))
            }
            .accessibilityLabel(audioPlayer.isPlaying ? "Pause" : "Play")
        }
    }
}

private struct FullScreenLyricsFooterControls: View, Equatable {
    let isAutoScrollEnabled: Bool
    let lyricsDisplayMode: LyricsDisplayMode
    let isTranslatingLyrics: Bool
    let lyricsSource: LyricsSource?
    let onSync: () -> Void
    let onSelectMode: (LyricsDisplayMode) -> Void

    static func == (lhs: FullScreenLyricsFooterControls, rhs: FullScreenLyricsFooterControls) -> Bool {
        lhs.isAutoScrollEnabled == rhs.isAutoScrollEnabled
            && lhs.lyricsDisplayMode == rhs.lyricsDisplayMode
            && lhs.isTranslatingLyrics == rhs.isTranslatingLyrics
            && lhs.lyricsSource == rhs.lyricsSource
    }

    var body: some View {
        HStack {
            Button(action: {
                onSync()
            }) {
                Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.title2)
                    .foregroundColor(Color("PrimaryText").opacity(0.85))
            }
            .frame(width: 32, height: 32)
            .opacity(isAutoScrollEnabled ? 0 : 1)
            .allowsHitTesting(!isAutoScrollEnabled)
            .accessibilityLabel("Sync lyrics")
            .accessibilityHidden(isAutoScrollEnabled)

            Spacer()

            Menu {
                ForEach(LyricsDisplayMode.allCases, id: \.self) { mode in
                    Button {
                        onSelectMode(mode)
                    } label: {
                        if lyricsDisplayMode == mode {
                            Label(mode.rawValue, systemImage: "checkmark")
                        } else {
                            Text(mode.rawValue)
                        }
                    }
                }
                if let lyricsSource {
                    Divider()
                    Button {} label: {
                        Text("Source: \(lyricsSource.rawValue)")
                    }
                    .disabled(true)
                }
            } label: {
                if isTranslatingLyrics {
                    ProgressView()
                        .tint(Color("PrimaryText"))
                } else {
                    Image(systemName: "translate")
                        .font(.title2)
                        .foregroundColor(lyricsDisplayMode != .original ? .blue : Color("PrimaryText").opacity(0.85))
                }
            }
            .disabled(isTranslatingLyrics)
        }
    }
}
