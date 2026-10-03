//
//  CopyButton.swift
//  QuickNetStats
//

import SwiftUI
import AppKit

/// A plain button that copies `value` to the clipboard and briefly reports it.
/// The label receives `isConfirming`, true for a short moment after a successful copy,
/// so it can swap its content for a "Copied" confirmation. Disabled when `value` is nil.
struct CopyButton<Content: View>: View {

    let value: String?
    /// The app's animation preference; reduce motion is honored on top of it.
    var animated: Bool = true
    @ViewBuilder let label: (_ isConfirming: Bool) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isConfirming = false
    @State private var confirmationID = 0

    private static var confirmationDuration: Duration { .seconds(1.2) }

    var body: some View {
        Button(action: copy) {
            label(isConfirming)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(value == nil)
        .help(value == nil ? "" : "Click to copy")
        .accessibilityHint(value == nil ? "" : "Copies to the clipboard")
        // Restarting on every new id lets a re-tap extend the confirmation instead of a stale timer clearing it.
        .task(id: confirmationID) {
            guard confirmationID > 0 else { return }
            do {
                try await Task.sleep(for: Self.confirmationDuration)
            } catch {
                return
            }
            withAnimation(animation) { isConfirming = false }
        }
        // MenuBarExtra keeps this view alive across popover openings, so a confirmation cut short by
        // closing would otherwise resurface on reopen.
        .onDisappear { isConfirming = false }
    }

    private var animation: Animation? {
        animated && !reduceMotion ? .easeInOut(duration: 0.15) : nil
    }

    private func copy() {
        guard Clipboard.copy(value) else { return }
        withAnimation(animation) { isConfirming = true }
        confirmationID += 1
        announceCopied()
    }

    private func announceCopied() {
        if #available(macOS 14, *) {
            AccessibilityNotification.Announcement("Copied").post()
        } else {
            NSAccessibility.post(
                element: NSApp as Any,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: "Copied",
                    .priority: NSAccessibilityPriorityLevel.high.rawValue
                ]
            )
        }
    }
}

// MARK: - Previews

#Preview("Idle") {
    CopyButton(value: "10.0.0.32") { isConfirming in
        Text(isConfirming ? "Copied" : "10.0.0.32")
    }
    .padding()
}

#Preview("Nil value (disabled)") {
    CopyButton(value: nil) { _ in
        Text("Unavailable")
    }
    .padding()
}
