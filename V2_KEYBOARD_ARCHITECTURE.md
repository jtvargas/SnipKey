# SnipKey V2 QWERTY Keyboard — Architecture Reference

> A single-source reference for the V2 native-feel keyboard. Synthesized from a deep multi-agent
> code analysis (structure, input handling, hot-path performance, design rationale). Use it to
> understand *what exists*, *why it was built that way*, and *where to look* when changing it.

---

## 1. TL;DR

The V2 keyboard is a custom iOS keyboard extension that reaches **near-native typing feel** inside
a third-party `UIInputViewController` by removing SwiftUI from the touch and render hot paths:

- **Keys area = pure UIKit + CALayer.** No SwiftUI hit-testing, no per-key views. Touches are
  routed by one multi-touch state machine; keys are drawn as `CAShapeLayer` + glyph layers.
- **SwiftUI is used only for the suggestion toolbar** (slash snippets + predictive text), where it
  keeps its `@Query`/`@Environment` bindings.
- **Characters commit on touch-DOWN** (like native iOS), not on release.
- **Dead zones are eliminated** by tiling invisible `KeyHitView` hit cells over every key's hit
  rect and resolving touches through a binary-search `HitGrid`.
- **The hot path is tiny and XPC-frugal:** an `ownCharacterInsertInFlight` guard skips redundant
  cross-process context reads, and slash/predictive work is coalesced into one deferred flush per
  runloop and pushed off-main.

**Stack:** Swift 5.9 · UIKit (keys) · SwiftUI (toolbar/app) · CALayer rendering · SwiftData
(snippets) · App Group UserDefaults (settings) · CloudKit (sync) · iOS 17+.

---

## 2. Project Layout & File Map

All paths are under `/SnipKeyboard/`. V2 code lives in `QWERTY/V2/`; shared code in `QWERTY/`.

### Core V2 (touch + render + state machine)
| File | Role |
|---|---|
| `KeyboardViewController.swift` | `UIInputViewController` root. Mounts `NativeKeyboardV2View` directly on the input view, hydrates state, owns `textDocumentProxy`, coalesces side-effects, V1/V2 toggle. |
| `QWERTY/V2/NativeKeyboardV2View.swift` | Pure-UIKit host. Bridges `@Observable` state into the coordinator via `withObservationTracking`; SwiftUI body renders only the toolbar + a `Spacer` for the keys region. |
| `QWERTY/V2/KeyboardGestureCoordinator.swift` | **The single multi-touch state machine** (~833 lines). Per-touch press tracking, finger-slide, highlight, callouts, accent menus, space-cursor drag, rapid backspace. Owns `KeyLayerRenderer`, `HitGrid`, `KeyHitView` tiles. |
| `QWERTY/V2/KeyLayerRenderer.swift` | CALayer renderer. `CAShapeLayer` backgrounds + glyph layers (`CATextLayer` / SF Symbol images), glyph cache, instant highlight, shift/case updates. |

### Layout & hit-testing
| File | Role |
|---|---|
| `QWERTY/V2/KeyboardLayoutFactory.swift` | Builds a `KeyboardLayout` per page (letters/numbers/symbols) with flexible widths. |
| `QWERTY/V2/KeyboardLayoutResolver.swift` | Two-pass width algorithm → `[KeyFrame]` (visible rect + hit rect). Hit rects extend into gaps/edges. Cached per (page, width). |
| `QWERTY/V2/KeyboardLayoutItem.swift` | Primitives: `KeyWidth` (`.input`/`.available`/`.points`/`.percentage`), `KeyboardLayoutItem`, `KeyboardRow`. |
| `QWERTY/KeyboardDimensions.swift` | Responsive geometry from screen width (key height, gaps, insets, radii). Native iOS proportions. |
| `QWERTY/DynamicHitResolver.swift` | Pure-math probability-weighted boundary shifting (clamps keys ≥60% width). |
| `QWERTY/V2/SmartTouchResolver.swift` | Wraps `DynamicHitResolver` with bigram weights from typing history (~200ns/call). |

