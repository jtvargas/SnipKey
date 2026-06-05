# AGENTS.md — SnipKey iOS Application

Guidelines for AI coding agents working on this codebase. Read this before making any changes.

---

## Project Overview

**SnipKey** is a native iOS app (SwiftUI + SwiftData) that lets users create, organize, and quickly access text snippets, URLs, images, and PDFs via a custom keyboard extension.

| | |
|---|---|
| **Version** | 5.5 (main app), 5.0 (keyboard extension) |
| **Bundle ID** | `jrtv-projects.SnipKey` |
| **Min Deployment** | iOS 17.0 (base), iOS 26.0 in latest build configs |
| **Architecture** | MVVM with SwiftData |
| **Sync** | iCloud via CloudKit |
| **Monetization** | Free app with optional tips via RevenueCat |
| **Privacy** | No analytics, no tracking, no third-party data sharing |

**Targets:**

- `SnipKey` — Main iOS application
- `SnipKeyboard` — Custom keyboard extension (`jrtv-projects.SnipKey.SnipKeyboard`)

**Shared infrastructure:**

- **App Group:** `group.snipkey` (shared data between app and keyboard extension)
- **iCloud Container:** `iCloud.SnipKeyCloud`

---

## Build & Run

### Xcode (recommended)

Open `SnipKey.xcodeproj`, select the `SnipKey` scheme, pick a simulator or device, and press `Cmd + R`.

### Command line

```bash
# Build the main app (debug)
xcodebuild -project SnipKey.xcodeproj -scheme SnipKey -configuration Debug build

# Build for a specific simulator
xcodebuild -project SnipKey.xcodeproj -scheme SnipKey \
  -destination 'platform=iOS Simulator,name=iPhone 16' build

# Clean build
xcodebuild -project SnipKey.xcodeproj -scheme SnipKey clean build
```

### After building

The keyboard extension must be enabled manually:

1. Go to **Settings > General > Keyboard > Keyboards > Add New Keyboard**
2. Select **SnipKey**
3. (Optional) Enable **Allow Full Access** for image/PDF clipboard operations

---

## Testing

**No tests currently exist.** Test targets (`SnipKeyTests`, `SnipKeyUITests`) are defined in the Xcode scheme but contain no test files. Adding tests is a welcome contribution.

```bash
# Run all tests (when they exist)
xcodebuild test -project SnipKey.xcodeproj -scheme SnipKey \
  -destination 'platform=iOS Simulator,name=iPhone 16'

# Run a single test class
xcodebuild test -project SnipKey.xcodeproj -scheme SnipKey \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:SnipKeyTests/TestClassName

# Run a single test method
xcodebuild test -project SnipKey.xcodeproj -scheme SnipKey \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:SnipKeyTests/TestClassName/testMethodName
```

---

## Project Structure

