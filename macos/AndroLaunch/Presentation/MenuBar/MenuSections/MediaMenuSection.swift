//
//  MediaMenuSection.swift
//  AndroLaunch
//
//  Now-playing row plus transport controls in the status menu. Owned by
//  phone-companion. Hidden when nothing is playing, so the menu stays quiet.
//
//  Transport is best-effort through the phone's media session; if the app opts
//  out of notification-listener control the rows report the refusal rather than
//  faking playback state.
//

import AppKit
import Combine

final class MediaMenuSection: MenuSectionProviding {
    let sectionID = "media"
    var topLevelOrder: Int { 25 }

    private var retainedItems: [NSMenuItem] = []
    private var separatorItem: NSMenuItem?
    private var statusItem: NSMenuItem?
    private var playPauseItem: NSMenuItem?
    private var nextItem: NSMenuItem?
    private var previousItem: NSMenuItem?
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: MenuViewModel) {
        MediaCenter.shared.$nowPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        MediaCenter.shared.$artwork
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    // MARK: - MenuSectionProviding

    func topLevelItems() -> [NSMenuItem] {
        if retainedItems.isEmpty { buildItems() }
        refresh()
        return retainedItems
    }

    func menuWillOpen() { refresh() }

    // MARK: - Building

    private func buildItems() {
        let separator = NSMenuItem.separator()

        let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        status.isEnabled = false

        let playPause = NSMenuItem(
            title: "Play", action: #selector(togglePlayPause(_:)), keyEquivalent: "")
        playPause.target = self

        let next = NSMenuItem(
            title: "Next Track", action: #selector(nextTrack(_:)), keyEquivalent: "")
        next.target = self
        next.image = symbol("forward.fill")

        let previous = NSMenuItem(
            title: "Previous Track", action: #selector(previousTrack(_:)), keyEquivalent: "")
        previous.target = self
        previous.image = symbol("backward.fill")

        retainedItems = [separator, status, playPause, next, previous]
        separatorItem = separator
        statusItem = status
        playPauseItem = playPause
        nextItem = next
        previousItem = previous
    }

    // MARK: - Refreshing retained rows

    private func refresh() {
        guard !retainedItems.isEmpty else { return }
        let nowPlaying = MediaCenter.shared.nowPlaying
        let active = nowPlaying != nil

        separatorItem?.isHidden = !active
        statusItem?.isHidden = !active
        playPauseItem?.isHidden = !active
        nextItem?.isHidden = !active
        previousItem?.isHidden = !active

        guard let nowPlaying else { return }

        let statusText = nowPlaying.detailText
        statusItem?.title = statusText
        statusItem?.attributedTitle = NSAttributedString(
            string: statusText,
            attributes: [
                .font: NSFont.menuFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        statusItem?.toolTip = MediaCenter.shared.lastError
        if let artwork = MediaCenter.shared.artwork {
            statusItem?.image = menuImage(from: artwork)
        } else {
            statusItem?.image = symbol("music.note")
        }

        playPauseItem?.title = nowPlaying.isPlaying ? "Pause" : "Play"
        playPauseItem?.image = symbol(nowPlaying.isPlaying ? "pause.fill" : "play.fill")
        playPauseItem?.isEnabled = true

        nextItem?.isEnabled = nowPlaying.canSkip
        nextItem?.toolTip = nowPlaying.canSkip
            ? "Skips to the next track on the phone."
            : "This app does not expose skip controls."

        previousItem?.isEnabled = nowPlaying.canPrevious
        previousItem?.toolTip = nowPlaying.canPrevious
            ? "Returns to the previous track on the phone."
            : "This app does not expose previous-track controls."
    }

    // MARK: - Helpers

    private func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.size = NSSize(width: 16, height: 16)
        image?.isTemplate = true
        return image
    }

    /// Small menu artwork; scaled once per update, never cached to disk.
    private func menuImage(from image: NSImage) -> NSImage? {
        let target = NSSize(width: 16, height: 16)
        let copy = NSImage(size: target)
        copy.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: target))
        copy.unlockFocus()
        return copy
    }

    // MARK: - Actions

    @objc private func togglePlayPause(_ sender: Any?) {
        MediaCenter.shared.togglePlayPause()
    }

    @objc private func nextTrack(_ sender: Any?) {
        MediaCenter.shared.next()
    }

    @objc private func previousTrack(_ sender: Any?) {
        MediaCenter.shared.previous()
    }
}
