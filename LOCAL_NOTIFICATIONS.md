# Keyboard-Triggered Local Notifications

How the **keyboard extension** (`SnipKeyboard`) schedules a local notification when the user
accepts a **Create reminder** pill — and why it fires even while the main app (`SnipKey`) stays
suspended in the background. The empty-field bell beside Paste only inserts `/remind `.

---

## The key constraint that drives the design

> A backgrounded app is **suspended** — it runs no code. It cannot schedule anything "on demand"
> while suspended, and iOS does **not** wake it for cross-process signals (Darwin notifications,
> App Group writes, etc.).

So the notification must be scheduled by whoever is **actually running** at the moment the button is
tapped — that's the **keyboard extension**. Once the keyboard calls `UNUserNotificationCenter.add`,
the **system** owns the timer and delivers the notification at fire time regardless of the app's
state (foreground, backgrounded, suspended, or closed). The main app never has to be reopened.

> An earlier design used App Groups + Darwin notifications to have the *main app* schedule. That
> cannot satisfy "fire while the app stays suspended," because the suspended app can't run the
> scheduling code. It was replaced by direct keyboard scheduling.

---

## Flow

```text
Main app (once): NotificationPresenter.bootstrap()
                LocalNotificationScheduler.requestAuthorizationIfNeeded()

Keyboard: empty-field bell / code-button Reminder action
          → inserts "/remind " without scheduling
          → user enters task/time and accepts Create reminder
          → KeyboardActions.createReminder (Full Access required)
          → KeyboardViewController.routeReminder
          → LocalNotificationScheduler.schedule(ReminderRequest)
          → UNUserNotificationCenter.add(calendar trigger)
          → system delivers at the requested time, app state irrelevant
```

1. App is launched once → `NotificationPresenter.bootstrap()` sets the delegate, and
   `LocalNotificationScheduler.requestAuthorizationIfNeeded()` prompts for permission.
2. User backgrounds SnipKey, switches to another app, and taps the empty-field bell.
3. The keyboard inserts `/remind `; the user enters a task/time and accepts **Create reminder**.
4. With Full Access and the SnipKey destination, the keyboard schedules the request.
5. At the parsed fire date the banner appears — no reopening required.

---

## Components

| File | Target membership | Responsibility |
|---|---|---|
| [`SnipKey/Shared/Notifications/LocalNotificationScheduler.swift`](SnipKey/Shared/Notifications/LocalNotificationScheduler.swift) | **Both** | `ReminderRequest` model + `schedule(_:)` + `requestAuthorizationIfNeeded()` + `identifierPrefix` |
| [`SnipKey/Features/Notifications/NotificationPresenter.swift`](SnipKey/Features/Notifications/NotificationPresenter.swift) | **SnipKey only** | `UNUserNotificationCenterDelegate` — foreground banner presentation + `bootstrap()` |
| [`SnipKey/Features/Notifications/RemindersView.swift`](SnipKey/Features/Notifications/RemindersView.swift) | **SnipKey only** | In-app list of pending + delivered reminders (swipe-delete, clear-all, refresh) |

Wiring:
- `SnipKeyApp.init()` → `NotificationPresenter.shared.bootstrap()` (delegate set before launch finishes).
- Root view `.onAppear` → `LocalNotificationScheduler.requestAuthorizationIfNeeded()`.
- Keyboard bell (`KeyboardToolbarView`) → `KeyboardActions.insertQuickCommand("/remind ")`.
  Accepting the resulting pill invokes `createReminder`, whose controller checks Full Access and
  routes the parsed date to the configured destination.
- App: 🔔 toolbar button on the Snippets screen (`HomeView2`) presents `RemindersView` as a sheet.

## Button UX & multiple reminders

- The keyboard 🔔 uses `SuggestionPillButtonStyle` (instant pressed highlight) and a 44pt-wide,
  full-toolbar-height hit cell (`.contentShape(Rectangle())`) — matching the suggestion pills, so
  taps register reliably and give feedback. It appears only for an empty field and inserts the
  command prefix; it does not schedule a fixed-delay reminder.
- Each accepted Create reminder pill schedules an **independent** notification: a unique
  `identifierPrefix + UUID` identifier and a distinct subtitle ("Fires at <time>").
- `RemindersView` filters by `LocalNotificationScheduler.identifierPrefix`, lists **Upcoming**
  (pending, by fire time) and **Delivered**, and is the diagnostic for "did it actually schedule?".

## Natural-language `/remind`

The keyboard also recognizes a typed command and offers a one-tap **"Create reminder"** suggestion
pill — no need to background the app or press the 🔔. Type, for example:

```
/remind me to call the doctor at 3PM
```

