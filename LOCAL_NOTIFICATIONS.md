# Keyboard-Triggered Local Notifications

How the **keyboard extension** (`SnipKeyboard`) gets a local notification scheduled when the user
taps the 🔔 button — and why it fires even while the main app (`SnipKey`) stays suspended in the
background.

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

```
┌──────────────────────────────┐         ┌─────────────────────────────┐
│       SnipKeyboard (ext)      │         │       SnipKey (main app)     │
│                               │         │                             │
│  🔔 toolbar button            │         │  NotificationPresenter       │
│      │ tap                    │         │   • sets UN delegate (init)  │
│      ▼                        │         │   • requests auth once       │
│  KeyboardActions.requestRemin │         │     (LocalNotificationSched- │
│      │  (Full Access?)        │         │      uler.requestAuth…)      │
│      ▼                        │         │   • presents banner if the   │
│  LocalNotificationScheduler   │         │     app is FOREGROUND at fire│
│   .schedule(ReminderRequest)  │         └─────────────────────────────┘
│      │                        │
│      ▼  UNUserNotificationCenter.add(+delay trigger)
│   ───────────────────────────────────────────►  system delivers later,
│                                                   app state irrelevant
└──────────────────────────────┘
```

1. App is launched once → `NotificationPresenter.bootstrap()` sets the delegate, and
   `LocalNotificationScheduler.requestAuthorizationIfNeeded()` prompts for permission.
2. User backgrounds SnipKey (don't force-kill), switches to any app, taps 🔔 in the keyboard.
3. The keyboard (Full Access) calls `LocalNotificationScheduler.schedule(...)` → the system holds
   the timer.
4. After the delay (10s DEBUG / 120s release) the banner appears — no reopening required.

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
- Keyboard: 🔔 button (`KeyboardToolbarView`) → `KeyboardActions.requestReminder`, wired in
  `KeyboardViewController` where `hasFullAccess` is known → `LocalNotificationScheduler.schedule`.
- App: 🔔 toolbar button on the Snippets screen (`HomeView2`) presents `RemindersView` as a sheet.

## Button UX & multiple reminders

- The keyboard 🔔 uses `SuggestionPillButtonStyle` (instant pressed highlight) and a 44pt-wide,
  full-toolbar-height hit cell (`.contentShape(Rectangle())`) — matching the suggestion pills, so
  taps register reliably and give feedback.
- Each tap schedules an **independent** notification: a unique `identifierPrefix + UUID` identifier
  plus a distinct `subtitle` ("Fires at <time>") so two reminders never look identical or coalesce.
- `RemindersView` filters by `LocalNotificationScheduler.identifierPrefix`, lists **Upcoming**
  (pending, by fire time) and **Delivered**, and is the diagnostic for "did it actually schedule?".

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

- **Full Access** must be enabled for the keyboard. Without it the keyboard sandbox blocks the
  scheduling call. SnipKey already requires Full Access for its core snippet/clipboard features, so
  this adds nothing new. `requestReminder` checks `hasFullAccess` and no-ops with a log otherwise.
- **Notification permission** must have been granted (the app prompts on first launch).

---

## Extending

Add a `ReminderAction` case and a matching arm in `LocalNotificationScheduler.schedule(_:)`. Add any
new parameters to `ReminderRequest`. Call sites (keyboard/app) build a `ReminderRequest` and call
`schedule` — nothing else changes.

---

## Testing (simulator + argent MCP)

1. **Build** `SnipKey` (`xcodebuild -project SnipKey.xcodeproj -scheme SnipKey -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' build`). A membership mistake on the shared file surfaces as an "unresolved identifier" error in the **SnipKeyboard** build.
2. **Run** the app once, accept the notification prompt.
3. **Settings → General → Keyboard → Keyboards → Add → SnipKey**, then **Allow Full Access**.
4. Background SnipKey (Home, don't swipe-kill). Open Notes, switch to the SnipKey keyboard, tap 🔔.
5. Keep using Notes; after ~10s (DEBUG) the banner fires **without reopening SnipKey**. Release builds use 120s.

> Drive with argent: `launch-app` SnipKey, then `launch-app` Notes, discover the 🔔 via
> `describe` / `debugger-component-tree`, `gesture-tap` it, wait, observe the banner. Call
> `stop-all-simulator-servers` when done.