### Input pipeline & features
| File | Role |
|---|---|
| `QWERTY/V2/KeyboardCommitPipeline.swift` | Stateless `@MainActor enum` of commit functions: character insert w/ casing, smart space-eating, auto-period, smart punctuation, auto-cap "I". Shared by V1 & V2. |
| `QWERTY/V2/KeyboardCalloutView.swift` | Tooth-shaped input bubble + flat accent menu. Path caching/morphing, spring-vs-instant by burst detection. |
| `QWERTY/V2/CalloutController.swift` | Thin coordinator between gesture stream and `KeyboardCalloutView`; coord conversion + burst window. |
| `QWERTY/V2/SpaceBarCursorController.swift` | Space long-press → caret drag mode (250ms / 14pt to engage). |
| `QWERTY/V2/AccentMap.swift` | Static lookup of accent variants + domain (`.com`/`.net`/…) menu. |
| `QWERTY/SlashCommandEngine.swift` | Slash `/query` detection + tiered fuzzy snippet matching. |
| `QWERTY/V2/PredictiveTextEngineAsync.swift` | `UITextChecker` off-main, 40ms debounce, token-guarded coalescing. |
| `QWERTY/QWERTYKeyboardView.swift` | SwiftUI toolbar (slash pills, predictive pills), debug overlay. |

### Next-Gen Touch Engine (default ON) — see §3.4
| File | Role |
|---|---|
| `QWERTY/V2/ProbabilisticHitResolver.swift` | The 2D **power-diagram** key resolver: Σ-normalized argmin over key centers with log-space language weights, anchor zone, anti-swallow guard. Also the coarse rasterized debug-cell image. Strict superset of nearest-center at β=0. |
| `QWERTY/V2/TouchOffsetModel.swift` | Automatic per-user offset learning: 6-cluster EMA of fractional touch offsets, confidence-gated (pending→confirm on next char, discard on backspace), divergence guard, layout-hash keyed, App Group persisted. |
| `QWERTY/V2/TypingTelemetry.swift` | Shadow-mode telemetry (off by default): acting-vs-shadow disagreement, privacy-safe (anonymous key indices + normalized in-cell position), App Group JSON export. |
| `QWERTY/BigramEngine.swift` → `TrigramEngine` | Bigram tables + curated high-confidence trigram boosts (`th→e`, `qu→`vowel, …) max-merged onto the bigram base. |
| `QWERTY/ProbabilisticTouchContext.swift` | Per-key prior source; tracks last two chars (trigram), EMA-smooths weights with deadband, exposes a `confidence` factor for dynamic λ. |
| `QWERTY/DynamicHitResolver.swift` / `QWERTY/V2/SmartTouchResolver.swift` | Legacy 1D bigram boundary shift — the fallback path used for non-letters / when the engine is off. |
| `Features/Settings/Views/ShadowTelemetryView.swift` (app) | Host-app report: disagreement rate, per-key heatmap, mean touch landing. |

### State & bridge
| File | Role |
|---|---|
| `QWERTY/QWERTYKeyboardState.swift` | `@Observable` view state (shift/page/appearance/return) **+** non-observable `QWERTYInputTracking` (hot-path bookkeeping, zero re-renders). |
| `QWERTY/KeyboardActions.swift` | Value-type struct of ~14 closures wrapping `textDocumentProxy` ops. UIKit↔SwiftUI bridge; includes the `insertCharacter` fast path. |
| `QWERTY/V2/ModelContainerProvider.swift` | Actor providing the App-Group SwiftData `ModelContainer`; `warmup()` started early in `viewDidLoad`. |

### Legacy V1 (still intact behind the flag)
| File | Role |
|---|---|
| `QWERTY/QWERTYKeyboardLayout.swift` | Static V1 key rows. |
| `QWERTY/KeyButtonView.swift` | V1 per-key SwiftUI renderer + `KeyTouchArea` (`UIControl`) hack + V1 haptics. |
| `QWERTY/KeyRowView.swift` | V1 `HStack` row layout with duplicated width math. |

