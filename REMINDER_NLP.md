# `/remind` Natural-Language Parsing — Specification

How SnipKey turns a typed `/remind …` command into a scheduled reminder, entirely **on-device**
(no network, no latency). Implemented in
[`SnipKeyboard/QWERTY/ReminderParseEngine.swift`](SnipKeyboard/QWERTY/ReminderParseEngine.swift)
(`ReminderParser`). For how it's wired into the keyboard/app, see
[`LOCAL_NOTIFICATIONS.md`](LOCAL_NOTIFICATIONS.md).

---

## Design principle

A good reminder system shouldn't just detect times — it should infer **intent** when no explicit
time is given. So the parser separates **which day** from **what time** and decides each
independently, instead of trusting `NSDataDetector`'s combined result (which defaults date-only
phrases to **noon** and doesn't recognize "noon", "next week", or bare "at 3").

**Time priority:** explicit clock time → time-of-day phrase → 9 AM default → now + 1 hour.

---

## Resolution pipeline

The text after the last `/remind` is resolved in this order; the first match wins:

1. **Relative duration** — `in <N> <unit>`:
   - `second` / `minute` / `hour` → **exact** `now + offset`.
   - `day` / `week` / `month` → that future day at **9:00 AM**.
2. **`next week` / `next month`** → next **Monday** 9:00 AM / **first of next month** 9:00 AM.
3. **Time-of-day phrase** (deterministic map, below) → that time, on the day `NSDataDetector` finds
   (or **today** if none).
4. **`NSDataDetector` date**:
   - with an explicit **clock time** (`3pm`, `3:30`) → honor exactly;
   - with **no time**, future day → **9:00 AM**; vague **today** → **now + 1 hour**.
5. **Bare `at <hour>`** (e.g. "at 3") → that hour **assuming PM**, nearest future.
6. **Nothing temporal** → **now + 1 hour**.

**Past-time roll:** any time that resolves to **today but already passed** rolls to **tomorrow**
(e.g. "at 3pm" typed at 5pm). Explicitly future days are never rolled.

**Pill gating:** the "Create reminder" pill appears once there's a real **task** *or* an explicit
time. `/remind` with nothing typed yet shows nothing.

---

## Time-of-day mapping

| Phrase | Time | | Phrase | Time |
|---|---|---|---|---|
| morning / this morning | 9:00 AM | | evening / this evening | 6:00 PM |
| noon / lunchtime | 12:00 PM | | tonight | 7:00 PM |
| afternoon / this afternoon | 3:00 PM | | before bed | 9:00 PM |
| | | | midnight | 12:00 AM |

---

## Examples & expected output

Reference "now" for the relative examples: **Thursday, June 4, 3:23 PM**.

| You type `/remind …` | Title (body) | Fires |
|---|---|---|
| `me to call John` | Call John | now + 1 hour → today 4:23 PM |
| `me later` | Later | now + 1 hour → today 4:23 PM |
| `me this afternoon` | Reminder | today 3:00 PM *(→ tomorrow if 3 PM passed)* |
| `me tonight` | Reminder | today 7:00 PM |
| `me tomorrow` | Reminder | tomorrow (Fri) 9:00 AM |
| `me tomorrow to pay rent` | Pay rent | tomorrow (Fri) 9:00 AM |
| `me next week` | Reminder | Mon Jun 8, 9:00 AM |
| `me next month` | Reminder | Wed Jul 1, 9:00 AM |
| `me on Friday` | Reminder | Fri Jun 5, 9:00 AM |
| `me this Friday` | Reminder | Fri Jun 5, 9:00 AM |
| `me April 15` | Reminder | Apr 15, 9:00 AM |
| `me April 15 at 5pm` | Reminder | Apr 15, 5:00 PM |
| `me at 3pm` | Reminder | today 3:00 PM (→ tomorrow if passed) |
| `me at 3:30` | Reminder | today 3:30 PM (→ tomorrow if passed) |
| `me at 3` | Reminder | today 3:00 PM (PM assumed; → tomorrow if passed) |
| `me in 2 hours` | Reminder | today 5:23 PM (exact) |
| `me in 30 minutes` | Reminder | today 3:53 PM (exact) |
| `me in 15 seconds` | Reminder | today 3:23 PM + 15s (exact) |
| `me in 3 days` | Reminder | Sun Jun 7, 9:00 AM |
| `me in 2 weeks` | Reminder | Thu Jun 18, 9:00 AM |
| `me to check in at 5pm` | Check in | today 5:00 PM |
| `me to take medicine this morning` | Take medicine | today 9:00 AM (→ tomorrow if passed) |
| `me before bed to floss` | Floss | today 9:00 PM |
| `me at noon` | Reminder | today 12:00 PM (→ tomorrow if passed) |
| `` (just `/remind`) | — | no pill |
| `me to` | — | no pill |

Notes:
- **Body extraction** strips the `/remind` trigger, lead-ins ("me", "to", "please"), the detected
  time/date phrase, and dangling trailing connectors — then capitalizes. "check **in** at 5pm"
  correctly keeps "Check in" (the time-of-day logic never treats "in" as a connector here).
- The reminder is scheduled by the shared `LocalNotificationScheduler` with title **"Reminder"** and
  the body as the message, so it also appears in the in-app Reminders list and the bell badge.

---

## Limitations (V1)

- **No context-aware defaults** — "dinner tomorrow" is 9 AM, not 6 PM. Reminder content does not
  influence the time. (A possible future enhancement.)
- A **bare future day with no time** uses 9 AM (e.g. "next monday" → Mon 9 AM), and a vague "today"
  with no time uses now + 1 hour.
- `NSDataDetector` resolves a day-only **explicit calendar date in the past** (e.g. "April 15" when
  it's June) to that past date; the system simply never fires it (harmless no-op).
- Parsing is English-oriented (driven by `NSDataDetector` + the English phrase maps above).
