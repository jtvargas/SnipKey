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
                    Section {
                        Text("No reminders yet — tap the 🔔 on the SnipKey keyboard to schedule one.")
                            .font(.custom("IBMPlexMono-Regular", size: 13))
                            .foregroundColor(.secondary)
                    }
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
        guard let trigger = req.trigger as? UNTimeIntervalNotificationTrigger,
              let fireDate = trigger.nextTriggerDate() else {
            return "Scheduled"
        }
        return "Fires \(Self.formatter.string(from: fireDate))"
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
                    let l = (lhs.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate() ?? .distantFuture
                    let r = (rhs.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate() ?? .distantFuture
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