---

## 3. Architecture Overview

### 3.1 Mount & ownership chain
```
KeyboardViewController (UIInputViewController)
 ├─ reads AppGroupSettings.useNativeKeyboardV2 (default true)
 ├─ builds KeyboardActions (closures over textDocumentProxy)
 ├─ owns QWERTYKeyboardState (@Observable) + QWERTYInputTracking (plain)
 ├─ mounts NativeKeyboardV2View  ── UIKit keys, addSubview directly on input view
 └─ mounts UIHostingController   ── SwiftUI toolbar only (keys region = Spacer)

NativeKeyboardV2View (UIView)
 └─ KeyboardGestureCoordinator (UIView, multi-touch root)
     ├─ KeyLayerRenderer            (CALayer keys)
     ├─ HitGrid                     (binary-search hit resolution)
     ├─ [KeyHitView]                (invisible tiling hit cells)
     ├─ CalloutController → KeyboardCalloutView
     └─ SpaceBarCursorController
```

The keys `UIView` and the SwiftUI hosting view occupy the same rect; the **keys UIView sits above**
the toolbar in z-order so touches in the keys region never reach SwiftUI's hit-testing.

### 3.2 Layout pipeline
```
KeyboardPage (.letters/.numbers/.symbols)
  → KeyboardLayoutFactory.layout(for:dims:)        // rows w/ flexible widths
  → KeyboardLayoutResolver.resolve(...)            // → [KeyFrame] (visible rect + hit rect)
  → HitGrid.build(frames)                          // row/col seam boundaries (binary search)
  + KeyLayerRenderer.render(frames)                // CAShapeLayer + glyph per key
  + rebuildHitViews(frames)                        // one KeyHitView per hit rect
```

### 3.3 Touch → character flow (plain letter)
```
UITouch down (delivered to KeyHitView → coordinator.touchesBegan)
  → findKey(at:)            HitGrid binary search          (O(log n) ≈ O(1))
  → smartResolved(...)      SmartTouchResolver/DynamicHitResolver bigram shift (~200ns)
  → beginPress(...)
      • renderer.setHighlightedKey()      instant CATransaction(disableActions)
      • calloutController.presentInput()  spring (first) or instant (burst)
      • KeyboardCommitPipeline.commitCharacter():
          - smart-space eat check
          - actions.insertCharacter():
              ownCharacterInsertInFlight = true
              textDocumentProxy.insertText()     ← synchronous XPC write (dominant cost)
                └─ re-enters textDidChange → updateQWERTYState (auto-cap .words/.sentences SKIPPED)
              ownCharacterInsertInFlight = false
          - inputTracking.recordAction()         zero-render (plain class)
          - touchContext.recordCharacter()       bigram weight refresh
          - smart punctuation (only for - . " ')
          - actions.scheduleSideEffects()        coalesced → 1 flush/runloop
      • scheduleLongPress()   400ms accent-menu Task (only if key has a menu)
  → touchesEnded → endPress() → highlight fades, callout dismisses
```

**Deferred (post-runloop, off the touch path):** one `documentContextBeforeInput` XPC read →
slash evaluation + predictive scheduling; predictive runs off-main via `Task.detached` after a
40ms debounce.

### 3.4 Next-Gen Touch Engine (`smartResolved` path, default ON)

`smartResolved(...)` is the seam where a near-boundary letter tap is corrected. With the engine on
(default), eligible touches (character key, letters page, smart-transform field) go through the 2D
**power-diagram** resolver instead of the legacy 1D shift; everything else (space/return/shift,
symbols, URL/password fields) falls back to the legacy `SmartTouchResolver` unchanged.

