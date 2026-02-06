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
├── KeyboardViewController.swift        # UIInputViewController (text injection, file paste)
├── KeyboardView.swift                  # SwiftUI keyboard UI (snippet grid, sort, filter, actions)
├── SnipKeyboard.entitlements           # Extension entitlements
└── Info.plist                          # Extension config (RequestsOpenAccess: true)
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

The keyboard extension (`SnipKeyboard` target) is a `UIInputViewController` that hosts a SwiftUI view.

### How it works

1. `KeyboardViewController` subclasses `UIInputViewController`
2. It hosts `KeyboardViewExt` (SwiftUI) via `UIHostingController`
3. Text is inserted via `textDocumentProxy.insertText()` — this is how text bypasses paste restrictions
4. Images and PDFs are copied to `UIPasteboard.general` (requires Full Access)
5. Communication between SwiftUI and UIKit uses `NotificationCenter` with named notifications

### NotificationCenter Channels

| Notification | Purpose |
|---|---|
| `addKey` | Insert text or paste file into current input |
| `switchKey` | Switch to next keyboard |
| `deleteKey` | Delete character(s) |
| `spaceKey` | Insert space |
| `selectText` / `selectTextEmpty` | Text selection events |
| `hasFullAccess` | Full Access status broadcast |

### Key constraints

- Keyboard extensions run in a **constrained memory environment** (~48 MB limit)
- Keep the UI lightweight — the current keyboard view is fixed at 260pt height
- Full Access is required for `UIPasteboard` operations but not for text insertion
- The extension shares the same SwiftData container via the `group.snipkey` App Group

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
| No tests | — | Test targets exist in scheme but have no test files |
| Minimal error handling | Throughout | Most errors use `print()` and `try?` |
| Missing privacy manifest | — | `.xcprivacy` file not present; may be needed for App Store (UIPasteboard, UserDefaults declarations) |
| RevenueCat API key in source | `RevenueCatManager.swift` | Public API key per RevenueCat design, but worth noting |

---

## Roadmap

The project has a multi-phase roadmap to evolve SnipKey from a snippet-only keyboard into a full replacement keyboard (similar to Grammarly's iOS keyboard approach). The planned phases are:

1. **Full QWERTY Keyboard** — a complete keyboard with all keys working 1:1 with the native iOS keyboard, plus a toggle button to switch between typing and the snippets list
2. **Slash Commands** — type `/snippetName` to trigger inline autocomplete and paste snippets without leaving the typing flow
3. **Emoji Shortcodes** — type `:emojiName` to autocomplete and inject emojis (Slack/Discord/GitHub-style shortcodes)

See the [Roadmap & Vision](README.md#roadmap--vision) section in `README.md` for full details, examples, and contribution guidance.

---

## Useful Links

| | |
|---|---|
| **App Store** | https://apps.apple.com/us/app/snipkey/id6480381137 |
| **Website** | https://snipkey.jrtv.online |
| **Privacy Policy** | https://snipkey.jrtv.online/privacy-policy |
| **Feature Requests** | https://snipkey.canny.io |
