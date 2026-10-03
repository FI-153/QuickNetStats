//
//  Clipboard.swift
//  QuickNetStats
//

import AppKit

enum Clipboard {
    /// Returns false (and leaves the pasteboard untouched) for nil or empty values.
    @discardableResult
    static func copy(_ value: String?, to pasteboard: NSPasteboard = .general) -> Bool {
        guard let value, !value.isEmpty else { return false }
        pasteboard.clearContents()
        return pasteboard.setString(value, forType: .string)
    }
}