```
SnipKey/
├── SnipKeyApp.swift                    # @main app entry point
├── ContentView.swift                   # [DEAD CODE] Default Xcode template, unused
├── SnipKeyDataManager.swift            # Shared SwiftData ModelContainer factory
├── SnipKey.entitlements                # App entitlements (iCloud, App Groups)
├── Info.plist                          # App configuration
├── IBMPlexMono-*.ttf                   # Custom fonts (Regular, Medium, SemiBold, Bold)
├── Assets.xcassets/                    # App icons, images, SVGs, colors
│
├── Core/
│   └── Colors.swift                    # Color extensions (system colors + hex init)
│
├── Components/
│   ├── AboutApp.swift                  # Developer bio / about screen
│   ├── TipDevView.swift                # Tip jar UI (RevenueCat products)
│   ├── TagColorPicker.swift            # Color palette picker for tags
│   ├── TagColorIndicator.swift         # Colored circle tag display
│   ├── MorphingSymbolView.swift        # Animated SF Symbol transitions
│   ├── StaggeredImagesList.swift       # Overlapping card-style media gallery
│   └── LoopVideoView.swift             # Looping video player component
│
├── Helper/
│   ├── Biometrics.swift                # FaceID / TouchID (LocalAuthentication)
│   ├── Keyboard.swift                  # Keyboard utilities (clipboard, extension detection)
│   ├── RevenueCatManager.swift         # RevenueCat singleton (tip jar)
│   ├── AppIconProvider.swift           # App icon name resolver
│   ├── Views.swift                     # View extensions (hideKeyboard, limitText, pressable)
│   └── Strings.swift                   # String extensions (HMAC, URL validation, attributed text)
│
├── Tips/
│   └── HomeTips.swift                  # TipKit definitions (3 tips)
│
└── Features/
    ├── Home/View/
    │   ├── HomeView2.swift             # PRIMARY home view (TabView: Snippets/Settings/Search)
    │   ├── HomeView.swift              # [LEGACY] NavigationSplitView home, unused
    │   ├── HomeSnippetList.swift        # Snippet list component
    │   └── SearchView.swift            # Full search view with tag browser
    │
    ├── Snippets/
    │   ├── SnippetModel.swift          # SwiftData models: SnippetItem, SnipTag, SnippetFile
    │   ├── SnippetViewModel.swift      # Snippet CRUD + tag + file operations
    │   └── Views/
    │       ├── SnippetForm.swift       # Create/edit form (single + bulk modes)
    │       ├── SnippetViewDetail.swift # Snippet detail (with biometric lock)
    │       ├── SnippetListItem.swift   # List row + minimal keyboard grid item
    │       ├── SnippetTagForm.swift    # Tag selection + batch move
    │       ├── EditTagView.swift       # Edit tag sheet (name, icon, color, delete)
    │       ├── TagsView.swift          # Settings > Tags management list
    │       ├── SnippetContentForm.swift       # Dynamic content editor (text/URL/image/PDF)
    │       ├── SnippetContentViewDisplay.swift # Content display renderer
    │       ├── SnippetFilesView.swift  # Image gallery (masonry grid)
    │       ├── SnippetListEmpty.swift  # Empty state with typewriter animation
    │       ├── KeyboardStatusView.swift # Keyboard setup status indicator
    │       └── ArrowSVG.swift          # Decorative arrow shape
    │
    ├── Settings/
    │   ├── Model/SettingsModel.swift   # SettingsModel (@Model) + enums
    │   ├── ViewModel/SettingsViewModel.swift # Settings business logic
    │   └── Views/SettingsView.swift    # Full settings screen
    │
    ├── Subscription/Views/
    │   └── SubscriptionView.swift      # Free app info screen (placeholder)
    │
    └── OnBoarding/
        ├── OnBoardingModel.swift       # BoardingItem struct
        ├── Model/Page.swift            # 5-page onboarding page definitions
        └── Views/
            ├── OnBoardingView.swift    # Feature list onboarding
            ├── OnboardingStepperView.swift # 5-step animated welcome walkthrough
            ├── WelcomeView.swift       # Tab-style welcome cards
            ├── BoardingCardView.swift  # Individual boarding card
            ├── Splashscreen.swift      # Splash screen (1.2s)
            └── KeyboardHelpGuideView.swift # 3-step keyboard setup guide

SnipKeyboard/                           # Keyboard Extension Target
├── KeyboardViewController.swift        # UIInputViewController + QWERTY state management
├── KeyboardView.swift                  # SwiftUI keyboard UI (snippet grid + QWERTY toggle)
├── SnipKeyboard.entitlements           # Extension entitlements
├── Info.plist                          # Extension config (RequestsOpenAccess: true)
└── QWERTY/                             # Full QWERTY keyboard implementation
    ├── KeyboardDimensions.swift        # Responsive key measurements from screen width
    ├── QWERTYKeyboardState.swift       # @Observable render state + plain input tracking
    ├── KeyboardActions.swift           # textDocumentProxy closures via SwiftUI environment
    ├── QWERTYKeyboardLayout.swift      # Static key definitions for letters/numbers/symbols
    ├── KeyButtonView.swift             # Key rendering with UIKit KeyTouchArea (touch lifecycle)
    ├── KeyRowView.swift                # HStack row with zero-dead-zone padding + probabilistic data
    ├── QWERTYKeyboardView.swift        # Main keyboard view + toolbar + slash suggestions
    ├── KeyPopupView.swift              # UIKit balloon popup for key press visual feedback
    ├── SlashCommandEngine.swift        # Slash command tracker + state + fuzzy matching engine
    ├── PredictiveTextEngine.swift      # Predictive text tracker + state + suggestion engine
    ├── BigramEngine.swift              # Static English bigram frequency table (26x26)
    ├── DynamicHitResolver.swift        # Probability-weighted key boundary resolver
    └── ProbabilisticTouchContext.swift  # Per-keystroke context for probabilistic touch targeting
```

