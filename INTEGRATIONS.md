# SnipKey Integrations

An extensible system for connecting SnipKey to other apps. The first integration is the native iOS
**Reminders app** (EventKit). The design keeps the existing local-reminder behavior fully intact and
adds **Reminders App** as an optional reminder *destination* — only one destination is ever active,
so a reminder is never created in both.

See also: **[`LOCAL_NOTIFICATIONS.md`](LOCAL_NOTIFICATIONS.md)** (the existing SnipKey notification
path + the `/remind` NLP parser this routes) and **[`REMINDER_NLP.md`](REMINDER_NLP.md)**.

---

## What the user sees

`Settings → Integrations → Reminders`:

- **Enable Reminders** — master switch. **Off by default**; until it's on, behavior is unchanged.
- **Allow Reminders access** — a **Grant** button. This is the *only* place the EventKit permission
  prompt is presented (the keyboard cannot prompt). Granted to the **main app**.
- **Create reminders in** — a picker: **SnipKey** (default) or **Reminders App**. "Reminders App"
  is selectable only once permission is granted.

Both keyboard reminder paths honor the destination: the typed `/remind … <time>` **Create reminder**
pill *and* the 🔔 quick button.

---

## Components

| File | Target(s) | Responsibility |
|---|---|---|
| [`SnipKey/Shared/Reminders/ReminderDestination.swift`](SnipKey/Shared/Reminders/ReminderDestination.swift) | **Both** | The `.snipKey` / `.remindersApp` enum. The app picks it; the keyboard routes by it. |
| [`SnipKey/Shared/Reminders/EventKitReminderService.swift`](SnipKey/Shared/Reminders/EventKitReminderService.swift) | **Both** | Single encapsulation of EventKit: `authorizationStatus()`, `requestAccess` (app-only prompt), and `create(title:dueDate:)` (off-main `EKReminder` write with an `EKAlarm` so it fires). |
| `SnipKey/Features/Settings/Integrations/AppIntegration.swift` | App | `IntegrationID` + `IntegrationDescriptor` + `IntegrationRegistry` — the lightweight, extensible list model. |
| `SnipKey/Features/Settings/Integrations/IntegrationsView.swift` | App | The Integrations list (driven entirely by the registry). |
| `SnipKey/Features/Settings/Integrations/RemindersIntegrationView.swift` | App | Enable toggle + permission grant + destination picker. |

Persistence: `SettingsModel.remindersIntegrationEnabled` (Bool) and `SettingsModel.reminderDestination`
(`ReminderDestination`, a `Codable` enum, persisted like `afterPasteAction`). Both are mirrored to the
`group.snipkey` App Group via `AppGroupSettings` (new `setString`/`string` helpers + keys), exactly
like every other keyboard setting, so the keyboard can read them synchronously at launch.

---

## Reminder creation flow

```
Keyboard (reads destination ONCE per session in viewDidLoad — never on the keystroke path)
  /remind "Create reminder" pill ┐
  🔔 quick button                ┘──► KeyboardViewController.routeReminder(title, body, fireDate)
        │
        ├─ effectiveReminderDestination == .snipKey
        │     → LocalNotificationScheduler.schedule(...)            (existing behavior, unchanged)
        │
        └─ effectiveReminderDestination == .remindersApp
              → EventKitReminderService.create(...)   PRIMARY: write the EKReminder directly,
                                                       using the permission granted in the app
                 └─ on failure (not authorized / no calendar / save error):
                       fall back to LocalNotificationScheduler.schedule(...) so the reminder
                       is never silently lost.
```

`effectiveReminderDestination` is `.remindersApp` only when the integration is enabled **and** that
destination is selected; otherwise `.snipKey`. The selected destination always wins.

### Why "try direct, then fall back"

Permission is granted to the **main app**. The open question is whether the **keyboard extension's
process** can use that grant: EventKit authorization goes through iOS's TCC privacy system, which
evaluates the *calling process*, and the keyboard has its own bundle-ID
(`jrtv-projects.SnipKey.SnipKeyboard`) distinct from the app (`jrtv-projects.SnipKey`). Unlike
`UNUserNotificationCenter.current()` — which is documented to operate *on behalf of the containing
app* — EventKit has no such documented behavior.

