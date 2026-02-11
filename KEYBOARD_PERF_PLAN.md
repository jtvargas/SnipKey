# Keyboard Performance Optimization Plan

Audit and implementation plan for making SnipKey's QWERTY keyboard typing performance indistinguishable from the native iOS keyboard.

---

## Current Architecture (Already Implemented)

| Technique | File(s) | Impact |
|---|---|---|
| `touchDown` firing (not `touchUpInside`) | `KeyButtonView.swift` | ~30-80ms latency reduction per key |
| `@Observable` equality guards | `KeyboardViewController.swift` | Prevents redundant re-renders from `textDidChange` |
| `CharacterKeyLabel` isolating shift observation | `KeyButtonView.swift` | Shift toggle re-renders ~28 lightweight labels, not ~28 full key views |
| `static let` cached layout arrays | `QWERTYKeyboardLayout.swift` | Zero allocation per body evaluation |
| `ForEach` element-based identity | `QWERTYKeyboardView.swift`, `KeyRowView.swift` | Stable diffing, no unnecessary destroy/recreate |
| `viewWillLayoutSubviews` deduplication | `KeyboardViewController.swift` | Halves `updateQWERTYState()` calls during typing |
| `QWERTYInputTracking` non-observable | `QWERTYKeyboardState.swift` | Auto-period + shift timing causes zero re-renders |
| `KeyPopupView` pure UIKit/CALayer | `KeyPopupView.swift` | Popup show/hide is ~0.1ms, zero SwiftUI involvement |
| `KeyTouchArea` highlight via `UIControl.backgroundColor` | `KeyButtonView.swift` | CALayer implicit animation, no `@State` |

Best case per-keystroke (shift already disabled): **zero SwiftUI re-renders**.

---

## Identified Bottlenecks (10 Issues, 3 Tiers)

### HIGH — Measurable Impact on Keystroke Path

#### 1. `textDidChange` Posts Notifications Unconditionally
- **File:** `KeyboardViewController.swift:278-285`
- **Problem:** After every character insertion, `textDidChange` posts `"selectText"` or `"selectTextEmpty"` even when QWERTY is active and snippet view isn't shown. Combined with observer leak (#2), triggers N observer calls per keystroke.
- **Fix:** Guard posts behind `qwertyState.showingSnippets`.
- **Status:** COMPLETE

#### 2. NotificationCenter Observer Leak in KeyboardView
- **File:** `KeyboardView.swift:709-738`
- **Problem:** `setupSelectTextObserver()` registers 3 observers in `.onAppear` but never removes them. Each QWERTY↔snippets toggle adds 3 more. After 10 toggles = 30 observers, each firing per keystroke.
- **Fix:** Store observer tokens and remove in `onDisappear`.
- **Status:** COMPLETE

#### 3. `deletionCount` as `@State` in Timer Callback
- **File:** `KeyButtonView.swift:413`
- **Problem:** During backspace long-press, `deletionCount += 1` mutates `@State` 10x/second, scheduling unnecessary SwiftUI body re-evaluations.
- **Fix:** Move `deletionCount` to a non-`@State` plain `var` on the Coordinator or use a captured reference.
- **Status:** COMPLETE

### MEDIUM — Indirect or Rare Impact

#### 4. `screenWidth` Captured Once, Stale After Rotation
- **File:** `KeyboardViewController.swift:51`
- **Problem:** `keyboardActionsStruct` captures `screenWidth` at lazy-init time. After rotation, the width is stale — keys and popup use wrong dimensions.
- **Fix:** Make `screenWidth` a closure `() -> CGFloat` that reads current width, or recreate the struct on width change.
- **Status:** PENDING

#### 5. Dead `@ObservedObject var keyboard: KeyboardObserver`
- **File:** `KeyboardView.swift:171`
- **Problem:** Creates Combine observation pipeline for `@Published` properties that are never updated. Wasted memory + subscription overhead.
- **Fix:** Remove `KeyboardObserver` class and `@ObservedObject` property entirely.
- **Status:** PENDING

#### 6. Dead `@AppStorage` and `@State` Properties
- **File:** `KeyboardView.swift:165, 184, 187`
- **Problem:** `@AppStorage("sortBySelection")`, `@State var snippetsTest`, `@State var text` — declared but never used for their intended purpose. Each adds marginal SwiftUI state tracking overhead.
- **Fix:** Remove all three.
- **Status:** PENDING

#### 7. `appearanceMode` Read by All Keys' `backgroundStyle`
- **File:** `KeyButtonView.swift:306`
- **Problem:** Every `KeyButtonView.body` reads `state.appearanceMode` via `isDarkMode` → `backgroundStyle`. If appearance changes (rare), all ~32 keys re-render full bodies.
- **Fix:** Extract `KeyBackgroundView` sub-view to isolate `appearanceMode` observation (same pattern as `CharacterKeyLabel`).
- **Status:** PENDING

### LOW — Theoretical or One-Time Cost

#### 8. `ModelContainer` Created Synchronously
- **File:** `KeyboardView.swift:753`
- **Problem:** `SnipKeyDataManager().makeSharedContainer()` does disk I/O on main thread during first render. Adds ~50-200ms to first keyboard appearance.
- **Fix:** Move to fully async loading pattern.
- **Status:** PENDING

#### 9. Strong Self Captures in NotificationCenter
- **File:** `KeyboardViewController.swift:168, 209`
- **Problem:** `"addKey"` and `"spaceKey"` observers capture `self` strongly. Potential retain cycle.
- **Fix:** Use `[weak self]` consistently.
- **Status:** PENDING

#### 10. Post-Keystroke Shift Re-renders
- **Situation:** When auto-capitalization is active, typing a character toggles shift disabled→enabled across two events, causing ~56 `CharacterKeyLabel` body evaluations.
- **Why low priority:** Each eval is ~0.01ms. Total ~0.5ms = 3% of frame budget at 10 keys/sec.
- **Status:** ACCEPTABLE (no fix needed)

---

## Per-Keystroke Budget After All Fixes

| Operation | Time | Thread |
|---|---|---|
| `touchDown` → `insertText` | ~0.5ms | Main |
| Popup show (CALayer) | ~0.1ms | Main → Render server |
| Key highlight (CALayer) | ~0.05ms | Main |
| `textDidChange` (guarded, no notifications) | ~0.1ms | Main |
| Shift re-renders (when applicable) | ~0.5ms | Main |
| **Total per keystroke** | **~1.2ms** | vs 16.6ms frame budget |

At 10 keys/sec: **7.2% main-thread utilization** — indistinguishable from native.

---

## Architectural Approaches Comparison (Reference)

| Approach | Touch Latency | Re-render Cost | Memory | Complexity | Verdict |
|---|---|---|---|---|---|
| SwiftUI Button | ~80-120ms | `body` eval per tap | Low | Low | Used for special keys only |
| UIKit UIControl via UIViewRepresentable | ~10-30ms | Zero from touch | Low | Medium | **Current: char/space keys** |
| Pure UIKit UIButton | ~40-80ms | N/A | Low | High | Rejected (built-in delay) |
| CALayer-only rendering | ~5-10ms | Zero | Very low | Very high | Used for popup only |
| Full UIKit keyboard | ~10-20ms | N/A | Medium | Very high | Rejected (disproportionate rewrite) |

**Recommended:** Hybrid UIKit touch + SwiftUI rendering + CALayer popup (current architecture).