---

## Data Models

### SnippetItem (`@Model`)

```swift
@Model
final class SnippetItem {
    var creationDate: Date?
    var updatedDate: Date?
    var id: String?
    var title: String?
    var content: String?
    var isSecure: Bool = false
    var lastTimeUsed: Date?
    var usedCount: Int = 0
    var type: SnipType?                  // .txt, .url, .file, .image

    @Relationship(inverse: \SnipTag.snippets)
    var customTag: SnipTag?

    @Relationship(inverse: \SnippetFile.snippet)
    var file: SnippetFile?
}
```

### SnipTag (`@Model`)

```swift
@Model
final class SnipTag {
    var creationDate: Date = Date.now
    var name: String?
    var imageTag: String?                // SF Symbol name
    var id: String?
    var colorHex: String?                // Hex color string, e.g. "#FF3B30"
    var snippets: [SnippetItem]?
}
```

### SnippetFile (`@Model`)

```swift
@Model
final class SnippetFile {
    var id: String?
    var fileType: FileType?              // .document, .image
    var fileFormatType: String?          // MIME type: "image/png", "image/jpeg", "application/pdf"
    @Attribute(.externalStorage)
    var fileData: Data?                  // Binary data stored externally by SwiftData
    var snippet: [SnippetItem]?
}
```

### SettingsModel (`@Model`)

```swift
@Model
final class SettingsModel {
    var settingsId: String = "SnipKey-Settings"
    var afterPasteAction: KeyboardAfterPasteAction = .space
    // Possible values: .rtrn, .space, .change, .changeReturn, .nothing
}
```

### Key Enums

```swift
enum SnipType: String, Codable {
    case txt, url, file, image
}

enum FileType: String, Codable {
    case document, image
}

enum KeyboardAfterPasteAction: String, Codable {
    case rtrn, space, change, changeReturn, nothing
}
```

### Shared Container

`SnipKeyDataManager` creates a shared `ModelContainer` accessible to both the main app and the keyboard extension via the `group.snipkey` App Group. The schema includes `SnippetItem.self` and `SettingsModel.self` — `SnipTag` and `SnippetFile` are included automatically via relationships.

---

## Dependencies (Swift Package Manager)

| Package | Version | Purpose |
|---|---|---|
| **AlertToast** | 1.3.9 | Toast / banner notifications |
| **CloudKitSyncMonitor** | 1.2.1 | iCloud sync status indicator |
| **Pow** | 1.0.3 | Animations (confetti, conditional effects) |
| **RevenueCat** | 5.4.0 | In-app purchase tips (tip jar only) |
| **SwiftUIMasonry** | main | Masonry grid layout (image gallery) |
| **SymbolPicker** | 1.5.2 | SF Symbol selection for tags |

All packages resolve automatically when opening the project in Xcode.

---

## Code Style

### Import Order

System frameworks first, then third-party packages:

```swift
import Foundation
import SwiftUI
import SwiftData
import TipKit
// Third-party
import AlertToast
import RevenueCat
```

### Architecture: MVVM with SwiftData

| Layer | Convention | Example |
|---|---|---|
| **Model** | SwiftData `@Model` classes in `*Model.swift` | `SnippetModel.swift` |
| **ViewModel** | `@Observable` classes in `*ViewModel.swift` | `SnippetViewModel.swift` |
| **View** | SwiftUI views, use `@Query` for data fetching | `SnippetForm.swift` |

### Naming Conventions

| Element | Convention | Example |
|---|---|---|
| Files | PascalCase | `SnippetViewModel.swift` |
| Types / Classes | PascalCase | `SnippetItem`, `SnipType` |
| Properties / Variables | camelCase | `isSecure`, `customTag` |
| Enums | PascalCase type, camelCase cases | `SnipType.txt`, `FileType.document` |
| @ViewBuilder functions | PascalCase + "View" suffix | `ListItemsView()`, `AddSnippetButtonView()` |

