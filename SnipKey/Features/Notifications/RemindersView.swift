//
//  RemindersView.swift
//  SnipKey (main app only)
//
//  In-app list of scheduled (pending) and delivered reminders, read from
//  UNUserNotificationCenter. Reminders are created by the keyboard's 🔔 button — see
//  LOCAL_NOTIFICATIONS.md. Presented as a sheet from the Snippets screen.
//

import SwiftUI
import UserNotifications

struct RemindersView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var pending: [UNNotificationRequest] = []
    @State private var delivered: [UNNotification] = []

    private var isEmpty: Bool { pending.isEmpty && delivered.isEmpty }

    var body: some View {
        NavigationStack {
            List {
                if isEmpty {
                    emptyState()
                } else {
                    if !pending.isEmpty {
                        Section("Upcoming") {
                            ForEach(pending, id: \.identifier) { req in
                                row(title: req.content.body,
                                    detail: upcomingDetail(req))
                            }
                            .onDelete(perform: deletePending)
                        }
                    }
                    if !delivered.isEmpty {
                        Section("Delivered") {
                            ForEach(delivered, id: \.request.identifier) { note in
                                row(title: note.request.content.body,
                                    detail: "Delivered \(Self.formatter.string(from: note.date))")
                            }
                            .onDelete(perform: deleteDelivered)
                        }
                    }
                }
            }
            .navigationTitle("Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .destructive) { clearAll() } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { load() } label: { Image(systemName: "arrow.clockwise") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: load)
        }
    }

    // MARK: - Empty state guide

    /// Shown when there are no reminders: a short guide on the two ways to create one, with
    /// natural-language `/remind` examples. See REMINDER_NLP.md for the full grammar.
    @ViewBuilder
    private func emptyState() -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("No reminders yet")
                    .font(.custom("IBMPlexMono-SemiBold", size: 16))
                    .foregroundColor(Color.label)
                Text("Two ways to schedule one from the SnipKey keyboard:")
                    .font(.custom("IBMPlexMono-Regular", size: 13))
                    .foregroundColor(Color.secondaryLabel)

                guideStep(icon: "bell", text: "Tap the 🔔 for a quick reminder.")
                guideStep(icon: "text.bubble",
                          text: "Or just type what you need — when the keyboard sees a “/remind …” with a time, a Create reminder button appears in the suggestion bar. Tap it and you’re set.")
            }
            .padding(.vertical, 4)
        }

        Section("Try typing") {
            exampleRow("/remind call mom at 6pm", "today at 6:00 PM")
            exampleRow("/remind pay rent tomorrow", "tomorrow at 9:00 AM")
            exampleRow("/remind stretch in 30 minutes", "30 minutes from now")
            exampleRow("/remind take meds this morning", "today at 9:00 AM")
            exampleRow("/remind dentist next friday", "Friday at 9:00 AM")
        }

        Section {
            Text("Words like tonight, this afternoon, noon and before bed map to set times. A time that already passed today rolls to tomorrow, and a reminder with no time fires in 1 hour.")
                .font(.custom("IBMPlexMono-Regular", size: 12))
                .foregroundColor(Color.secondaryLabel)
        } footer: {
            Text("Natural-language “/remind” parsing is currently English only.")
                .font(.custom("IBMPlexMono-Regular", size: 11))
        }
    }

    private func guideStep(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color.label)
                .frame(width: 18, alignment: .center)
            Text(text)
                .font(.custom("IBMPlexMono-Regular", size: 13))
                .foregroundColor(Color.label)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func exampleRow(_ command: String, _ result: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(command)
                .font(.custom("IBMPlexMono-Medium", size: 13))
                .foregroundColor(Color.label)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.secondarySystemBackground)
                )
            HStack(spacing: 4) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 9))
                Text(result)
                    .font(.custom("IBMPlexMono-Regular", size: 11))
            }
            .foregroundColor(Color.secondaryLabel)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Rows

    private func row(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.custom("IBMPlexMono-Medium", size: 14))
                .foregroundColor(Color.label)
            Text(detail)
                .font(.custom("IBMPlexMono-Regular", size: 11))
                .foregroundColor(Color.secondaryLabel)
        }
        .padding(.vertical, 2)
    }

    private func upcomingDetail(_ req: UNNotificationRequest) -> String {
        guard let fireDate = Self.nextFireDate(req.trigger) else { return "Scheduled" }
        return "Fires \(Self.formatter.string(from: fireDate))"
    }

    /// Next fire date for either trigger kind: relative (🔔 button) or calendar (`/remind … at <time>`).
    private static func nextFireDate(_ trigger: UNNotificationTrigger?) -> Date? {
        if let t = trigger as? UNTimeIntervalNotificationTrigger { return t.nextTriggerDate() }
        if let t = trigger as? UNCalendarNotificationTrigger { return t.nextTriggerDate() }
        return nil
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .medium
        return f
    }()

    // MARK: - Data

    private func load() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ours = requests
                .filter { $0.identifier.hasPrefix(LocalNotificationScheduler.identifierPrefix) }
                .sorted { lhs, rhs in
                    let l = Self.nextFireDate(lhs.trigger) ?? .distantFuture
                    let r = Self.nextFireDate(rhs.trigger) ?? .distantFuture
                    return l < r
                }
            DispatchQueue.main.async { pending = ours }
        }
        center.getDeliveredNotifications { notes in
            let ours = notes
                .filter { $0.request.identifier.hasPrefix(LocalNotificationScheduler.identifierPrefix) }
                .sorted { $0.date > $1.date }
            DispatchQueue.main.async { delivered = ours }
        }
    }

    private func deletePending(at offsets: IndexSet) {
        let ids = offsets.map { pending[$0].identifier }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        pending.remove(atOffsets: offsets)
    }

    private func deleteDelivered(at offsets: IndexSet) {
        let ids = offsets.map { delivered[$0].request.identifier }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
        delivered.remove(atOffsets: offsets)
    }

    private func clearAll() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier))
        center.removeDeliveredNotifications(withIdentifiers: delivered.map(\.request.identifier))
        pending = []
        delivered = []
    }
}

#Preview {
    RemindersView()
}
