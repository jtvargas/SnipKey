# AGENTS.md - SnipKey iOS Application

This document provides guidelines for AI coding agents working on this codebase.

## Project Overview

SnipKey is a native iOS app (SwiftUI + SwiftData) that lets users create, organize, and quickly access text snippets via a custom keyboard extension. Key features include snippet management with tags, iCloud sync via CloudKit, biometric authentication, and in-app tips via RevenueCat.

**Targets:**
- `SnipKey` - Main iOS application
- `SnipKeyboard` - Custom keyboard extension

## Build & Run Commands

This is an Xcode project. Build and run using:

```bash
# Build the main app
xcodebuild -project SnipKey.xcodeproj -scheme SnipKey -configuration Debug build

# Build for iOS Simulator
xcodebuild -project SnipKey.xcodeproj -scheme SnipKey \
  -destination 'platform=iOS Simulator,name=iPhone 15' build

# Clean build
xcodebuild -project SnipKey.xcodeproj -scheme SnipKey clean
```

For development, use Xcode directly (Cmd+R to build & run).

## Testing

**No tests currently exist** in this project. If adding tests:

```bash
# Run all tests
xcodebuild test -project SnipKey.xcodeproj -scheme SnipKey \
  -destination 'platform=iOS Simulator,name=iPhone 15'

# Run a single test class
xcodebuild test -project SnipKey.xcodeproj -scheme SnipKey \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:SnipKeyTests/TestClassName

# Run a single test method
xcodebuild test -project SnipKey.xcodeproj -scheme SnipKey \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:SnipKeyTests/TestClassName/testMethodName
```

## Project Structure

```
SnipKey/
├── SnipKeyApp.swift              # App entry point (@main)
├── ContentView.swift             # Root content view
├── SnipKeyDataManager.swift      # SwiftData container setup
├── Core/                         # Core utilities (Colors)
├── Components/                   # Reusable UI components
├── Helper/                       # Utilities (Biometrics, Keyboard, RevenueCat)
├── Tips/                         # TipKit definitions
└── Features/
    ├── Home/View/                # Main home views (HomeView2, SearchView)
    ├── Snippets/                 # Snippet models, viewmodels, views
    ├── Settings/                 # Settings feature (Model/ViewModel/Views)
    ├── Subscription/             # In-app purchase views
    └── OnBoarding/               # Onboarding flow

SnipKeyboard/                     # Keyboard Extension Target
├── KeyboardViewController.swift  # UIInputViewController
└── KeyboardView.swift            # SwiftUI keyboard UI
```

## Dependencies (Swift Package Manager)

- **AlertToast** - Toast notifications
- **CloudKitSyncMonitor** - iCloud sync status indicators
- **Pow** - Animations
- **RevenueCat** - In-app purchases/tips
- **SwiftUIMasonry** - Grid layouts
- **SymbolPicker** - SF Symbol selection

## Code Style Guidelines

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

### Architecture Pattern

MVVM with SwiftData:

- **Models**: SwiftData `@Model` classes in `*Model.swift` files
- **ViewModels**: `@Observable` classes in `*ViewModel.swift` files  
- **Views**: SwiftUI views using `@Query` for data fetching

### Naming Conventions

| Element | Convention | Example |
|---------|------------|---------|
| Files | PascalCase | `SnippetViewModel.swift` |
| Types/Classes | PascalCase | `SnippetItem`, `SnipType` |
| Properties/Variables | camelCase | `isSecure`, `customTag` |
| Enums | PascalCase, camelCase cases | `SnipType.txt`, `FileType.document` |
| ViewBuilder functions | PascalCase + "View" suffix | `ListItemsView()`, `AddSnippetButtonView()` |

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

### SwiftData Models

```swift
@Model
final class SnippetItem {
    var creationDate: Date?
    var id: String?
    var title: String?
    var content: String?
    var isSecure: Bool = false
    
    @Relationship(inverse: \SnippetItem.customTag)
    var customTag: SnipTag?
    
    init(title: String, content: String, type: SnipType, isSecure: Bool) {
        self.creationDate = Date.now
        self.id = UUID().uuidString
        self.title = title
        self.content = content
        self.isSecure = isSecure
    }
}
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

The app uses IBM Plex Mono. Use these font names:

```swift
.font(.custom("IBMPlexMono-Regular", size: 12))
.font(.custom("IBMPlexMono-Medium", size: 14))
.font(.custom("IBMPlexMono-SemiBold", size: 15))
.font(.custom("IBMPlexMono-Bold", size: 16))
```

### Color Extensions

Use custom Color extensions for system colors:

```swift
Color.label                       // UIColor.label
Color.secondaryLabel              // UIColor.secondaryLabel
Color.systemBackground            // UIColor.systemBackground
Color.secondarySystemBackground   // UIColor.secondarySystemBackground
Color.tertiarySystemBackground    // UIColor.tertiarySystemBackground
```

### Error Handling

Current pattern uses print statements for debugging and optional chaining:

```swift
do {
    let snippets = try modelContext?.fetch(fetchDescriptor)
    return snippets
} catch {
    print("FAILED TO FETCH SNIPPETS")
    return []
}
```

For SwiftData save operations:
```swift
try? self.modelContext?.save()
```

### App Groups & Extension Communication

- **App Group**: `group.snipkey` for sharing data between main app and keyboard extension
- **iCloud Container**: `iCloud.SnipKeyCloud`
- **NotificationCenter** for extension communication:

```swift
NotificationCenter.default.post(
    name: NSNotification.Name(rawValue: "addKey"), 
    object: snippet
)
```

### Feature Flags

Use `@AppStorage` for feature flags and user preferences:

```swift
@AppStorage("showTipDev") var showTipDev: Bool = false
@AppStorage("isKeyboardShortcutEnabled") var isKeyboardShortcutEnabled: Bool = false
@AppStorage("isOnboarding") var isOnboarding: Bool = true
```

## Important Technical Notes

1. **Shared Data Container**: `SnipKeyDataManager` creates a shared ModelContainer for both main app and keyboard extension access
2. **Biometrics**: Uses LocalAuthentication framework (FaceID/TouchID) for secure snippets
3. **TipKit**: Used for user tips and onboarding hints
4. **Minimum iOS**: iOS 14+ (inferred from API usage)

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
