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

enum LyricsTranslationState {
    case idle
    case loading(LyricsTranslationRequest)
    case loaded(request: LyricsTranslationRequest, payload: LyricsTranslationPayload)

    func payload(for source: LyricsPayload) -> LyricsTranslationPayload? {
        guard case .loaded(let request, let payload) = self,
              request.payload == source else { return nil }
        return payload
    }

    var isLoading: Bool {
        guard case .loading = self else { return false }
        return true
    }

    var request: LyricsTranslationRequest? {
        guard case .loading(let request) = self else { return nil }
        return request
    }

    var taskId: UUID? {
        request?.id
    }
}

struct LyricsTranslationRequest {
    let id = UUID()
    let originalUrl: String
    let payload: LyricsPayload
}

public struct LyricsView: View {
    let payload: LyricsPayload
    let audioPlayer: AudioPlayerWithReverb
    let playback: AudioPlaybackState
    let timeline: AudioTimelineState
    let translationPayload: LyricsTranslationPayload?
    let isTranslatingLyrics: Bool
    let lyricsDisplayMode: LyricsDisplayMode
    let onSelectMode: (LyricsDisplayMode) -> Void
    let onExpand: () -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LyricsHeaderView(
                isTranslatingLyrics: isTranslatingLyrics,
                lyricsDisplayMode: lyricsDisplayMode,
                lyricsSource: payload.source,
                showsExpand: true,
                onExpand: onExpand,
                onSelect: onSelectMode
            )

            LyricsLinesView(
                payload: payload,
                audioPlayer: audioPlayer,
                playback: playback,
                timeline: timeline,
                lyricsDisplayMode: lyricsDisplayMode,
                romanizedLyricLines: translationPayload?.romanizations,
                translatedLyricLines: translationPayload?.translations,
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
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color("SecondaryBg"))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

private struct TranslationFailureAlertModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var logText: String?

    @State private var showLogSheet = false

    func body(content: Content) -> some View {
        content
            .alert("Translation Failed", isPresented: $isPresented) {
                if logText?.isEmpty == false {
                    Button("View Logs") {
                        showLogSheet = true
                    }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text("Failed to translate lyrics. Please try again.")
            }
            .sheet(isPresented: $showLogSheet) {
                NavigationStack {
                    LogViewer(
                        title: "View Logs",
                        logText: logText,
                        showClose: true
                    )
                }
            }
    }
}

private extension View {
    func translationFailureAlert(
        isPresented: Binding<Bool>,
        logText: Binding<String?>
    ) -> some View {
        modifier(
            TranslationFailureAlertModifier(
                isPresented: isPresented,
                logText: logText
            )
        )
    }
}

struct LyricsPresentationView: View {
    let payload: LyricsPayload
    let audioPlayer: AudioPlayerWithReverb
    let title: String
    let artistSummary: String
    let originalUrl: String
    @Binding var lyricsDisplayMode: LyricsDisplayMode

    @State private var translationState = LyricsTranslationState.idle
    @State private var isFullScreenPresented = false
    @State private var showTranslationErrorAlert = false
    @State private var translationLogText: String?

    private var compactFailureAlertBinding: Binding<Bool> {
        Binding(
            get: {
                !isFullScreenPresented && showTranslationErrorAlert
            },
            set: { isPresented in
                guard !isFullScreenPresented else { return }
                showTranslationErrorAlert = isPresented
            }
        )
    }

    private func selectMode(_ mode: LyricsDisplayMode) {
        lyricsDisplayMode = mode
        translateIfNeeded(for: mode)
    }

    private func translateIfNeeded(for mode: LyricsDisplayMode) {
        guard mode != .original else { return }
        guard case .idle = translationState else { return }

        showTranslationErrorAlert = false
        translationLogText = nil

        translationState = .loading(
            LyricsTranslationRequest(
                originalUrl: originalUrl,
                payload: payload
            )
        )
    }

    private static func translate(
        _ request: LyricsTranslationRequest
    ) async -> LyricsTranslationResult {
        await withCheckedContinuation { continuation in
            LyricsCache.shared.translateLyrics(
                originalUrl: request.originalUrl,
                payload: request.payload,
                completion: { continuation.resume(returning: $0) }
            )
        }
    }

    private func resetTranslation() {
        translationState = .idle
        lyricsDisplayMode = .original
        isFullScreenPresented = false
        showTranslationErrorAlert = false
        translationLogText = nil
    }