### State Management

```swift
// User defaults persistence
@AppStorage("isOnboarding") var isOnboarding: Bool = true

// Environment for dependency injection
@Environment(\.modelContext) var modelContext
@Environment(SettingsViewModel.self) private var settingsViewModel

// SwiftData queries
@Query(sort: \SnippetItem.creationDate, order: .reverse) private var snippets: [SnippetItem]

// Shared managers as StateObject
@StateObject private var revenueCatManager = RevenueCatManager.shared
```

### View Composition

Use `@ViewBuilder` for reusable view components within a view:

```swift
@ViewBuilder
func ListItemsView() -> some View {
    // View implementation
}

@ViewBuilder
func AddSnippetButtonView() -> some View {
    // View implementation
}
```

### Custom Fonts

The app uses **IBM Plex Mono**. Always use these font names:

```swift
.font(.custom("IBMPlexMono-Regular", size: 12))
.font(.custom("IBMPlexMono-Medium", size: 14))
.font(.custom("IBMPlexMono-SemiBold", size: 15))
.font(.custom("IBMPlexMono-Bold", size: 16))
```

### Color Extensions

Use custom Color extensions for system-adaptive colors:

```swift
Color.label                       // UIColor.label
Color.secondaryLabel              // UIColor.secondaryLabel
Color.systemBackground            // UIColor.systemBackground
Color.secondarySystemBackground   // UIColor.secondarySystemBackground
Color.tertiarySystemBackground    // UIColor.tertiarySystemBackground
```

For hex-based colors (used in tag colors):

```swift
Color(hex: "#FF3B30")
```

### Error Handling

Current pattern uses print statements and optional chaining:

```swift
do {
    let snippets = try modelContext?.fetch(fetchDescriptor)
    return snippets
} catch {
    print("FAILED TO FETCH SNIPPETS")
    return []
}
```

For save operations:

```swift
try? self.modelContext?.save()
```

### Feature Flags

User preferences stored via `@AppStorage`:

```swift
@AppStorage("showTipDev") var showTipDev: Bool = false
@AppStorage("isKeyboardShortcutEnabled") var isKeyboardShortcutEnabled: Bool = false
@AppStorage("isOnboarding") var isOnboarding: Bool = true
```

---

## Keyboard Extension

The keyboard extension (`SnipKeyboard` target) is a `UIInputViewController` that hosts a SwiftUI view. It operates in two modes: **QWERTY typing** and **snippet browsing**, toggled via a button in the toolbar or the bottom-row snippet key.

### Architecture Overview

1. `KeyboardViewController` subclasses `UIInputViewController` and owns:
   - `QWERTYKeyboardState` (`@Observable`) — shared render state injected into SwiftUI environment
   - `KeyboardActions` (struct of closures) — wraps `textDocumentProxy` operations, passed via SwiftUI `@Environment`
   - `KeyPopupView` (UIKit) — singleton balloon popup added as a subview above the SwiftUI hosting controller
   - Explicit `NSLayoutConstraint` for keyboard height (no GeometryReader)
2. `KeyboardViewExt` (SwiftUI) conditionally renders `QWERTYKeyboardView` or the snippet grid based on `qwertyState.showingSnippets`
3. Text is inserted via `textDocumentProxy.insertText()` — this bypasses paste restrictions
4. Images and PDFs are copied to `UIPasteboard.general` (requires Full Access)

### QWERTY Keyboard Design

The QWERTY keyboard is built in `SnipKeyboard/QWERTY/` with 13 files. Key architecture decisions:

**State management:**
- `QWERTYKeyboardState` (`@Observable`) holds only view-affecting properties: `currentPage`, `shiftState`, `returnKeyLabel`, `returnKeyIsProminent`, `appearanceMode`, `needsInputModeSwitchKey`, `showingSnippets`
- `QWERTYInputTracking` (plain class, NOT `@Observable`) holds internal tracking for auto-period detection and shift double-tap timing. Mutations here cause zero SwiftUI re-renders.
- All `@Observable` mutations from `KeyboardViewController` use equality guards (`if value != newValue`) to prevent unnecessary re-renders.
- `viewWillLayoutSubviews()` only calls `updateQWERTYState()` when screen width changes; `textDidChange()` handles per-keystroke updates.

