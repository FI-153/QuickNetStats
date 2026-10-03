//
//  WindowScreenReader.swift
//  QuickNetStats
//

import SwiftUI
import AppKit

/// Reports the screen of the window hosting this view, as it appears and whenever the window moves
/// to another display. Prefer this over `NSScreen.main`, which follows the key window process-wide.
struct WindowScreenReader: NSViewRepresentable {

    let onChange: (NSScreen?) -> Void

    func makeNSView(context: Context) -> ScreenTrackingView {
        let view = ScreenTrackingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: ScreenTrackingView, context: Context) {
        nsView.onChange = onChange
    }

    final class ScreenTrackingView: NSView {

        var onChange: ((NSScreen?) -> Void)?

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if let window {
                NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeScreenNotification, object: window)
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidChangeScreen),
                name: NSWindow.didChangeScreenNotification,
                object: window
            )
            report()
        }

        @objc private func windowDidChangeScreen(_ notification: Notification) {
            report()
        }

        // Deferred so the callback never mutates SwiftUI state in the middle of a view update.
        private func report() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onChange?(self.window?.screen)
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

extension View {
    /// Calls `action` with the hosting window's screen when the view appears and when the window
    /// changes displays.
    func onWindowScreenChange(_ action: @escaping (NSScreen?) -> Void) -> some View {
        background(WindowScreenReader(onChange: action).frame(width: 0, height: 0))
    }
}