```
smartResolved(rawKey, point)                         [eligible letter tap]
  cfg.beta = baseβ × touchContext.confidence         dynamic λ (flat word-start → ~0 pull)
  ProbabilisticHitResolver.resolve:
     t', c_k′ = Σ-normalize(point, center + siteOffset(k))   σx=13, σy=16
     anchor zone? → keep rawKey                       deliberate center taps never overridden
     k* = argmin_k ‖t'−c_k′‖² − β·clip(log P(k|ctx))  ~30-key argmin, ~150 ns
     anti-swallow? → fall back to rawKey
  → commit-on-touch-down (unchanged)
  → TouchOffsetModel: confirmPending() + record(k, point)   learn off the hot path
  (backspace → TouchOffsetModel.discardPending())

P(k|ctx)  = smoothedWeights (EMA, deadband, word-boundary reset) of:
              bigram(prev) ⊕ curated trigram boost(prev2,prev1) ⊕ predictive word-prior
siteOffset = TouchOffsetModel learned per-cluster offset (fractions × key size, layout-hash keyed)
```

**Safety/feel invariants:** keys never move (only invisible sites/weights change); anchor zone
protects center taps; off in secure/URL/email/number fields and non-letter pages; learning gated on
confirmed (non-backspaced) keystrokes; everything on-device. **Shadow mode** (off by default) runs the
*other* resolver in parallel and logs disagreements for tuning; the **Voronoi debug overlay** (off by
default) paints the live decision cells.

---

## 4. The Performance Model (Hot Path)

The design goal is to keep the **synchronous main-thread cost of one keystroke sub-frame** so
fast typing (~10–12 chars/sec, faster on bursts) never drops a character or stutters.

