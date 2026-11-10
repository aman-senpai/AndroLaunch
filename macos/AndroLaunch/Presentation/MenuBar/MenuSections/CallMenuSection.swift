//
//  CallMenuSection.swift
//  AndroLaunch
//
//  Status-menu call rows: answer/decline while the phone rings, end a call in
//  progress, and one status line naming the device. Owned by phone-companion.
//
//  The section is silent when there is no call: its rows exist so AppKit never
//  has to rebuild the menu for a call (which would move the highlighted row), but
//  they are hidden until a call appears. Nothing here claims call audio.
//

import AppKit
import Combine

final class CallMenuSection: MenuSectionProviding {
    let sectionID = "calls"
    var topLevelOrder: Int { 20 }

    private var retainedItems: [NSMenuItem] = []
    private var separatorItem: NSMenuItem?
    private var statusItem: NSMenuItem?
    private var answerItem: NSMenuItem?
    private var declineItem: NSMenuItem?
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: MenuViewModel) {
        CallCenter.shared.$active
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

        let answer = NSMenuItem(
            title: "Answer Call", action: #selector(answerCall(_:)), keyEquivalent: "")
        answer.target = self
        answer.image = symbol("phone.fill")

        let decline = NSMenuItem(
            title: "Decline Call", action: #selector(declineCall(_:)), keyEquivalent: "")
        decline.target = self
        decline.image = symbol("phone.down.fill")

        retainedItems = [separator, status, answer, decline]
        separatorItem = separator
        statusItem = status
        answerItem = answer
        declineItem = decline
    }

    // MARK: - Refreshing retained rows

    private func refresh() {
        guard !retainedItems.isEmpty else { return }
        let snapshot = CallCenter.shared.active
        let call = snapshot != nil && !(snapshot?.isIdle ?? true)

        // Hidden rows keep the menu structurally stable while staying silent when idle.
        separatorItem?.isHidden = !call
        statusItem?.isHidden = !call
        answerItem?.isHidden = !call
        declineItem?.isHidden = !call

        guard let snapshot, call else { return }

        let control = snapshot.controlAvailable
        let deviceName = snapshot.deviceName

        statusItem?.title = statusText(for: snapshot)
        statusItem?.attributedTitle = statusTitle(statusText(for: snapshot))

        if snapshot.isRinging {
            answerItem?.isHidden = false
            answerItem?.title = "Answer Call on \(deviceName)"
            answerItem?.isEnabled = control
            answerItem?.toolTip = control
                ? "Answers the call on your phone. Audio stays on your phone."
                : "Allow call control in AndroLaunch Comp on the phone (Calls → Allow)."
            declineItem?.title = "Decline Call"
            declineItem?.toolTip = "Declines the ringing call on your phone."
        } else {
            answerItem?.isHidden = true
            declineItem?.title = "End Call on \(deviceName)"
            declineItem?.toolTip = "Ends the call on your phone. Audio stays on your phone."
        }
        declineItem?.isEnabled = control
        if !control {
            declineItem?.toolTip = "Allow call control in AndroLaunch Comp on the phone."
        }
        if let error = CallCenter.shared.lastError {
            statusItem?.toolTip = error
        }
    }

    private func statusText(for snapshot: CallCenter.Snapshot) -> String {
        let state: String
        if snapshot.isRinging {
            state = snapshot.incoming ? "Incoming call" : "Ringing"
        } else {
            state = "In call"
        }
        return "\(state) · \(snapshot.deviceName)"
    }

    private func statusTitle(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.menuFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
    }

    private func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.size = NSSize(width: 16, height: 16)
        image?.isTemplate = true
        return image
    }

    // MARK: - Actions

    @objc private func answerCall(_ sender: Any?) {
        CallCenter.shared.answer()
    }

    @objc private func declineCall(_ sender: Any?) {
        CallCenter.shared.decline()
    }
}
