# ⌨️ SnipKey — Save Time, Type Quicker

[![iOS 17+](https://img.shields.io/badge/iOS-17%2B-blue?logo=apple)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)](https://swift.org/)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-Framework-blue?logo=swift)](https://developer.apple.com/swiftui/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![App Store](https://img.shields.io/badge/App%20Store-Download-blue?logo=apple)](https://apps.apple.com/us/app/snipkey/id6480381137)
[![GitHub](https://img.shields.io/badge/GitHub-Open%20Source-black?logo=github)](https://github.com/jtvargas/SnipKey)

**SnipKey** is a native iOS app that lets you save text snippets, URLs, images, and PDFs — then paste them anywhere using a custom keyboard. No more retyping. No more switching apps to copy something. Just tap and type.

Built with **SwiftUI** and **SwiftData**, SnipKey is designed to be fast, private, and simple. Your data stays on your device (with optional iCloud sync through Apple's own CloudKit), and nothing is ever shared with third parties. No analytics. No tracking. No ads.

The app is **completely free** and **open source**. Optional tips are available if you'd like to support ongoing development. View the source code, report issues, or contribute on [GitHub](https://github.com/jtvargas/SnipKey).

---

## Table of Contents

- [Why SnipKey?](#why-snipkey)
- [Use Cases](#use-cases)
- [Features](#features)
- [Privacy & Security](#privacy--security)
- [Screenshots](#screenshots)
- [Tech Stack](#tech-stack)
- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
- [Dependencies](#dependencies)
- [Contributing](#contributing)
- [Roadmap & Vision](#roadmap--vision)
- [License](#license)
- [Links](#links)

---

## Why SnipKey?

We all have text we type over and over — email addresses, phone numbers, canned replies, code snippets, addresses, URLs. Copying and pasting works most of the time, but it breaks when:

- An app **blocks paste** in its text fields
- You need to **switch between apps** just to grab a piece of text
- You're filling out the **same form fields** repeatedly
- You want quick access to **dozens of snippets** without a clipboard manager cluttering your workflow

SnipKey solves all of this with a **custom keyboard** that sits right where you type. Your snippets are always one tap away, in any app, in any text field.

---

## Use Cases

### Bypass Copy/Paste Restrictions

Some apps and websites intentionally disable paste in their text fields (banking apps, exam portals, certain forms). Because SnipKey works as a **keyboard extension**, it injects text directly into the input field character by character — the same way you'd type it manually. This means it works in fields where paste is blocked, giving you a way to enter your saved content without retyping it.

### Frequently Used Text

Save the things you type every day and access them instantly:

- **Email signatures** and sign-off templates
- **Addresses** — home, work, shipping
- **Phone numbers**, IDs, account numbers
- **Canned responses** for customer support, sales, or social media
- **Standard replies** — "Thanks for reaching out!", "I'll get back to you shortly"

### Developers & Power Users

- Paste **code snippets**, **API keys**, **config values**, or **terminal commands**
- Quick access to **regex patterns**, **SQL queries**, or **boilerplate code**
- Store **environment variables** or **connection strings** you use across projects

### Form Filling

Stop retyping the same information across apps:

- Job applications (cover letter paragraphs, skills lists)
- Medical forms (medications, allergies, insurance info)
- E-commerce checkouts (shipping details, discount codes)
- Government/banking forms (ID numbers, tax info)

### Content Creation

- **Social media bios**, hashtag sets, or link-in-bio URLs
- **Email templates** for outreach, follow-ups, or newsletters
- **Markdown snippets** for documentation or blog posts

### Sensitive Information (with Biometric Lock)

Mark any snippet as **secure** and it will require FaceID or TouchID before it can be viewed or pasted:

- Recovery codes, backup keys
- Confidential notes
- Private reference numbers

---

## Features

| Feature | Description |
|---|---|
| **Custom Keyboard** | Access all your snippets from any app via a dedicated keyboard extension |
| **Full QWERTY Keyboard** | Complete replacement keyboard with letters, numbers, symbols — no need to switch keyboards |
| **Next-Gen Touch Engine** | Native-feel typing that quietly corrects off-center taps, biases toward the letter you likely meant, and learns your personal thumb offsets over time — keys never visibly move. On by default. |
| **Slash Commands** | Type `/` followed by a snippet name to trigger inline autocomplete and paste snippets without leaving the typing flow |
| **4 Snippet Types** | Save text, URLs, images, and PDFs |
| **Tag System** | Organize snippets with custom tags, each with its own name, SF Symbol icon, and color |
| **Biometric Security** | Lock sensitive snippets behind FaceID or TouchID |
| **Keyboard Reminders** | Tap 🔔 on the keyboard for a quick reminder, or type `/remind me to … at <time>` to schedule one in natural language; view upcoming & delivered reminders in the app, with a badge while reminders are pending |
| **iCloud Sync** | Sync across all your devices via Apple's CloudKit |
| **Bulk Creation** | Paste a list of items to create multiple snippets at once |
| **Search & Filter** | Full-text search across titles, content, and tags with tag-based filtering |
| **Configurable Paste Action** | Choose what happens after pasting: return, space, switch keyboard, or nothing |
| **Usage Tracking** | See when and how often each snippet is used; sort by recently used |
| **Dark Mode** | System, light, or dark appearance |
| **Onboarding** | Guided setup walkthrough to get the keyboard enabled quickly |
| **Free Forever** | No subscriptions, no ads, no paywalls — optional tips to support development |

### Intelligent Typing Engine (V2)

The custom keyboard ships with a **next-generation touch engine** (on by default) that makes typing
more accurate and forgiving without ever moving the keys you see. In plain terms: each letter has a
soft, invisible "catch zone" that quietly flexes toward what you most likely meant.

- **2D probabilistic key selection** — instead of a rigid grid, a touch resolves by combining *where*
  you tapped with *what you're likely typing*, in both axes (handles cross-row near-misses, not just
  left/right).
- **Automatic per-user adaptation** — the keyboard learns where *your* thumbs actually land relative
  to each key and shifts the invisible targets to match. No setup, no "training mode" — it just gets
  better as you type, on-device only.
- **Language-aware boundaries** — common letters and predictable letter-pairs (e.g. `th→e`, `qu→`vowel)
  get slightly larger catch zones; correction backs off at the start of a word where there's no
  context yet.
- **Native feel preserved** — commit-on-touch-down, instant highlight, callouts, accent long-press,
  and space-cursor all unchanged; the engine only changes *which key a near-boundary tap resolves to*.
- **Safe by design** — a deliberate, centered tap is never overridden; correction is disabled in
  password / URL / email / number fields; all learning stays on your device and is never transmitted.

It can be toggled in **Settings → Experimental → Next-Gen Touch Engine**. Engineering details live in
[`V2_KEYBOARD_ARCHITECTURE.md`](V2_KEYBOARD_ARCHITECTURE.md) and
[`V2_KEYBOARD_NEXTGEN_PLAN.md`](V2_KEYBOARD_NEXTGEN_PLAN.md).

### Reminders

Tap the 🔔 on the keyboard's toolbar to set yourself a reminder — it schedules a local notification
that fires in **2 minutes**. Because the keyboard schedules it directly, the notification fires even
if you never reopen SnipKey (a backgrounded app is suspended and can't schedule on demand). Each tap
is an independent reminder.

You can also schedule in **natural language**: type `/remind me to call the doctor at 3PM` and a
**"Create reminder"** suggestion pill appears. Tapping it removes the text and schedules the reminder,
with a confirmation banner. It's intent-aware about *when*: `at 3pm` / `at 3:30` (today, or tomorrow
if passed), `tomorrow` / `Friday` / `April 15` (→ 9 AM), `this afternoon` / `tonight` / `before bed`
(deterministic times), `next week` / `next month`, relative `in 15 seconds` … `in 2 weeks`, and a
plain `/remind call John` with no time (→ in 1 hour). Parsing runs entirely on-device — no network,
no latency. Full rules: [`REMINDER_NLP.md`](REMINDER_NLP.md).

In the app, the **Snippets** screen has a 🔔 toolbar button that opens a **Reminders** list of your
upcoming and recently delivered reminders (swipe to delete, or clear all). When reminders are
pending, the bell shows a small red count badge.

Requires **Allow Full Access** for the keyboard and notification permission (the app asks once).
Engineering details live in [`LOCAL_NOTIFICATIONS.md`](LOCAL_NOTIFICATIONS.md).

---

## Privacy & Security

Privacy is the core principle behind SnipKey. Here's exactly what happens with your data:

### What stays on your device

- **All snippet data** (text, URLs, images, PDFs) is stored locally using Apple's SwiftData framework
- **Tags, settings, and preferences** are stored locally
- **Nothing is uploaded to any server** we own or operate

### iCloud Sync (optional)

- If you're signed into iCloud, snippets sync across your devices using **Apple's CloudKit**
- This is Apple's own infrastructure — your data goes from your device to your iCloud account and nowhere else
- We have **zero access** to your iCloud data

### No third-party data sharing

- **No analytics SDKs** — we don't track what you do in the app
- **No crash reporting services** — no Crashlytics, no Sentry, nothing
- **No advertising SDKs** — no ads, ever
- **No personal data from your snippets is shared with any third party**
- The only third-party SDK is **RevenueCat**, used solely to process optional tips — it does not access your snippets or any personal content

### Keyboard extension & Full Access

- The keyboard extension can work **without Full Access** for text snippets
- **Full Access is only needed** if you want to paste images or PDFs (which requires clipboard access)
- Even with Full Access enabled, **no data is transmitted anywhere** — it's used only for local clipboard operations
- Apple requires showing the "Full Access" prompt for any keyboard that interacts with the clipboard; this is an iOS requirement, not a choice to collect data

### Biometric protection

- Snippets marked as secure require **FaceID or TouchID** to view or paste
- Authentication is handled entirely by Apple's **LocalAuthentication** framework on-device

---

## Screenshots

<!-- 
Add screenshots here. Recommended format:

<p align="center">
  <img src="screenshots/home.png" width="200" alt="Home Screen">
  <img src="screenshots/keyboard.png" width="200" alt="Custom Keyboard">
  <img src="screenshots/detail.png" width="200" alt="Snippet Detail">
  <img src="screenshots/tags.png" width="200" alt="Tag Management">
</p>

To add screenshots:
1. Create a `screenshots/` directory in the repo root
2. Add your screenshots (PNG or JPEG)
3. Update the paths above
-->

*Screenshots coming soon.*

---

## Tech Stack

| Technology | Purpose |
|---|---|
| **SwiftUI** | User interface |
| **SwiftData** | Local data persistence |
| **CloudKit** | iCloud sync |
| **LocalAuthentication** | FaceID / TouchID |
| **TipKit** | In-app tips and onboarding hints |
| **RevenueCat** | Optional tip jar (in-app purchases) |
| **IBM Plex Mono** | Custom monospace font |

---

## Project Structure

```
SnipKey/
├── SnipKeyApp.swift                    # App entry point (@main)
├── SnipKeyDataManager.swift            # Shared SwiftData ModelContainer
├── Core/
│   └── Colors.swift                    # Color extensions (system colors + hex)
├── Components/
│   ├── AboutApp.swift                  # Developer bio / about screen
│   ├── TipDevView.swift                # Tip jar UI (RevenueCat)
│   ├── TagColorPicker.swift            # Color palette picker for tags
│   ├── TagColorIndicator.swift         # Colored circle tag indicator
│   ├── MorphingSymbolView.swift        # Animated SF Symbol transitions
│   ├── StaggeredImagesList.swift       # Overlapping card-style media gallery
│   └── LoopVideoView.swift             # Looping video player
├── Helper/
│   ├── Biometrics.swift                # FaceID / TouchID authentication
│   ├── Keyboard.swift                  # Keyboard utilities (clipboard, extension detection)
│   ├── RevenueCatManager.swift         # RevenueCat singleton manager
│   ├── AppIconProvider.swift           # App icon name resolver
│   ├── Views.swift                     # View extensions (hideKeyboard, limitText, pressable)
│   └── Strings.swift                   # String extensions (HMAC, URL validation)
├── Tips/
│   └── HomeTips.swift                  # TipKit definitions
└── Features/
    ├── Home/View/
    │   ├── HomeView2.swift             # Primary home view (TabView: Snippets/Settings/Search)
    │   ├── SearchView.swift            # Search with tag browser
    │   └── HomeSnippetList.swift       # Snippet list component
    ├── Snippets/
    │   ├── SnippetModel.swift          # SwiftData models (SnippetItem, SnipTag, SnippetFile)
    │   ├── SnippetViewModel.swift      # Snippet CRUD operations
    │   └── Views/
    │       ├── SnippetForm.swift       # Create/edit form (single + bulk)
    │       ├── SnippetViewDetail.swift # Detail view with biometric lock
    │       ├── SnippetListItem.swift   # List row + keyboard grid item
    │       ├── SnippetTagForm.swift    # Tag selection + batch assignment
    │       ├── EditTagView.swift       # Edit tag (name, icon, color)
    │       ├── TagsView.swift          # Tags management list
    │       ├── SnippetContentForm.swift       # Dynamic content editor
    │       ├── SnippetContentViewDisplay.swift # Content display renderer
    │       ├── SnippetFilesView.swift  # Image gallery (masonry grid)
    │       ├── SnippetListEmpty.swift  # Empty state with typewriter animation
    │       ├── KeyboardStatusView.swift # Keyboard setup status
    │       └── ArrowSVG.swift          # Decorative arrow shape
    ├── Settings/
    │   ├── Model/SettingsModel.swift   # Settings data model + enums
    │   ├── ViewModel/SettingsViewModel.swift # Settings logic
    │   └── Views/SettingsView.swift    # Settings screen
    ├── Subscription/Views/
    │   └── SubscriptionView.swift      # Free app info screen
    └── OnBoarding/
        ├── OnBoardingModel.swift       # Boarding item struct
        ├── Model/Page.swift            # 5-page onboarding model
        └── Views/
            ├── OnBoardingView.swift    # Feature list onboarding
            ├── OnboardingStepperView.swift # Animated welcome walkthrough
            ├── WelcomeView.swift       # Tab-style welcome cards
            ├── BoardingCardView.swift  # Individual boarding card
            ├── Splashscreen.swift      # Splash screen
            └── KeyboardHelpGuideView.swift # Keyboard setup guide

SnipKeyboard/                           # Keyboard Extension Target
├── KeyboardViewController.swift        # UIInputViewController + QWERTY state management
├── KeyboardView.swift                  # SwiftUI keyboard UI (snippet grid + QWERTY toggle)
├── SnipKeyboard.entitlements           # Extension entitlements
├── Info.plist                          # Extension configuration
└── QWERTY/                             # Full QWERTY keyboard implementation
    ├── KeyboardDimensions.swift        # Responsive key sizing from screen width
    ├── QWERTYKeyboardState.swift       # @Observable render state + input tracking
    ├── KeyboardActions.swift           # textDocumentProxy closures via SwiftUI environment
    ├── QWERTYKeyboardLayout.swift      # Static key definitions (letters/numbers/symbols)
    ├── KeyButtonView.swift             # Key rendering with UIKit touch handling
    ├── KeyRowView.swift                # Row layout with edge-aware padding
    ├── QWERTYKeyboardView.swift        # Main keyboard view + toolbar with slash suggestions
    ├── KeyPopupView.swift              # UIKit balloon popup for key press feedback
    └── SlashCommandEngine.swift        # Slash command detection, fuzzy matching, state
```

---

## Getting Started

### Prerequisites

- **Xcode 15.3** or later
- **iOS 17.0+** device or simulator
- An Apple Developer account (for running on a physical device)

### Setup

1. **Clone the repository**

   ```bash
   git clone https://github.com/jtvargas/SnipKey.git
   cd SnipKey
   ```

2. **Open the project**

   ```bash
   open SnipKey.xcodeproj
   ```

3. **Select the scheme and destination**

   - Scheme: `SnipKey`
   - Destination: any iOS 17+ simulator or your device

4. **Build and run** (`Cmd + R`)

### Notes

- **Code Signing**: The project's `DEVELOPMENT_TEAM` is intentionally left blank. Before building on a physical device, open the project in Xcode, go to **Signing & Capabilities** for both the `SnipKey` and `SnipKeyboard` targets, and select your own development team. Simulator builds work without this step.
- **RevenueCat (tip jar)**: The tip jar feature uses a public RevenueCat API key that ships with the app. Contributors don't need to set up their own RevenueCat account — the tips section will work as-is.
- **iCloud Sync**: Requires an active iCloud account. On the simulator, sign into iCloud via Settings to test sync.
- **Keyboard Extension**: After building, go to **Settings > General > Keyboard > Keyboards > Add New Keyboard** and enable SnipKey. The app includes a guided setup walkthrough.

### Build from the command line

```bash
# Build for simulator
xcodebuild -project SnipKey.xcodeproj -scheme SnipKey \
  -destination 'platform=iOS Simulator,name=iPhone 15' build

# Clean build
xcodebuild -project SnipKey.xcodeproj -scheme SnipKey clean build
```

---

## Dependencies

All dependencies are managed via **Swift Package Manager** and resolve automatically when you open the project.

| Package | Purpose |
|---|---|
| [AlertToast](https://github.com/elai950/AlertToast) | Toast / banner notifications |
| [CloudKitSyncMonitor](https://github.com/ggrkumar/CloudKitSyncMonitor) | iCloud sync status indicator |
| [Pow](https://github.com/EmergeTools/Pow) | Animations and effects |
| [RevenueCat](https://github.com/RevenueCat/purchases-ios-spm) | In-app purchase tips (tip jar only) |
| [SwiftUIMasonry](https://github.com/nicklama/SwiftUIMasonry) | Masonry grid layout |
| [SymbolPicker](https://github.com/xnth97/SymbolPicker) | SF Symbol picker for tags |

---

## Contributing

Contributions are welcome! Whether it's a bug fix, new feature, or documentation improvement — we appreciate your help.

### How to contribute

1. **Fork** the repository
2. **Create a branch** for your feature or fix

   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make your changes** following the existing code style (see [AGENTS.md](AGENTS.md) for detailed conventions)
4. **Test your changes** — run the app on a simulator, verify the keyboard extension works
5. **Submit a Pull Request** with a clear description of what you changed and why

### Guidelines

- **Follow the MVVM architecture** — models in `*Model.swift`, view models in `*ViewModel.swift`, views in SwiftUI
- **Use the existing code style** — see [AGENTS.md](AGENTS.md) for naming conventions, import order, state management patterns, and more
- **Privacy first** — do not add analytics, tracking, or any third-party SDK that collects user data. This is a hard rule.
- **No tests exist yet** — if you'd like to add tests, that's a highly valued contribution
- **Keep the keyboard extension lightweight** — it runs in a constrained memory environment

### Reporting Issues

Found a bug or have a feature request? You can:

- [Open an issue](https://github.com/jtvargas/SnipKey/issues) on GitHub
- [Submit a feature request](https://snipkey.canny.io) on Canny

---

## Roadmap & Vision

SnipKey today is a snippet-only keyboard — you switch to it when you need a snippet, then switch back to your regular keyboard to keep typing. The long-term vision is to make SnipKey a **full replacement keyboard** that you never need to switch away from. Type normally, access your snippets inline, and never touch the globe icon again.

Think of it like [Grammarly's iOS keyboard](https://www.grammarly.com/mobile): a complete QWERTY keyboard that works exactly like the native one, with powerful features layered on top through a suggestion bar. That's where SnipKey is headed — but instead of grammar suggestions, the power layer is **instant snippet access, slash commands, and emoji shortcodes**.

### Phase 1 — Full QWERTY Keyboard ✅

> **Status: Complete.**

Built a complete QWERTY keyboard that behaves like the native iOS keyboard:

- **All keys functional** — letters, numbers, symbols, shift, caps lock, delete, return, space, globe/language switch
- **Layout parity** — matches native iOS key sizing, spacing, and row gaps (~258pt total height)
- **Key press feedback** — UIKit balloon popup + background highlight using CALayer (zero SwiftUI state)
- **Snippet toggle** — dedicated button to switch between QWERTY and snippet list views
- **Performance optimized** — UIKit `KeyTouchArea` for low-latency touch handling, `@Observable` equality guards, `static let` cached layouts

### Phase 2 — Slash Commands for Quick Snippet Access ✅

> **Status: Complete.**

Type `/` to trigger inline snippet autocomplete without leaving the typing flow:

- Type `/` followed by a snippet name to see matching suggestions in the **toolbar above the keys**
- **Fuzzy matching** — prefix, word-prefix, substring, and ordered character matching (e.g., `/addr` surfaces "Address - Home")
- Tap a suggestion to replace the `/query` text with the full snippet content
- **Biometric support** — secure snippets require FaceID/TouchID before insertion
- **Usage tracking** — `lastTimeUsed` and `usedCount` updated on each use
- **Slash trigger button** — toolbar button to quickly insert `/` and activate suggestions
- Text and URL snippets only (image/PDF not applicable for inline insertion)

**Example flow:**
```
User types:  "Hi, my address is /addr"
Suggestion bar shows:  [ Address - Home ] [ Address - Work ] [ Address - Shipping ]
User taps "Address - Home"
Result:  "Hi, my address is 123 Main St, Apt 4B, New York, NY 10001"
```

### Phase 3 — Emoji Shortcodes

Bring the developer-friendly emoji shortcode experience (familiar from Slack, Discord, and GitHub) directly into the keyboard:

- Type `:` followed by an emoji name (e.g., `:smile`, `:thumbsup`, `:fire`, `:rocket`) to trigger emoji autocomplete
- Matching emojis appear in the suggestion bar above the keys
- Tap to inject the emoji character directly into the text field
- Support **common shortcode conventions** compatible with Slack, Discord, and GitHub naming
- Searchable — typing `:heart` would show :heart:, :heartbeat:, :heart_eyes:, and other heart-related emojis

**Example flow:**
```
User types:  "Great work! :rock"
Suggestion bar shows:  [ :rocket: ] [ :rock: ] [ :rocking_chair: ]
User taps ":rocket:"
Result:  "Great work! 🚀"
```

### How to Contribute to the Roadmap

All three phases are open for contribution. If you're interested in working on any of these:

1. Check the [GitHub Issues](https://github.com/jtvargas/SnipKey/issues) for existing tasks or discussions
2. Submit ideas or vote on features at [snipkey.canny.io](https://snipkey.canny.io)
3. Open a PR — even partial implementations (e.g., a single key row, a basic slash command parser) are welcome as building blocks

The keyboard extension lives in `SnipKeyboard/` — see [AGENTS.md](AGENTS.md) for technical details on how the extension works, its memory constraints, and the NotificationCenter communication pattern between SwiftUI and UIKit.

---

## License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.

---

## Links

| | |
|---|---|
| **App Store** | [Download SnipKey](https://apps.apple.com/us/app/snipkey/id6480381137) |
| **GitHub** | [Source Code](https://github.com/jtvargas/SnipKey) |
| **Website** | [snipkey.jrtv.online](https://snipkey.jrtv.online) |
| **Privacy Policy** | [snipkey.jrtv.online/privacy-policy](https://snipkey.jrtv.online/privacy-policy) |
| **Feature Requests** | [snipkey.canny.io](https://snipkey.canny.io) |

---

Built with care by [Jonathan Taveras](https://github.com/jtvargas). Open source. No tracking. No ads. Just a useful keyboard.