### 4.1 Verified optimizations
| Optimization | What it does | Where |
|---|---|---|
| **`ownCharacterInsertInFlight` guard** | Our own `insertText` synchronously re-enters `textDidChange`; the guard skips the `.words`/`.sentences` auto-cap `documentContextBeforeInput` XPC read (a just-typed char can't start a sentence). `.allCharacters` still honored. | `KeyboardViewController.swift:79`, `~616–633`; set around `KeyboardActions.swift` insert. |
| **Coalesced side-effects** | Many commits in one runloop → **one** `documentContextBeforeInput` read; `scheduleSideEffectFlush` guards on a bool and posts a single `DispatchQueue.main.async`. | `KeyboardViewController.swift:466–515`. |
| **Async predictive** | `UITextChecker` runs off-main via `Task.detached(.userInitiated)`, 40ms debounce, stale results dropped by token guard. Never blocks insert. | `PredictiveTextEngineAsync.swift:41,67,84`. |
| **HitGrid O(log n)** | Two binary searches (row seams, then column seams). 4 rows × ~10 keys → <4 iterations. Built only on layout change. | `KeyboardGestureCoordinator.swift:686–702`. |
| **Smart-touch ~200ns** | Row-filtered frame loop + bigram weight lookup + pure-math `DynamicHitResolver`. Plausible, uninstrumented. | `SmartTouchResolver.swift:30–76`, `DynamicHitResolver.swift:39–108`. |
| **Glyph cache** | SF Symbol renders memoized by `(name, size, weight, tintRGBA)`. Bounded by the ~6-symbol set. | `KeyLayerRenderer.swift:343–376`. |
| **Instant highlight** | All immediate-feedback layer mutations wrapped in `CATransaction.setDisableActions(true)`; only fade-outs animate. | `KeyLayerRenderer.swift:136,185`; `KeyboardCalloutView.swift:130`. |
| **Observable split** | Hot-path bookkeeping lives in non-`@Observable` `QWERTYInputTracking`; keystrokes cause **zero** SwiftUI invalidation until visible state changes. | `QWERTYKeyboardState.swift:30–77`. |
| **Commit on touch-DOWN** | Character lands at finger-down, removing the ~80–150ms press-duration latency of touch-up commits. | `KeyboardGestureCoordinator.swift:387–389`. |

### 4.2 XPC / IPC surfaces
- **App Group UserDefaults** (`group.snipkey`) — synchronous settings reads (`useNativeKeyboardV2`,
  `probabilisticTouchEnabled`, `autoCapitalizationEnabled`, `debugHitOverlayEnabled`). Read at
  launch / on commit, generally not per-keystroke (see opportunity 6.1).
- **`documentContextBeforeInput`** — the expensive cross-process text read (~0.5–5ms). Minimized to:
  one coalesced flush per burst; skipped via the insert guard for `.words`/`.sentences`; read on the
  touch path **only** for smart-punctuation chars (`- . " '`).
- **SwiftData (`ModelContainerProvider`)** — App-Group container, CloudKit auto-sync; `warmup()`
  fired in `viewDidLoad` so the container is ready before first toolbar render.

### 4.3 Snippets data & matching
- **Models (SwiftData `@Model`):** `SnippetItem` (title/content/type/isSecure/tags/usage),
  `SnipTag`, `SnippetFile` (external storage), `UsageTracking`.
- **Toolbar `@Query`** fetches snippets reactively (DB-change driven, not per-keystroke).
- **Slash matching tiers** (`SlashCommandEngine.swift:216–245`): 100 prefix · 80 word-prefix ·
  60 substring · 40 in-order subsequence · ties broken by recency. Only `.txt`/`.url` eligible;
  capped at 10. Two-phase: UIKit `SlashCommandTracker.evaluate` (no render) → SwiftUI
  `SlashCommandState.updateMatches` (fuzzy match when query results ready).

---

## 5. Subsystem Deep-Dives

### 5.1 Dead-zone elimination (hit tiling)
Two complementary mechanisms guarantee every point resolves to exactly one key:
1. **`KeyHitView` tiles** — one invisible UIView per key sized to its **hit rect** (which expands
   into inter-key gaps and to the keyboard edges). Critically filled with `UIColor(white:0, alpha:0.02)`
   **not** `.clear`: inside the keyboard-extension render context, fully transparent views are
   excluded from hit-testing (verified empirically). ~2% fill is imperceptible but hit-testable.
2. **`HitGrid` + `hitTest` override** — seams computed at hit-rect midpoints; a final `hitTest`
   fallback scans the tiles if `super.hitTest` returns self. (`KeyboardGestureCoordinator.swift:590–596,
   650–703, 803–816`.)
- **Debug overlay** (`debugHitOverlayEnabled`): red border + 8% fill on every cell and toolbar
  button to visualize the tiling.

### 5.2 Callouts (input bubble + accent menu)
- **Input mode:** tooth-shaped `UIBezierPath` (bubble + S-curve neck + key overlay), clamped at
  screen edges with the neck re-anchored to keep pointing at the real key. Paths cached by
  `(keySize, neckLeftX)` so repeats are free (`KeyboardCalloutView.swift:256–329`).
- **Action mode:** flat horizontal menu of accent/domain slots (44pt, 58pt for multi-char like
  `.com`), system-blue highlight on the selected slot. `shadowPath` set to avoid off-screen passes.
- **Burst behavior ("callout glide"):** spring pop (`CASpringAnimation` stiffness 220, damping 20)
  on the first press of a burst; if a new present arrives <150ms after the last dismiss, it snaps in
  instantly (no spring) and dismisses instantly — so fast typing doesn't read as bouncing/dimming.
  Burst window tracked via `CACurrentMediaTime()` in `CalloutController`.

### 5.3 Special keys & native behaviors
- **Shift / caps lock:** `.disabled`→`.enabled` (one-shot, auto-resets after a char) → double-tap
  within 300ms → `.locked`. Fires on touch-down for instant visual change. (`QWERTYKeyboardState.swift:121–153`.)
- **Space:** commits on touch-UP (must distinguish tap from cursor mode). Hold 250ms or drift 14pt →
  `SpaceBarCursorController` cursor-drag (12pt/char, ProMotion-smooth via `coalescedTouches`),
  suppresses the space on lift. Double-space → auto-period `". "`.
- **Backspace:** deletes on touch-down; after 350ms hold, accelerating repeat via structured-
  concurrency `Task` — burst `1→2→3` chars, interval `max(45, 110 - count*6)` ms. (V1 used a fixed
  100ms `Timer`.)
- **Accent menu:** 400ms long-press → undo the optimistic touch-down commit (`deleteBackward`) →
  open menu → drag to select → insert on release. URL/email fields get `.` → domain menu.
- **Smart space / punctuation:** predictive insert adds a "smart" trailing space consumed if the next
  char is `. , ! ? ; : ' ) } ] " ``; `--`→em-dash, `...`→ellipsis, typographic quotes by context;
  lone `i`→`I` after space (gated by setting + `allowsSmartTransforms`).
- **Predictive bar:** up to 3 pills, instant press highlight (no animation); long-press the middle
  pill (0.4s) dismisses predictions for the session.

### 5.4 State machine (`KeyboardGestureCoordinator`)
- `activePresses: [ObjectIdentifier(touch): ActivePress]` — true multi-touch; rolling type never
  drops chars. `ActivePress` carries the tracked key, start point, slide flag, per-touch
  `longPressTask` / `rapidDeleteTask`, `rapidDeleteCount`, `ownsSpaceCursor`.
- `mostRecentTouchID` drives shared visuals (highlight + callout); on lift, promotion picks the next
  press so the callout never gaps.
- 12pt directional hysteresis before the tracked key changes on slide.
- `deinit` cancels all outstanding Tasks.

---

## 6. Optimization Opportunities & Risks

Found in the code (not speculative). Severity is relative to an already-fast baseline.

| # | Item | Severity | Location |
|---|---|---|---|
| 6.1 | `AppGroupSettings.bool(probabilisticTouchEnabled)` read on **every** character touch-down — a never-changes-mid-session setting on a latency path. Cache once at init. | Medium | `SmartTouchResolver.swift:40` |
| 6.2 | `rebuildLayout()` recomputes `resolvedFrames` + `HitGrid` (array allocs) **before** the `RenderSignature` short-circuit; wasteful on non-render `layoutSubviews` (trait/frame animations). Move the signature check first. | Low–Med | `KeyboardGestureCoordinator.swift:182–217` |
| 6.3 | `rebuildHitViews` destroys + recreates ~35 `KeyHitView`s on each signature change (view alloc ≫ layer alloc). Reframe in place when key count is unchanged (e.g., rotation). | Low–Med | `KeyboardGestureCoordinator.swift:241–249` |
| 6.4 | Smart-punctuation does a synchronous `documentContextBeforeInput` XPC read for `- . " '` on the touch path (intentional, but those 4 keys are higher-latency than letters). | Known | `KeyboardCommitPipeline.swift:163–164` |
| 6.5 | `modelContext.save()` runs synchronously on main after snippet insert — fine at low frequency, a risk as the store grows. | Low | `QWERTYKeyboardView.swift:155–157` |
| 6.6 | One `Task { @MainActor }` allocation per `withObservationTracking` `onChange` fire (re-registration pattern). Short-lived; negligible. | Very low | `NativeKeyboardV2View.swift:91–97` |

**Note on a claim that didn't fully match:** the predictive engine is described as a "background
serial queue" but is actually `Task.detached` + cancellation-based coalescing (functionally
equivalent for debouncing; technically structured concurrency, not a `DispatchQueue`).