- **Parsing** is fully on-device — zero latency, no network — in `ReminderParser` (see
  [`SnipKeyboard/QWERTY/ReminderParseEngine.swift`](SnipKeyboard/QWERTY/ReminderParseEngine.swift)).
  It's **intent-aware**: it separates *which day* from *what time* and decides the time
  deterministically (explicit clock → time-of-day phrase → 9 AM default → now + 1 hour), rather than
  trusting `NSDataDetector`'s noon default. `NSDataDetector` (C-based, near-zero memory, safe under
  the 48 MB ceiling) supplies the **day**; custom logic fills what it misses (`noon`, `next week`,
  `next month`, bare `at 3`, relative `in N units`). **Full rules + examples:**
  **[`REMINDER_NLP.md`](REMINDER_NLP.md)**.
- Sub-minute precision is preserved: the calendar trigger includes `.second`, so "in 15 seconds"
  fires on time instead of rounding to the minute.
- **Trigger:** the explicit `/remind` keyword plus a real task or time. A bare time in normal text
  (no `/remind`) never shows the pill, and `/remind` with nothing typed yet shows nothing.
- The pill takes precedence over the predictive/slash suggestions and shows the resolved time
  ("Create reminder · 3:00 PM"). Tapping it: deletes the typed command, schedules the reminder, and
  shows a confirmation banner ("Reminder created for today/tomorrow at 3:00 PM").
- **Defaults:** explicit clock time fires that day (rolling to **tomorrow** if already passed);
  a date with no time fires at **9:00 AM**; time-of-day words map deterministically
  (afternoon → 3 PM, tonight → 7 PM, …); and a bare `/remind <task>` with no time → **now + 1 hour**.
- The reminder is built as `ReminderRequest(fireDate:title:"Reminder", message: <task>)` and scheduled
  by the **same** `LocalNotificationScheduler.schedule(_:)` (an absolute `fireDate` uses a
  `UNCalendarNotificationTrigger`). Because it reuses the shared `identifierPrefix`, it appears in
  `RemindersView` and feeds the in-app bell badge automatically.

Wiring: the controller updates `ReminderSuggestionState` from the coalesced side-effect flush
(`runReminderEvaluation`); the toolbar renders `CreateReminderPill` and calls
`KeyboardActions.createReminder(body:fireDate:)`, which checks Full Access before scheduling.
The confirmation banner uses the shared `.reminderToast()` modifier. The bell and code-button
menu are command-entry shortcuts, not separate scheduling paths.

## Upcoming badge

The Snippets 🔔 toolbar button (`HomeView2.RemindersButtonView`) shows a red count of **pending**
reminders. The count is read from `getPendingNotificationRequests` (filtered by `identifierPrefix`)
and refreshed on appear, on scene `.active`, when the Reminders sheet closes, and when a reminder
fires while the app is foreground — the latter via the `NotificationPresenter.remindersDidChange`
broadcast (posted from `willPresent`). There is no live cross-process signal from the keyboard, so
the badge reflects the latest read rather than updating the instant the keyboard schedules.

---

## Authorization model

Notification authorization is granted to the **app**, not the extension — and an app extension
cannot present the system permission prompt. So:

- The **main app** requests authorization once (the user must open SnipKey one time).
- The **keyboard** schedules using that already-granted authorization. The notification is delivered
  under SnipKey's identity (app name + icon).
- `schedule(_:)` checks `getNotificationSettings` and no-ops with a diagnostic if not authorized.

---

## Requirements

- **Full Access** must be enabled to schedule from the keyboard; without it, the sandbox blocks
  scheduling. The `createReminder` action checks access and logs refusal. Inserting `/remind `
  through the bell or code-button menu does not itself require Full Access.
- **Notification permission** must have been granted (the app prompts on first launch).

---

## Extending

Add a `ReminderAction` case and a matching arm in `LocalNotificationScheduler.schedule(_:)`. Add any
new parameters to `ReminderRequest`. Call sites (keyboard/app) build a `ReminderRequest` and call
`schedule` — nothing else changes.

---

## Manual verification (physical device)

1. Build/install SnipKey on the connected iPhone and open it once; accept notification permission.
2. Enable the Reminders integration, choose the SnipKey destination, and enable keyboard Full Access.
3. Background SnipKey and open an empty Notes field with its keyboard.
4. Tap the bell beside Paste: confirm exactly `/remind ` is inserted and nothing is scheduled yet.
5. Enter `check the oven in 10 seconds`, then accept **Create reminder**.
6. Keep using Notes; confirm the banner arrives without reopening SnipKey.
7. Confirm the bell disappears in a populated field, including with the caret at the beginning.
