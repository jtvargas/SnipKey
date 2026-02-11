//
//  QWERTYKeyboardView.swift
//  SnipKeyboard
//
//  Created by Jonathan Taveras Vargas on 2/10/26.
//

import SwiftUI

// MARK: - Main QWERTY Keyboard View

struct QWERTYKeyboardView: View {
    @Environment(QWERTYKeyboardState.self) private var state
    @Environment(\.keyboardActions) private var actions

    var body: some View {
        // Use screenWidth from UIKit (passed via KeyboardActions) — no GeometryReader needed.
        // This avoids GeometryReader's intrinsic-size problem in keyboard extensions.
        let dimensions = KeyboardDimensions(screenWidth: actions.screenWidth)

        VStack(spacing: 0) {
            // Top toolbar with snippet toggle
            KeyboardToolbarView(dimensions: dimensions)

            // Key rows
            VStack(spacing: dimensions.rowGap) {
                let rows = QWERTYKeyboardLayout.rows(for: state.currentPage)
                ForEach(Array(rows.enumerated()), id: \.element) { index, row in
                    KeyRowView(
                        actions: row,
                        rowIndex: index,
                        dimensions: dimensions
                    )
                }
            }
            .padding(.top, dimensions.topEdge)
            .padding(.bottom, dimensions.bottomEdge)
        }
        .frame(height: dimensions.totalHeight)
        // Haptic feedback disabled for smooth fast typing (iOS 26 style).
        // KeyboardHaptics is available if a user setting is added later.
    }
}

// MARK: - Keyboard Toolbar

/// Top toolbar with snippet toggle button.
/// This bar will also serve as the foundation for the future suggestion/autocomplete bar.
struct KeyboardToolbarView: View {
    let dimensions: KeyboardDimensions
    @Environment(QWERTYKeyboardState.self) private var state

    var body: some View {
        HStack {
            // Snippet toggle button
            Button {
                state.showingSnippets = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "text.badge.star")
                        .font(.system(size: 14, weight: .medium))
                    Text("Snippets")
                        .font(.custom("IBMPlexMono-Medium", size: 13))
                }
                .foregroundStyle(.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue.opacity(0.1))
                )
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(height: dimensions.toolbarHeight)
        .padding(.horizontal, 12)
    }
}