**Touch handling:**
- Character keys and the space bar use `KeyTouchArea` — a `UIViewRepresentable` wrapping `UIControl` with full touch lifecycle (`touchDown`/`touchUpInside`/`touchUpOutside`/`touchCancel`).
- Character insertion fires on `.touchDown` (not `.touchUpInside`) for ~30-80ms lower latency.
- `KeyTouchArea.onTouchDown` provides both the touch X position and the control's actual frame in keyboard coordinates (via `UIEvent` parameter + `convert(bounds, to: nil)`). Character keys use the touch X for probabilistic hit resolution; the actual frame is used for popup positioning.
- `KeyTouchArea` also handles visual highlight via `UIControl.backgroundColor` changes — pure CALayer, no SwiftUI state.
- On the letters page, character keys run `DynamicHitResolver` inline on each touch-down (~100ns) to check if the touch should redirect to an adjacent key based on bigram probabilities. See **Probabilistic Touch Targeting** section below.
- Special keys (shift, backspace, snippet toggle) use SwiftUI `Button` for long-press gesture support.

**Key press visual feedback (balloon popup):**
- `KeyPopupView` is a single `UIView` instance reused for all keys. It contains a `UILabel` + `CAShapeLayer` drawing a balloon shape with a downward-pointing tail.
- Show/hide is done via `CALayer` property changes (`isHidden`, `frame`, `transform`) — zero SwiftUI state mutations, zero layout passes.
- Spring scale animation runs on the Core Animation render server, not the main thread.
- Character/digit/symbol keys get balloon popup + background highlight on press.
- Space bar gets background highlight only (no popup), and dismisses any active popup.
- Special keys (shift, backspace, return, etc.) have no visual feedback currently.
- Popup is positioned using the `UIControl`'s actual frame from UIKit layout (via `convert(bounds, to: nil)`), not duplicated arithmetic. This eliminates drift between SwiftUI layout and popup positioning.

### Slash Command Architecture

The slash command system detects `/query` patterns during typing and shows matching snippet suggestions in the keyboard toolbar. It uses a two-phase evaluation design to avoid per-keystroke SwiftUI re-renders:

**Phase 1 — Detection (UIKit side, per-keystroke):**
- `SlashCommandTracker` (plain class, NOT `@Observable`) reads `documentContextBeforeInput` after each character/backspace/space/return
- Walks backwards from cursor to find `/`, validates it's at string start or after whitespace
- Compares against last known state — only promotes to Phase 2 if `isActive` or `query` actually changed
- Zero SwiftUI re-renders on the hot path

**Phase 2 — Matching (SwiftUI side, reactive):**
- `SlashCommandState` (`@Observable`) holds `isActive`, `query`, and `matchedSnippets`
- `KeyboardToolbarView` uses `.onChange(of: slashState.query)` to trigger fuzzy matching
- Snippets fetched via `@Query` in the toolbar view (not re-fetched per keystroke)
- Fuzzy matching scores: prefix (100) > word-prefix (80) > substring (60) > ordered chars (40)
- Only text/URL snippet types are eligible (image/PDF excluded)
- Secure snippets shown but require biometric auth on tap

**Key files:**
- `SlashCommandEngine.swift` — `SlashCommandTracker` + `SlashCommandState` + fuzzy matching + environment key
- `KeyboardActions.swift` — `evaluateSlashCommand` closure
- `KeyboardViewController.swift` — creates tracker/state, wires evaluation closure
- `QWERTYKeyboardView.swift` — `KeyboardToolbarView` with suggestions UI + `SlashTriggerButton`
- `KeyButtonView.swift` — calls `evaluateSlashCommand()` after character/backspace/return/space

### Probabilistic Touch Targeting

After typing a character, the invisible touch boundaries between adjacent keys dynamically shift based on English bigram frequencies. For example, after typing "t", the hit area for "h" expands because "th" is extremely common. Visual keys don't change — only touch resolution logic changes. This is an inline per-key approach (no overlay or separate touch layer).