---

## 7. Code-Quality Notes

**Strong separation of concerns:**
- `KeyboardCommitPipeline` is a stateless `@MainActor enum` → directly unit-testable with mock state
  and `.noop` actions. So are `DynamicHitResolver.resolve`, `SmartTouchResolver.resolve`,
  `SlashCommandState.matchScore`/`extractQuery`, `KeyboardLayoutResolver.resolve` (pure / UIKit-free).
- Tracker/State split repeated consistently (slash, predictive, input) to keep hot paths render-free.
- `CalloutController`/`KeyboardCalloutView` know nothing about touches; renderer knows nothing about
  input.

**Fragile coupling / debt to watch:**
- **NotificationCenter holdovers** (`addKey`/`switchKey`/`deleteKey`) remain live from V1; a snippet
  inserted via that path doesn't clear `pendingSmartSpace`, so a stale smart-space could linger.
- **Width-math duplication across three places:** `KeyRowView.visualKeyWidth` (V1),
  `KeyboardDimensions.visualKeyWidth` (popup positioning), and `KeyboardLayoutResolver.computeWidths`
  (V2). They agree today; divergent edits would misalign popups or hit cells.
- **`UIColor.label` trap (handled):** `CATextLayer` has no trait collection, so dynamic colors
  resolve against `UITraitCollection.current` (often dark in an extension). The renderer deliberately
  uses explicit `white`/`black` indexed on its own `isDark` flag.