    var body: some View {
        LyricsView(
            payload: payload,
            audioPlayer: audioPlayer,
            playback: audioPlayer.playback,
            timeline: audioPlayer.timeline,
            translationPayload: translationState.payload(for: payload),
            isTranslatingLyrics: translationState.isLoading,
            lyricsDisplayMode: lyricsDisplayMode,
            onSelectMode: selectMode,
            onExpand: { isFullScreenPresented = true }
        )
        .onAppear {
            translateIfNeeded(for: lyricsDisplayMode)
        }
        .onChange(of: payload) { _, _ in
            resetTranslation()
        }
        .task(id: translationState.taskId) { [request = translationState.request] in
            guard let request else { return }
            let result = await Self.translate(request)
            guard !Task.isCancelled,
                  request.id == translationState.request?.id else { return }

            switch result {
            case .loaded(let payload):
                translationState = .loaded(request: request, payload: payload)
            case .failed(let log):
                translationState = .idle
                lyricsDisplayMode = .original
                translationLogText = log
                showTranslationErrorAlert = true
            }
        }
        .translationFailureAlert(
            isPresented: compactFailureAlertBinding,
            logText: $translationLogText
        )
        .fullScreenCover(isPresented: $isFullScreenPresented) {
            FullScreenLyricsView(
                payload: payload,
                audioPlayer: audioPlayer,
                playback: audioPlayer.playback,
                timeline: audioPlayer.timeline,
                translationState: $translationState,
                title: title,
                artistSummary: artistSummary,
                lyricsDisplayMode: $lyricsDisplayMode,
                onSelectMode: selectMode
            )
            .translationFailureAlert(
                isPresented: $showTranslationErrorAlert,
                logText: $translationLogText
            )
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
    let audioPlayer: AudioPlayerWithReverb
    @ObservedObject var playback: AudioPlaybackState
    @ObservedObject var timeline: AudioTimelineState
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
        guard let activeIndex else {
            scrollToTop(proxy, shouldAnimate: shouldAnimate)
            return
        }
        lastActiveLyricIndex = activeIndex
        if shouldAnimate {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo(activeIndex, anchor: .center)
            }
        } else {
            proxy.scrollTo(activeIndex, anchor: .center)
        }
    }

    private func scrollToTop(_ proxy: ScrollViewProxy, shouldAnimate: Bool) {
        guard !payload.lines.isEmpty else { return }
        lastActiveLyricIndex = 0
        if shouldAnimate {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo(0, anchor: .top)
            }
        } else {
            proxy.scrollTo(0, anchor: .top)
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
        let currentMs = Int(timeline.currentTime * 1000)
        let shouldShowActive = payload.timed
            && (currentMs > 0 || playback.isPlaying || lastPlaybackTimeMs != nil)
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
            .onChange(of: timeline.currentTime) { _, newValue in
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
    let playback: AudioPlaybackState
    let timeline: AudioTimelineState
    @Binding var translationState: LyricsTranslationState
    let title: String
    let artistSummary: String
    @Binding var lyricsDisplayMode: LyricsDisplayMode
    let onSelectMode: (LyricsDisplayMode) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isAutoScrollEnabled: Bool = true

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
                    playback: playback,
                    timeline: timeline,
                    lyricsDisplayMode: lyricsDisplayMode,
                    romanizedLyricLines: translationState.payload(for: payload)?.romanizations,
                    translatedLyricLines: translationState.payload(for: payload)?.translations,
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
                        isTranslatingLyrics: translationState.isLoading,
                        lyricsSource: payload.source,
                        onSync: { isAutoScrollEnabled = true },
                        onSelectMode: onSelectMode
                    )
                    .equatable()

                    FullScreenLyricsPlaybackControls(
                        audioPlayer: audioPlayer,
                        playback: playback,
                        timeline: timeline
                    )
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
    }
}

private struct FullScreenLyricsPlaybackControls: View {
    let audioPlayer: AudioPlayerWithReverb
    @ObservedObject var playback: AudioPlaybackState
    @ObservedObject var timeline: AudioTimelineState

    @State private var isScrubbing: Bool = false
    @State private var scrubberTime: Double = 0

    var body: some View {
        VStack(spacing: 18) {
            Scrubber(
                value: $scrubberTime,
                inRange: 0...max(playback.duration, 0.01),
                activeFillColor: Color("PrimaryBg"),
                fillColor: Color("PrimaryBg").opacity(0.8),
                emptyColor: Color("PrimaryBg").opacity(0.2),
                height: 28,
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if editing {
                        scrubberTime = timeline.currentTime
                    }
                    if !editing {
                        audioPlayer.seek(to: scrubberTime)
                    }
                }
            )
            .onChange(of: timeline.currentTime) { _, newValue in
                guard !isScrubbing else { return }
                scrubberTime = newValue
            }
            .onAppear {
                scrubberTime = timeline.currentTime
            }

            Button(action: {
                if playback.isPlaying {
                    audioPlayer.pause()
                } else {
                    audioPlayer.play()
                }
            }) {
                Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 56))
                    .foregroundColor(Color("PrimaryBg"))
            }
            .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
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