**Architecture (inline per-key resolution):**
- `KeyRowView` pre-computes `ProbabilisticRowData` once per layout pass for letters-page rows 0-2. This contains `keyRects` (centerX, width per character key in row coordinate space), `characters` (row's character strings), and `keyOffsets` (each key's tappable left edge X offset).
- Each character `KeyButtonView` receives this data as optional properties (`rowKeyRects`, `rowCharacters`, `characterIndex`, `keyOffsetInRow`). On numbers/symbols pages these are nil (zero overhead).
- On touch-down, `KeyTouchArea` passes both the touch X and the control's actual UIKit frame. The character key's closure calls `resolveCharacter()` which converts local touch X to row-space X (`localTouchX + keyOffsetInRow`), fetches bigram weights from `ProbabilisticTouchContext`, and runs `DynamicHitResolver.resolve()`.
- If the resolved key differs from the tapped key, the neighbor's character is inserted instead. The popup always appears above the tapped key's actual position (better UX — matches where the finger is).

**Key files:**
- `BigramEngine.swift` — Static `enum` with pre-computed 26x26 English bigram conditional probability table. `weights(after:)` returns `[Character: Float]`. Also has `wordInitialFrequencies` for after space/punctuation. All `static let` data, zero allocations.
- `DynamicHitResolver.swift` — Static `enum` with `resolve(touchX:keyRects:weights:keyGap:)`. Computes shifted boundaries between adjacent keys proportional to weight ratios. Clamps so no key shrinks below 60% of original width. Pure arithmetic, ~100ns.
- `ProbabilisticTouchContext.swift` — Plain `final class` (NOT `@Observable` — zero SwiftUI re-renders). Tracks `lastCharacter` and pre-computes `currentWeights`. Updated per keystroke via `recordCharacter()` / `recordNonCharacter()`. Read by `KeyButtonView.resolveCharacter()`.
- `KeyRowView.swift` — `probabilisticRowData()` method computes row geometry during SwiftUI layout.
- `KeyButtonView.swift` — `resolveCharacter()`, `handleCharacterTap()` methods.
- `QWERTYKeyboardState.swift` — `QWERTYInputTracking.touchContext` stores the `ProbabilisticTouchContext` instance.

**Performance:**
- ~100ns additional latency per keystroke (DynamicHitResolver arithmetic)
- Zero additional SwiftUI re-renders
- One small [Float] array allocation per keystroke (~40 bytes for 10 weights)
- No additional UIView instances at runtime
- Row geometry computed once per layout pass, not per keystroke

### NotificationCenter Channels (Legacy — Snippet View)

These channels are used by the snippet browsing view (`KeyboardView.swift`). The QWERTY keyboard uses direct closures via `KeyboardActions` instead.

| Notification | Purpose |
|---|---|
| `addKey` | Insert text or paste file into current input |
| `switchKey` | Switch to next keyboard |
| `deleteKey` | Delete character(s) |
| `spaceKey` | Insert space |
| `selectText` / `selectTextEmpty` | Text selection events |
| `hasFullAccess` | Full Access status broadcast |

### Keyboard-triggered local notifications

The keyboard's 🔔 button schedules a local notification (fires in 2 minutes). It must fire even
while the main app stays **suspended** in the background, so the **keyboard schedules it directly**
via `UNUserNotificationCenter` — a suspended app runs no code and can't schedule on the keyboard's
behalf, and iOS won't wake it for a cross-process signal. Once `add` succeeds, the system owns the
timer and delivers regardless of app state.

- Scheduling logic is shared: `SnipKey/Shared/Notifications/LocalNotificationScheduler.swift`
  (dual-membership — both targets).
- The main app only owns the one-time authorization prompt and the foreground-presentation delegate
  (`SnipKey/Features/Notifications/NotificationPresenter.swift`, app-only).
- The Snippets 🔔 toolbar button (`HomeView2`) opens `RemindersView` and shows a red count badge of
  pending reminders, refreshed on appear/active/sheet-close and via the
  `NotificationPresenter.remindersDidChange` broadcast when one fires in-foreground.
