//
//  SnippetPasteboard.swift
//  SnipKey
//
//  Single, atomic pasteboard writer shared by the app and the keyboard extension.
//

import UIKit
import UniformTypeIdentifiers

/// Outcome of a snippet copy. Every failure mode is distinct so callers can show
/// truthful feedback instead of an unconditional "Copied" toast.
enum SnippetCopyResult: Equatable {
    case success
    case noFullAccess
    case missingData
    case tooLarge(byteCount: Int)
    case unsupportedType(format: String?)
}

enum SnippetPasteboard {
    /// Single size cap, enforced at send time AND at snippet creation. The keyboard
    /// extension's jetsam ceiling is ~60–70 MB and a copy transiently holds ~2× the
    /// file (the Data plus the pasteboard XPC buffer), so 20 MB keeps headroom.
    static let maxFileByteCount = 20 * 1024 * 1024

    /// User-facing form of the cap for alerts/toasts, derived from the constant.
    static var maxFileSizeDescription: String { "\(maxFileByteCount / (1024 * 1024)) MB" }

    /// Map a stored mime type to its UTI. Known formats resolve statically; anything
    /// else falls back to a dynamic `UTType(mimeType:)` lookup.
    static func utType(forMimeType mime: String?) -> UTType? {
        switch mime {
        case "application/pdf": return .pdf
        case "image/png": return .png
        case "image/jpeg": return .jpeg
        default:
            guard let mime else { return nil }
            return UTType(mimeType: mime)
        }
    }

    /// ONE atomic pasteboard write of the raw stored bytes labeled with the correct
    /// UTI — no placeholder string/color items, no image re-encoding. `hasFullAccess`
    /// is passed in because this file can't see UIInputViewController; the main app
    /// always passes `true` (the app process has unrestricted pasteboard access).
    @MainActor
    @discardableResult
    static func copyFile(data: Data?, mimeType: String?, hasFullAccess: Bool) -> SnippetCopyResult {
        guard hasFullAccess else { return .noFullAccess }
        guard let data, !data.isEmpty else { return .missingData }
        guard data.count <= maxFileByteCount else { return .tooLarge(byteCount: data.count) }
        guard let uti = utType(forMimeType: mimeType) else { return .unsupportedType(format: mimeType) }
        UIPasteboard.general.setItems([[uti.identifier: data]])
        return .success
    }

    /// Text counterpart so every copy path shares one entry point and result type.
    @MainActor
    @discardableResult
    static func copyText(_ text: String, hasFullAccess: Bool) -> SnippetCopyResult {
        guard hasFullAccess else { return .noFullAccess }
        UIPasteboard.general.string = text
        return .success
    }
}
