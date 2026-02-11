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

/// Top toolbar with settings button (right-aligned).
/// The snippets toggle is available via the dedicated key in the bottom row.
/// This toolbar has zero @Observable dependencies — it never re-renders during typing.
struct KeyboardToolbarView: View {
    let dimensions: KeyboardDimensions
    @Environment(\.keyboardActions) private var actions

    var body: some View {
        HStack {
            Spacer()

            // Settings button — opens main SnipKey app
            Button {
                actions.openApp()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(.secondaryLabel))
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .frame(height: dimensions.toolbarHeight)
        .padding(.horizontal, 12)
    }
}