- `KeyboardGestureCoordinator` / `KeyLayerRenderer` / `KeyboardCalloutView` need a view/layer host →
  not unit-testable without a screen context.

---

## 8. V1 → V2 Evolution

| Area | V1 | V2 |
|---|---|---|
| Keys rendering | SwiftUI view tree (40+ views) | CALayer sublayers on one UIView |
| Touch routing | One `UIControl` per key (`KeyTouchArea`) | Single coordinator, multi-touch |
| Dead zones | Possible (SwiftUI drops transparent views) | Eliminated (KeyHitView tiles + hitTest fallback) |
| Layout | Imperative `KeyRowView` width math | `LayoutFactory` → `LayoutResolver` → `[KeyFrame]` |
| Hit resolution | Per-key inside SwiftUI body | `HitGrid` binary search |
| Backspace repeat | Fixed 100ms `Timer`, coarse | `Task` ramp 110→45ms, burst 1→2→3 |
| Side effects | Synchronous on touch path (XPC per key) | Coalesced one flush/runloop, off-main predictive |
| Callout | Static-path `KeyPopupView` | Morphing tooth path, burst-suppressed spring |
| Accent menu / space cursor | None | `CalloutController` actions / `SpaceBarCursorController` |

Flag: `AppGroupSettings.Key.useNativeKeyboardV2` (default `true`), read in
`KeyboardViewController`. Both paths fully coexist.

---

## 9. Settings Reference

| Setting | Key | Default | Effect |
|---|---|---|---|
| Native V2 keyboard | `useNativeKeyboardV2` | `true` | V2 coordinator vs V1 per-key SwiftUI |
| Probabilistic touch | `probabilisticTouchEnabled` | `true` | Master gate for touch correction (legacy + next-gen) |
| **Next-gen touch engine** | `useProbabilisticHitResolver` | `true` | 2D power-diagram resolver + per-user learning vs legacy 1D shift |
| Auto-capitalization | `autoCapitalizationEnabled` | `true` | Sentence/word auto-cap + auto-"I" |
| Debug hit overlay | `debugHitOverlayEnabled` | `false` | Red hit-cell outlines; + live Voronoi cells when the engine is on |
| Shadow-mode logging | `shadowLoggingEnabled` | `false` | Records acting-vs-shadow resolver disagreement (tuning/telemetry) |

Settings are read at cold start (and on commit), not live — change requires reopening the keyboard,
which intentionally avoids main-thread work mid-typing.

---

## 10. Where to Start (by task)

- **Change typing feel / latency:** `KeyboardGestureCoordinator.swift` (begin/end/moved press) +
  `KeyboardCommitPipeline.swift`.
- **Change key layout / sizing:** `KeyboardLayoutFactory.swift` → `KeyboardLayoutResolver.swift` →
  `KeyboardDimensions.swift`.
- **Change rendering / glyphs / highlight:** `KeyLayerRenderer.swift`.
- **Touch accuracy:** `SmartTouchResolver.swift` + `DynamicHitResolver.swift` (+ bigram data).
- **Callouts / accent menus:** `KeyboardCalloutView.swift` + `CalloutController.swift` + `AccentMap.swift`.
- **Snippets / slash:** `SlashCommandEngine.swift` + toolbar in `QWERTYKeyboardView.swift`.
- **Predictive text:** `PredictiveTextEngineAsync.swift`.
- **XPC / state hydration:** `KeyboardViewController.swift` + `KeyboardActions.swift` + `QWERTYKeyboardState.swift`.