- **Natural-language `/remind`:** typing `/remind … <time>` is parsed on-device in
  `SnipKeyboard/QWERTY/ReminderParseEngine.swift` (`ReminderParser` + `ReminderSuggestionState`).
  It's intent-aware — separates *day* (from `NSDataDetector`) from *time* (explicit clock →
  time-of-day phrase map → 9 AM default → now + 1 hour), and adds what `NSDataDetector` misses
  (`noon`, `next week`/`next month`, bare `at 3`, relative `in N seconds…weeks`). Past today-times
  roll to tomorrow; calendar trigger includes `.second`. **Full spec: `REMINDER_NLP.md`.**
  The controller updates the state in the coalesced flush (`runReminderEvaluation`); the toolbar shows
  `CreateReminderPill`, which deletes the command and calls `KeyboardActions.createReminder(body:fireDate:)`
  → `ReminderRequest(fireDate:title:"Reminder",…)` (calendar trigger). Confirmation banner is the shared
  `.reminderToast()` modifier on both keyboard roots. Reuses the same `identifierPrefix`, so it lands in
  `RemindersView` + the badge.
- Requires **Full Access** (already a SnipKey baseline) and granted notification permission.

See **[`LOCAL_NOTIFICATIONS.md`](LOCAL_NOTIFICATIONS.md)** for the full design, the why, and testing
steps. (An earlier App Group + Darwin design — where the app scheduled — was dropped because it
can't fire while the app is suspended.)

### Integrations (reminder destinations)

`Settings → Integrations → Reminders` lets the user send reminders to the **native iOS Reminders
app** (EventKit) instead of SnipKey's local notifications. A single `ReminderDestination` enum
(`.snipKey` default / `.remindersApp`) is persisted in `SettingsModel` and mirrored to the
`group.snipkey` App Group; the keyboard reads it once per session and `KeyboardViewController.routeReminder`
routes both the `/remind` pill and the 🔔 button to exactly one destination — never both.

- EventKit work is encapsulated in `SnipKey/Shared/Reminders/EventKitReminderService.swift`
  (dual-membership). The **main app** owns the permission prompt (`RemindersIntegrationView`); the
  keyboard **attempts a direct write** using that grant and **falls back** to a SnipKey notification
  if its process isn't authorized (TCC is per-process/per-bundle-ID — **confirm on-device** whether
  the keyboard inherits the app's grant; if not, build the `PendingReminderQueue` contingency).
- The Integrations list is driven by a lightweight `IntegrationRegistry` so new integrations need no
  refactor. Nothing here touches the keystroke hot path.

See **[`INTEGRATIONS.md`](INTEGRATIONS.md)** for the full design, the try-direct-then-fallback
rationale, and how to extend it.

### Key Constraints

- Keyboard extensions run in a **constrained memory environment** (~48 MB limit)
- Keep the UI lightweight — avoid adding `@State` or `@Observable` properties for per-keystroke visual effects
- Full Access is required for `UIPasteboard` operations but not for text insertion
- The extension shares the same SwiftData container via the `group.snipkey` App Group
- The keyboard extension cannot render views above its frame boundary (no private window access like Apple's native keyboard)
- For visual feedback, always prefer UIKit/CALayer approaches over SwiftUI state changes

---

## Privacy Guidelines

**This is a strict policy.** All contributors must follow these rules:

1. **No analytics or tracking SDKs.** Do not add Firebase Analytics, Mixpanel, Amplitude, or any similar SDK.
2. **No crash reporting SDKs.** Do not add Crashlytics, Sentry, Bugsnag, or similar.
3. **No advertising SDKs.** The app has no ads and never will.
4. **No third-party data sharing.** Snippet content, user data, and usage patterns must never be sent to any external service.
5. **No network calls** besides CloudKit sync (Apple's infrastructure) and RevenueCat (tip jar processing only).
6. **Biometric data** is handled entirely by Apple's LocalAuthentication framework on-device. Never store or transmit authentication results.
7. If a new feature requires network access, it must be clearly justified and documented.

---

## Common Patterns

### Creating a New View

```swift
struct MyNewView: View {
    @Environment(\.modelContext) var modelContext
    @Query(sort: \SnippetItem.creationDate) private var snippets: [SnippetItem]

    var body: some View {
        // View content
    }
}

#Preview {
    let container = SnipKeyDataManager().makeSharedContainer()
    MyNewView()
        .modelContainer(container)
}
```

### Adding ViewModel Logic

```swift
@Observable
class MyViewModel {
    var modelContext: ModelContext? = nil

    func performAction() {
        // Business logic
        try? modelContext?.save()
    }
}
```

### Adding a Snippet Type

If adding a new snippet type:

1. Add a case to `SnipType` enum in `SnippetModel.swift`
2. Handle the new type in `SnippetContentForm.swift` (editor)
3. Handle the new type in `SnippetContentViewDisplay.swift` (display)
4. Handle the new type in `KeyboardView.swift` (keyboard paste behavior)
5. Update `SnippetViewModel` if new CRUD logic is needed

### Working with the Keyboard Extension

When modifying `KeyboardView.swift` or `KeyboardViewController.swift`:

1. Build and run the **SnipKey** scheme (not SnipKeyboard directly)
2. Enable the keyboard in Settings if you haven't already
3. Open any app with a text field (e.g., Notes)
4. Switch to the SnipKey keyboard to test
5. Use Xcode's Debug > Attach to Process to debug the extension

---

## Known Technical Debt

| Issue | Location | Notes |
|---|---|---|
| Dead code: unused ContentView | `ContentView.swift` | Default Xcode template, references nonexistent `Item` model |
| Dead code: legacy home view | `HomeView.swift` | Replaced by `HomeView2.swift` |
| Dead code: KeyboardHaptics enum | `KeyButtonView.swift` | Haptic feedback disabled for iOS 26; enum kept for future settings toggle |
| No tests | — | Test targets exist in scheme but have no test files |
| Minimal error handling | Throughout | Most errors use `print()` and `try?` |
| Missing privacy manifest | — | `.xcprivacy` file not present; may be needed for App Store (UIPasteboard, UserDefaults declarations) |
| RevenueCat API key in source | `RevenueCatManager.swift` | Public API key per RevenueCat design, but worth noting |

---

## Roadmap

The project has a multi-phase roadmap to evolve SnipKey from a snippet-only keyboard into a full replacement keyboard (similar to Grammarly's iOS keyboard approach). The planned phases are:

1. ~~**Full QWERTY Keyboard**~~ **(COMPLETE)** — full QWERTY keyboard with letters/numbers/symbols pages, auto-capitalization, auto-period, caps lock, snippet toggle (tap) / globe (long-press), and key press visual feedback (balloon popup + highlight). Performance-optimized with UIKit touch handling, `@Observable` equality guards, and CALayer-based visual feedback.
2. ~~**Slash Commands**~~ **(COMPLETE)** — type `/snippetName` to trigger inline autocomplete in the toolbar. Two-phase evaluation (plain tracker + @Observable state) for zero per-keystroke re-renders. Fuzzy matching (prefix/word-prefix/substring/ordered chars). Biometric support for secure snippets. Usage tracking on selection. Slash trigger button in toolbar for quick activation.
3. ~~**Probabilistic Touch Targeting**~~ **(COMPLETE)** — bigram-frequency-based dynamic hit boundaries for character keys. After typing a character, adjacent keys' invisible touch targets shift based on English bigram probabilities. Inline per-key resolution (~100ns per keystroke), zero SwiftUI re-renders, no additional UIView instances. Popup positioning uses actual UIKit frame via `convert(bounds, to: nil)`.
4. **Emoji Shortcodes** — type `:emojiName` to autocomplete and inject emojis (Slack/Discord/GitHub-style shortcodes)

See the [Roadmap & Vision](README.md#roadmap--vision) section in `README.md` for full details, examples, and contribution guidance.

---

## Useful Links

| | |
|---|---|
| **App Store** | https://apps.apple.com/us/app/snipkey/id6480381137 |
| **GitHub** | https://github.com/jtvargas/SnipKey |
| **Website** | https://snipkey.jrtv.online |
| **Privacy Policy** | https://snipkey.jrtv.online/privacy-policy |
| **Feature Requests** | https://snipkey.canny.io |