So the keyboard **attempts** the direct write (gated by `EventKitReminderService.isAuthorized`, which
reflects the keyboard's own process). If the process can use the grant, the `EKReminder` is created
instantly — single artifact, no app reopen. If iOS reports the keyboard's process unauthorized,
`create` returns `false` and the caller falls back. **This must be confirmed on-device** (see below);
the architecture works either way because the EventKit write is encapsulated behind one service.

### Contingency (not yet built)

If the on-device spike shows the keyboard can't use the app's grant, the fallback can be upgraded to
"reliable + sync later": the keyboard schedules a SnipKey notification with a *known* id
(`ReminderRequest.identifier`) **and** enqueues a hand-off record to the App Group; the main app
materializes the real `EKReminder` on next launch and cancels the still-pending notification. The
`ReminderRequest.identifier` hook is already in place; the `PendingReminderQueue` + main-app drain are
deferred until the spike proves they're needed.

---

## Performance

Nothing here touches the keystroke hot path. The destination is read once per session and cached;
`/remind` parsing (`ReminderParser`/`runReminderEvaluation`) is unchanged. `EventKitReminderService`
only allocates its `EKEventStore` the first time a reminder is actually created (a rare, explicit
user tap), off the main thread via `Task.detached` — never during typing, well under the keyboard's
~48 MB ceiling.

---

## Extending — adding a second integration

1. Add a case to `IntegrationID`.
2. Add an `IntegrationDescriptor` to `IntegrationRegistry.all` (title, subtitle, icon, detail view).
3. Build its detail view + any dedicated service (mirroring `EventKitReminderService`).

The Integrations list loop needs no changes. Keep runtime behavior in a dedicated service, not in the
descriptor — the descriptor is presentation only.

---

## Timers (`/timer`) integration

The second integration. `Settings → Integrations → Timers` enables a `/timer` command: typing
`/timer 1h 30m` (or `15s`, `90`, `1h 5m 10s` — any mix of h/m/s units, plurals, or a bare number that
defaults to seconds) shows a **Create timer · 01:30:00** pill. Tapping it schedules a **SnipKey local
notification** that fires when the countdown ends — the user stays in their current app.

> AlarmKit (a system-managed countdown with a Lock Screen / Dynamic Island Live Activity) was
> evaluated and **removed**: only the *foreground app* can create an AlarmKit timer / host its Live
> Activity — a keyboard extension can't — so it would have required briefly switching into SnipKey on
> every `/timer`. We chose the simpler in-place local-notification timer instead.

Mirrors the `/remind` scaffolding (parser → observable state → pill → toast → router). Pieces:

| File | Target(s) | Responsibility |
|---|---|---|
| `SnipKeyboard/QWERTY/TimerParseEngine.swift` | App + Keyboard | `ParsedTimer` + `TimerParser` (multi-token duration sum, bare-number=seconds) + `TimerSuggestionState`. |
| `SnipKey/Features/Settings/Integrations/TimerIntegrationView.swift` | App | Enable Timers toggle + copy. |
| `SnipKey/Shared/Notifications/LocalNotificationScheduler.swift` | App + Keyboard | Reused — the timer's `ReminderRequest(fireDelay:)` notification path. |

Routing (`KeyboardViewController.routeTimer`): `LocalNotificationScheduler.schedule(fireDelay:)`. The
`/timer` pill (`CreateTimerPill`) + toast (`.timerToast()`) live in `QWERTYKeyboardView`, on both the
V1/V2 roots, and only appear when the integration is enabled (`timerIntegrationEnabled`, cached per
session). Persistence + App-Group mirroring follow the Reminders pattern; `IntegrationRegistry.enabledCount`
includes it. Needs Full Access (already a SnipKey baseline) + notification permission (requested at
app launch) — no AlarmKit, no extra entitlement, no widget.

---

## Verifying

1. **Build both targets:**
   `xcodebuild -project SnipKey.xcodeproj -scheme SnipKey -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' build`
   (a dual-membership mistake surfaces as an "unresolved identifier" in the **SnipKeyboard** build).
2. **★ Decisive keyboard-EventKit spike (real device):** after granting Reminders access in
   Integrations, observe `EKEventStore.authorizationStatus(for:.reminder)` **from the keyboard
   process** and attempt one save.
   - Authorized + save succeeds → the keyboard's direct write works; the fallback is just insurance.
   - Denied / save fails → build the contingency (`PendingReminderQueue` + drain).
3. **E2E:** SnipKey destination (regression) → notification fires; Reminders App destination →
   reminder appears in Apple Reminders with due time + alarm and no SnipKey notification; revoke
   permission mid-flow → falls back cleanly; Reset → integration off + destination back to SnipKey.
