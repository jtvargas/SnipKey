//
//  SnippetPreviewOverlay.swift
//  SnipKeyboard
//
//  Long-press preview card for the snippet list. A custom overlay instead of
//  .contextMenu: the system menu renders inside the ~254pt keyboard window
//  (clipped) and follows the system appearance, not the keyboard's
//  appearanceMode. Secure snippets must be authenticated BEFORE this view is
//  presented — it renders content unconditionally.
//
//  No dim layer, fully opaque card — same surface treatment as the
//  reminder-confirmation pill (ReminderToastModifier): translucent key colors
//  bleed the grid through anything floating above it.
//

import SwiftUI

struct SnippetPreviewOverlay: View {
    let snippet: SnippetItem
    let isDark: Bool
    /// Authoritative Full Access state (keyboardActions.hasFullAccess()).
    /// Copy stays tappable without it so the tap can surface the explanation toast.
    let canCopy: Bool
    let onCopy: () -> Void
    let onInsert: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Invisible tap-catcher — tap outside the card to dismiss (no dim).
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            // Card
            VStack(spacing: 10) {
                header

                contentBody
                    .frame(maxWidth: .infinity, alignment: .leading)

                footer
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: KeyStyle.cornerRadius, style: .continuous)
                    .fill(KeyStyle.solidSurface(isDark: isDark))
                    .overlay(
                        RoundedRectangle(cornerRadius: KeyStyle.cornerRadius, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
                    )
            )
            .shadow(color: .black.opacity(isDark ? 0.45 : 0.18), radius: 10, y: 4)
            .frame(maxWidth: 320)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: snippet.type?.snipTypeImage ?? "doc.text")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(KeyStyle.secondaryGlyph(isDark: isDark))
                .frame(width: 28, height: 28)
                .background(Circle().fill(KeyStyle.iconWell(isDark: isDark)))

            Text(snippet.title ?? "")
                .font(.custom("IBMPlexMono-Medium", size: 14))
                .foregroundStyle(KeyStyle.solidSurfaceText(isDark: isDark))
                .lineLimit(1)

            if snippet.isSecure {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(KeyStyle.secondaryGlyph(isDark: isDark))
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentBody: some View {
        switch snippet.type ?? .txt {
        case .txt, .url:
            ScrollView {
                Text(snippet.content ?? "")
                    .font(.custom("IBMPlexMono-Regular", size: 12))
                    .foregroundStyle(KeyStyle.secondaryGlyph(isDark: isDark))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        case .image:
            // Decode is fine here — single image, user-initiated.
            if let data = snippet.file?.fileData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: KeyStyle.cornerRadius, style: .continuous))
                    .frame(maxWidth: .infinity)
            } else {
                typeLabel
            }
        case .file:
            typeLabel
        }
    }

    private var typeLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: snippet.type?.snipTypeImage ?? "doc.circle.fill")
                .font(.system(size: 16))
            Text((snippet.type ?? .txt).displayText)
                .font(.custom("IBMPlexMono-Regular", size: 12))
        }
        .foregroundStyle(KeyStyle.secondaryGlyph(isDark: isDark))
        .padding(.vertical, 8)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            actionButton(title: "Copy", systemImage: "doc.on.doc", action: onCopy)
                .opacity(canCopy ? 1.0 : 0.5)
            actionButton(title: "Insert", systemImage: "text.insert", action: onInsert)
        }
    }

    private func actionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.custom("IBMPlexMono-Medium", size: 12))
            }
            .foregroundStyle(KeyStyle.solidSurfaceText(isDark: isDark))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: KeyStyle.cornerRadius, style: .continuous)
                    .fill(KeyStyle.solidSurfaceButton(isDark: isDark))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(SnippetPressStyle())
    }
}
