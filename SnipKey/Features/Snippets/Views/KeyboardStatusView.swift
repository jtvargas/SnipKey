//
//  KeyboardStatusView.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/29/24.
//

import SwiftUI
import Pow

struct KeyboardStatusView: View {
    var isShortcutsActive: Bool = false
    var onKeyboardStatusPress: () -> Void

    @State private var showingDetails = false

    var statusColor: Color {
        isShortcutsActive ? .customSuccess : .customError
    }

    var statusIcon: String {
        isShortcutsActive ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    var body: some View {
        Button {
            showingDetails = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                    .symbolEffect(.pulse)

//                Text(isShortcutsActive ? "Keyboard Ready" : "Setup Required")
//                    .font(.custom("IBMPlexMono-Bold", size: 14))
//                    .foregroundColor(.label)

//                Image(systemName: "chevron.right")
//                    .font(.system(size: 12, weight: .semibold))
//                    .foregroundColor(.secondaryLabel)
            }
//            .padding(.horizontal, 16)
//            .padding(.vertical, 12)
//            .background(Color.systemBackground)
//            .overlay(
//                RoundedRectangle(cornerRadius: 8)
//                    .stroke(statusColor, lineWidth: 2)
//            )
        }
        .conditionalEffect(
            .repeat(
                .glow(color: statusColor, radius: 4),
                every: 1.5
            ),
            condition: !isShortcutsActive
        )
        .sheet(isPresented: $showingDetails) {
            KeyboardDetailsSheet(
                isShortcutsActive: isShortcutsActive,
                onKeyboardStatusPress: onKeyboardStatusPress
            )
//            .presentationDetents([.])
            .presentationDetents([.fraction(0.7)])
            .presentationDragIndicator(.visible)
        }
    }
}

struct KeyboardDetailsSheet: View {
    var isShortcutsActive: Bool
    var onKeyboardStatusPress: () -> Void

    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Keyboard Status")
                    .font(.custom("IBMPlexMono-Bold", size: 18))

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.secondaryLabel)
                }
            }
            .padding()

            Divider()

            // Content
            VStack(spacing: 24) {
                // Status Icon & Text
                VStack(spacing: 12) {
                    Image(systemName: isShortcutsActive ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(isShortcutsActive ? .customSuccess : .customError)
                        .symbolEffect(.pulse)

                    VStack(spacing: 4) {
                        Text(isShortcutsActive ? "Ready to Use" : "Setup Required")
                            .font(.custom("IBMPlexMono-Bold", size: 20))

                        Text(isShortcutsActive ? "Keyboard is configured" : "Tap below to configure")
                            .font(.custom("IBMPlexMono-Regular", size: 13))
                            .foregroundColor(.secondaryLabel)
                    }
                }
                .padding(.top, 20)

                // Status Card
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "keyboard")
                            .foregroundColor(.blue)

                        Text("Shortcuts")
                            .font(.custom("IBMPlexMono-Bold", size: 14))

                        Spacer()

                        Image(systemName: isShortcutsActive ? "checkmark.circle.fill" : "x.circle.fill")
                            .foregroundColor(isShortcutsActive ? .customSuccess : .customError)
                    }

                    Divider()

                    HStack {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .foregroundColor(.blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Commands")
                                .font(.custom("IBMPlexMono-Bold", size: 14))
                            Text("Just type '/'")
                                .font(.custom("IBMPlexMono-Regular", size: 11))
                                .foregroundColor(.secondaryLabel)
                        }

                        Spacer()

                        Image(systemName: isShortcutsActive ? "checkmark.circle.fill" : "x.circle.fill")
                            .foregroundColor(isShortcutsActive ? .customSuccess : .customError)
                    }

                    Divider()

                    HStack(alignment: .top) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Full Access")
                                .font(.custom("IBMPlexMono-Bold", size: 14))
                            Text("Required for images & files")
                                .font(.custom("IBMPlexMono-Regular", size: 11))
                                .foregroundColor(.secondaryLabel)
                        }

                        Spacer()
                    }
                }
                .padding(16)
                .background(Color.secondarySystemBackground)
                .cornerRadius(12)

                Spacer()

                // Action Button
                if !isShortcutsActive {
                    Button {
                        dismiss()
                        onKeyboardStatusPress()
                    } label: {
                        HStack {
                            Image(systemName: "lightbulb.min.fill")
                            Text("See How To Setup")
                                .font(.custom("IBMPlexMono-Bold", size: 15))
                        }
                        .foregroundColor(.yellow)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.glass)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .presentationDragIndicator(.hidden)
    }
}
struct StatusRow: View {
    let icon: String
    let title: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .font(.system(size: 20))

            Text(title)
                .font(.custom("IBMPlexMono-Bold", size: 14))

            Spacer()

            Image(systemName: isActive ? "checkmark.circle.fill" : "x.circle.fill")
                .foregroundColor(isActive ? .customSuccess : .customError)
                .font(.system(size: 20))
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    VStack {
        KeyboardStatusView(
            isShortcutsActive: false,
            onKeyboardStatusPress: { }
        )
        .padding()

        KeyboardStatusView(
            isShortcutsActive: true,
            onKeyboardStatusPress: { }
        )
        .padding()
    }
}
