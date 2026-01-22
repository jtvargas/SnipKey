//
//  KeyboardHelpGuideView.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/29/24.
//

import SwiftUI

// MARK: - Helper Function
func openPhoneSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else {
        return
    }
    
    if UIApplication.shared.canOpenURL(url) {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}

// MARK: - Setup Step Model
struct KeyboardSetupStep: Identifiable {
    let id = UUID()
    let stepNumber: Int
    let title: String
    let instructions: [String]
    let note: String?
    let noteIcon: String?
    let image: String
    let darkImage: String
    let actionLabel: String?
    let actionIcon: String?
    let action: (() -> Void)?
}

// MARK: - Setup Steps Data
let keyboardSetupSteps: [KeyboardSetupStep] = [
    KeyboardSetupStep(
        stepNumber: 1,
        title: "Open Keyboard Settings",
        instructions: [
            "Tap **Open Settings** below",
            "Select **Keyboards**",
            "Tap **Add New Keyboard...**",
            "Choose **SnipKey** from the list"
        ],
        note: nil,
        noteIcon: nil,
        image: "settings-white-keyboard",
        darkImage: "settings-dark-keyboard",
        actionLabel: "Open Settings",
        actionIcon: "gear",
        action: { openPhoneSettings() }
    ),
    KeyboardSetupStep(
        stepNumber: 2,
        title: "Enable Full Access",
        instructions: [
            "Tap **SnipKey** in your keyboard list",
            "Turn on **Allow Full Access**",
            "Tap **Allow** when prompted"
        ],
        note: "Your data stays private and never leaves your device.",
        noteIcon: "lock.shield.fill",
        image: "settings-white-keyboard2",
        darkImage: "settings-dark-keyboard2",
        actionLabel: nil,
        actionIcon: nil,
        action: nil
    ),
    KeyboardSetupStep(
        stepNumber: 3,
        title: "You're All Set!",
        instructions: [
            "Open any app with a text field",
            "Tap and hold the **globe** icon on your keyboard",
            "Select **SnipKey** from the list"
        ],
        note: "Your snippets are now just one tap away!",
        noteIcon: "sparkles",
        image: "keyboard-switch",
        darkImage: "keyboard-switch",
        actionLabel: nil,
        actionIcon: nil,
        action: nil
    )
]

// MARK: - Step Indicator Component
struct StepIndicator: View {
    let currentStep: Int
    let totalSteps: Int
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 44, height: 44)
                Text("\(currentStep)")
                    .font(.custom("IBMPlexMono-Bold", size: 20))
                    .foregroundColor(.white)
            }
            
            Text("Step \(currentStep) of \(totalSteps)")
                .font(.custom("IBMPlexMono-Medium", size: 13))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Instruction Row Component
struct InstructionRow: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number).")
                .font(.custom("IBMPlexMono-Bold", size: 16))
                .foregroundColor(.blue)
                .frame(width: 24, alignment: .leading)
            
            Text(.init(text))
                .font(.custom("IBMPlexMono-Medium", size: 15))
                .foregroundColor(.label)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Note Box Component
struct NoteBox: View {
    let icon: String
    let text: String
    var style: NoteStyle = .info
    
    enum NoteStyle {
        case info, tip, privacy
        
        var backgroundColor: Color {
            switch self {
            case .info: return Color.blue.opacity(0.1)
            case .tip: return Color.green.opacity(0.1)
            case .privacy: return Color.purple.opacity(0.1)
            }
        }
        
        var iconColor: Color {
            switch self {
            case .info: return .blue
            case .tip: return .green
            case .privacy: return .purple
            }
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(style.iconColor)
                .frame(width: 24)
            
            Text(text)
                .font(.custom("IBMPlexMono-Regular", size: 13))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.backgroundColor)
        .cornerRadius(12)
    }
}

// MARK: - Progress Dots Component
struct ProgressDots: View {
    let currentStep: Int
    let totalSteps: Int
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Circle()
                    .fill(index == currentStep ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: currentStep)
            }
        }
    }
}

// MARK: - Step Card View
struct SetupStepCard: View {
    @Environment(\.colorScheme) var colorScheme
    let step: KeyboardSetupStep
    let totalSteps: Int
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Step Indicator
                StepIndicator(currentStep: step.stepNumber, totalSteps: totalSteps)
                    .padding(.top, 8)
                
                // Title
                Text(step.title)
                    .font(.custom("IBMPlexMono-Bold", size: 26))
                    .foregroundColor(.label)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // Image
                Group {
                    if colorScheme == .light {
                        Image(step.image)
                            .resizable()
                    } else {
                        Image(step.darkImage)
                            .resizable()
                    }
                }
                .scaledToFit()
                .frame(maxHeight: 220)
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                .padding(.horizontal, 24)
                
                // Instructions
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(step.instructions.enumerated()), id: \.offset) { index, instruction in
                        InstructionRow(number: index + 1, text: instruction)
                    }
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Note (if present)
                if let note = step.note, let noteIcon = step.noteIcon {
                    NoteBox(
                        icon: noteIcon,
                        text: note,
                        style: step.stepNumber == 2 ? .privacy : .tip
                    )
                    .padding(.horizontal, 24)
                }
                
                // Action Button (if present)
                if let actionLabel = step.actionLabel {
                    Button(action: {
                        step.action?()
                    }) {
                        HStack(spacing: 10) {
                            if let actionIcon = step.actionIcon {
                                Image(systemName: actionIcon)
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            Text(actionLabel)
                                .font(.custom("IBMPlexMono-Bold", size: 16))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 16)
                        .background(Color.blue)
                        .cornerRadius(14)
                        .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .padding(.top, 8)
                }
                
                Spacer(minLength: 80)
            }
            .padding(.vertical, 16)
        }
    }
}

// MARK: - Main View
struct KeyboardHelpGuideView: View {
    @Binding var isPresented: Bool
    @State private var currentStep: Int = 0
    
    private let steps = keyboardSetupSteps
    
    var body: some View {
        VStack(spacing: 0) {
            // Content TabView
            TabView(selection: $currentStep) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    SetupStepCard(step: step, totalSteps: steps.count)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: currentStep)
            
            // Bottom Navigation Bar
            VStack(spacing: 16) {
                Divider()
                
                HStack(alignment: .center) {
                    // Back Button
                    if currentStep > 0 {
                        Button {
                            withAnimation {
                                currentStep -= 1
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Back")
                                    .font(.custom("IBMPlexMono-Medium", size: 15))
                            }
                            .foregroundColor(.blue)
                        }
                    } else {
                        Button {
                            isPresented = false
                        } label: {
                            Text("Close")
                                .font(.custom("IBMPlexMono-Medium", size: 15))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Progress Dots
                    ProgressDots(currentStep: currentStep, totalSteps: steps.count)
                    
                    Spacer()
                    
                    // Next/Done Button
                    Button {
                        if currentStep == steps.count - 1 {
                            isPresented = false
                        } else {
                            withAnimation {
                                currentStep += 1
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(currentStep == steps.count - 1 ? "Done" : "Next")
                                .font(.custom("IBMPlexMono-Bold", size: 15))
                            if currentStep < steps.count - 1 {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                        }
                        .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .background(Color.systemBackground)
        }
        .background(Color.systemBackground)
    }
}

// MARK: - Preview
#Preview {
    @Previewable @State var isPresentedGuide: Bool = true
    
    KeyboardHelpGuideView(isPresented: $isPresentedGuide)
}
