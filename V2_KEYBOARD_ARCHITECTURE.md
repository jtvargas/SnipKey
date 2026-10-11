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
- **Characters commit on touch-UP or rollover flush** (`nativeCommitTiming`, default ON) —
  the system keyboard's actual semantics: highlight + callout at touch-down, the character
  lands at lift OR the instant the next finger touches down. This is what enables
  slide-to-correct, slide-off-cancel, shift-slide-capital and 123-slide-symbol. (The old
  optimistic commit-on-touch-DOWN — previously mislabeled "like native iOS" — remains as a
  DEBUG kill switch.)
- **Dead zones are eliminated** by tiling invisible `KeyHitView` hit cells over every key's hit
  rect and resolving touches through a binary-search `HitGrid`.
- **The hot path is tiny and XPC-free:** auto-capitalization, smart punctuation and word-delete
  read a local `TypingContextMirror` (never the host); traits come from a per-field cache; the
  only synchronous cross-process call per keystroke is the `insertText`/`deleteBackward` write.
  Slash/predictive work is coalesced into one deferred flush per runloop and pushed off-main.
- **Page and shift changes are visibility flips.** `KeyLayerRenderer` keeps one pre-built
  `KeySurface` per page with both letter cases and all three shift icons; 123/ABC and shift
  toggle allocate nothing and rasterize nothing.
- **Geometry is 1:1 native iPhone portrait** (`KeyboardDimensions` reference table: 54pt row
  pitch, 42pt keys, 6/12pt gaps, 4/3-letter side controls, 88/375 return) with a downward-biased
  vertical hit split (`verticalHitBias`) because thumbs land low.

**Stack:** Swift 5.9 · UIKit (keys) · SwiftUI (toolbar/app) · CALayer rendering · SwiftData
(snippets) · App Group UserDefaults (settings) · CloudKit (sync) · iOS 17+.

---

## 2. Project Layout & File Map

All paths are under `/SnipKeyboard/`. V2 code lives in `QWERTY/V2/`; shared code in `QWERTY/`.

### Core V2 (touch + render + state machine)
| File | Role |
|---|---|
| `KeyboardViewController.swift` | `UIInputViewController` root. Mounts `NativeKeyboardV2View` directly on the input view, hydrates state, owns `textDocumentProxy`, coalesces side-effects. |
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
| `QWERTY/V2/KeyboardCommitPipeline.swift` | Stateless `@MainActor enum` of commit functions: character insert w/ casing, smart space-eating, auto-period, smart punctuation, auto-cap "I". |
| `QWERTY/V2/KeyboardCalloutView.swift` | Tooth-shaped input bubble + flat accent menu. Path caching/morphing, spring-vs-instant by burst detection. |
| `QWERTY/V2/CalloutController.swift` | Thin coordinator between gesture stream and `KeyboardCalloutView`; coord conversion + burst window. |
| `QWERTY/V2/SpaceBarCursorController.swift` | Space long-press → caret drag mode (250ms / 14pt to engage). |
| `QWERTY/V2/AccentMap.swift` | Static lookup of accent variants + domain (`.com`/`.net`/…) menu. |
| `QWERTY/SlashCommandEngine.swift` | Slash `/query` detection + tiered fuzzy snippet matching. |
| `QWERTY/V2/PredictiveTextEngineAsync.swift` | Serial background prediction queue, 40ms debounce, token and exact-context validation. |
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
| `QWERTY/KeyboardActions.swift` | Value-type struct of closures wrapping `textDocumentProxy` ops. UIKit↔SwiftUI bridge; `insertText`/`deleteBackward` advance the context mirror before the XPC write. |
| `QWERTY/V2/ModelContainerProvider.swift` | Actor providing the App-Group SwiftData `ModelContainer`; `warmup()` started early in `viewDidLoad`. |

### Shared QWERTY infrastructure (V1 removed — V2 is the only keyboard)
| File | Role |
|---|---|
| `QWERTY/QWERTYKeyboardLayout.swift` | Static key rows consumed by the V2 layout factory. |
| `QWERTY/QWERTYKeyboardView.swift` | `KeyboardToolbarView` (slash/predictive/reminder pills) + shared `KeyboardHaptics`. |
| `QWERTY/DynamicHitResolver.swift` | 1D boundary-shift math used by the legacy `SmartTouchResolver` path. |

---

## 3. Architecture Overview

### 3.1 Mount & ownership chain
```
KeyboardViewController (UIInputViewController)
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
  + KeyLayerRenderer.render(frames, page)          // per-page KeySurface: built once, then isHidden flips
  + rebuildHitViews(frames)                        // one KeyHitView per hit rect
```

### 3.3 Touch → character flow (plain letter)
```
UITouch down (delivered to KeyHitView → coordinator.touchesBegan)
  → findKey(at:)            HitGrid binary search          (O(log n) ≈ O(1))
  → smartResolved(...)      SmartTouchResolver/DynamicHitResolver bigram shift (~200ns)
  → beginPress(...)
      • renderer.setPressedKey(_:for:)     per-touch overlay, instant CATransaction(disableActions)
      • KeyboardClickPlayer.play()         system key click (Keyboard Clicks setting honoured)
      • calloutController.presentInput()  spring (first) or instant (burst)
      • scheduleLongPress()   400ms accent-menu Task (only if key has a menu)
  → touchesMoved → slideClearsHysteresis()  12pt past a horizontal seam / 10pt past a vertical seam
  → touchesEnded (or next finger-down = rollover flush) → commitPendingPress():
      • KeyboardCommitPipeline.commitCharacter():
          - smart-space eat check
          - actions.insertText():
              contextMirror.append()                 local mirror first
              ownMutationInFlight = true
              textDocumentProxy.insertText()         ← the ONLY synchronous XPC call
                └─ re-enters textDidChange → auto-cap from contextMirror (zero reads)
              ownMutationInFlight = false
          - inputTracking.recordAction()             zero-render (plain class)
          - touchContext.recordCharacter()           bigram weight refresh
          - smart punctuation (only for - . " ')     reads contextMirror
          - actions.scheduleSideEffects()            coalesced → 1 flush/runloop
      • highlight fades, callout dismisses
```

**Deferred (post-runloop, off the touch path):** one `documentContextBeforeInput` XPC read →
slash evaluation + predictive scheduling; ranking and `UITextChecker` run on a serial background
queue after a 40ms debounce.

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
     k* = argmin_k ‖t'−c_k′‖² − β·clip(log P(k|ctx))  raw row + adjacent letter rows
     runner-up captured for telemetry / future hypothesis ranking
     anti-swallow? → fall back to rawKey
  → commit at lift / rollover flush (native timing; legacy commit-on-down behind the kill switch)
  → TouchOffsetModel: record(k, point), then fold after a 500ms no-backspace survival window
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
| **`TypingContextMirror`** | Keyboard-side mirror of the text before the caret (64 graphemes, pre-reserved buffer). Advanced in lockstep with every own insert/delete; resynced from ONE `documentContextBeforeInput` read only off the keystroke path (`flushSideEffects`, `viewWillAppear`, external `textDidChange`, coalesced `selectionDidChange`). Drives auto-cap, smart punctuation, auto-cap "I", word-delete chunks and predictive validation. This is SnipKey's implementation; SwiftKey symbol names alone do not establish equivalent internals. | `QWERTY/V2/TypingContextMirror.swift`; `QWERTYInputTracking.contextMirror`. |
| **Per-field trait cache** | `HostInputTraits` (keyboardType, appearance, returnKeyType, autocap, locale codes…) read in `refreshHostInputTraits()` only from `viewWillAppear`, external changes, `flushSideEffects` and `currentInputModeDidChangeNotification`. `updateQWERTYState` on an own insert performs zero proxy reads. | `KeyboardViewController.swift` `cachedHostInputTraits`. |
| **KeySurface per page** | Page switch (123/ABC, auto-return-to-letters) and shift toggles are `isHidden` flips over pre-built layers; a style change (appearance/size/scale/subtitle) is the only full rebuild. `handleMemoryPressure()` drops inactive pages. | `KeyLayerRenderer.swift` `KeySurface`, `GlyphLayers`. |
| **Staged init** | `viewDidLoad` builds only what the first keystroke needs; clipboard polling, SwiftData warm-up, reminder/timer flags and predictive warm-up run once from the first `viewDidAppear` on the next runloop turn (`performDeferredSetup`). | `KeyboardViewController.swift`. |
| **VoiceOver elements on demand** | The ~35 `UIAccessibilityElement`s are built only while VoiceOver is running (`voiceOverStatusDidChangeNotification`), not on every page switch. | `KeyboardGestureCoordinator.rebuildAccessibilityElementsIfNeeded`. |
| **Coalesced side-effects** | Many commits in one runloop → **one** `documentContextBeforeInput` read; `scheduleSideEffectFlush` guards on a bool and posts a single `DispatchQueue.main.async`. | `KeyboardViewController.swift:466–515`. |
| **Async predictive** | English model and `UITextChecker` run on a serial background queue, with 40ms debounce and token cancellation. Exact bounded context is checked on publication and against the host on acceptance. | `PredictiveTextEngineAsync.swift`, `KeyboardViewController.swift`. |
| **HitGrid O(log n)** | Two binary searches (row seams, then column seams). 4 rows × ~10 keys → <4 iterations. Built only on layout change. | `KeyboardGestureCoordinator.swift:686–702`. |
| **Smart-touch ~200ns** | Row-filtered frame loop + bigram weight lookup + pure-math `DynamicHitResolver`. Plausible, uninstrumented. | `SmartTouchResolver.swift:30–76`, `DynamicHitResolver.swift:39–108`. |
| **Glyph cache** | SF Symbol renders memoized by `(name, size, weight, tintRGBA)`. Bounded by the ~6-symbol set. | `KeyLayerRenderer.swift:343–376`. |
| **Instant highlight** | All immediate-feedback layer mutations wrapped in `CATransaction.setDisableActions(true)`; only fade-outs animate. | `KeyLayerRenderer.swift:136,185`; `KeyboardCalloutView.swift:130`. |
| **Observable split** | Hot-path bookkeeping lives in non-`@Observable` `QWERTYInputTracking`; keystrokes cause **zero** SwiftUI invalidation until visible state changes. | `QWERTYKeyboardState.swift:30–77`. |
| **Native commit timing** | Highlight/callout at finger-down (perceived latency unchanged); the character commits at lift or on the next finger-down (rollover flush) — native semantics enabling slide-to-correct. `commitDispatch` telemetry keeps the pure XPC cost visible. | `KeyboardGestureCoordinator` `flushPendingCharacterPresses` / `commitPendingPress`. |

### 4.2 XPC / IPC surfaces
- **App Group UserDefaults** (`group.snipkey`) — synchronous settings reads
  (`autoCapitalizationEnabled`, `debugHitOverlayEnabled`, DEBUG engine toggles). Read at
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
- **Animation ownership:** ordinary input pops immediately; sliding between same-size keys may
  move for 70ms. Every presentation clears prior slide/scale animation before assigning geometry.
  Release uses one explicit opacity fade (no competing implicit fade); cancellation snaps hidden.
  The popup alone owns its frame—an enclosing emoji panel must not resize it to panel bounds.
  A real UIKit host probe reproduced a stale slide surviving hide/new press before this fix and
  confirmed it is removed afterward. Per-touch highlight release also disables implicit animation.

### 5.3 Special keys & native behaviors
- **Slide gestures (native commit timing):** a pending letter press retargets across keys with
  12pt hysteresis (raw geometry — the prior never fights the finger; coalesced touches at 120Hz);
  the balloon glides between same-size keys (~70ms ease-out). Sliding off the bottom cancels;
  sliding onto backspace/shift/mode voids the press. **Shift-slide-release** types one capital;
  **123-slide-release** types the symbol and snaps back to letters (the plane switches at the
  mode key's touch-down). A slid-and-corrected commit feeds the offset model a gold label
  (`TouchOffsetModel.recordCorrected`, ±0.3 fraction clamp, plausible-aim-error gated).
- **Shift / caps lock:** `.disabled`→`.enabled` (one-shot, auto-resets after a char) → double-tap
  within 300ms → `.locked`. Fires on touch-down for instant visual change. (`QWERTYKeyboardState.swift:121–153`.)
- **Space:** commits on touch-UP (must distinguish tap from cursor mode). Hold 250ms or drift 14pt →
  `SpaceBarCursorController` cursor-drag (12pt/char, ProMotion-smooth via `coalescedTouches`),
  suppresses the space on lift. Double-space → auto-period `". "`.
- **Backspace:** deletes on touch-down; after a 500ms hold, repeats at ~100ms/char for 15 ticks,
  then escalates to whole-WORD chunks at ~350ms/tick (`KeyboardCommitPipeline.commitWordBackspace`,
  grapheme-safe, clamped 1–30) — native pacing. (Legacy kill-switch path keeps the old
  accelerating `1→2→3` burst ramp.)
- **Accent menu:** 400ms long-press on a still-pending press → open menu (nothing was committed,
  so nothing to undo — no ghost-character flicker) → drag to select → insert on release. URL/email
  fields get `.` → domain menu. (Legacy timing still undoes its optimistic commit first.)
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

### 5.5 English swipe typing

**Product setting:** Settings → Experimental → **Swipe to Type**, enabled by default in Debug and
Release. Stored in SwiftData and mirrored to App Group defaults. Reopening the keyboard refreshes
the setting; disabling restores the existing tap/slide path. No Full Access or network is required.
Swipe is limited to the letters page and fields permitting smart transforms (not URL, email or
numeric/literal fields). Legacy commit-on-down timing never arms swipe.

| Component | Responsibility |
|---|---|
| `SwipeTypes.swift` | Timestamped points, lowercase key-center geometry, ranked word candidates. |
| `SwipeGestureController.swift` | Single owner, buffered recognition, cancellation, bounded 512-point capture. |
| `SwipeTrailLayer.swift` | Age-limited Catmull-Rom trail; coalesced samples painted once per display frame, explicit lift fade. |
| `SwipeLexicon.swift` | Immutable 50,000-word English lexicon, flat letter storage, first/last-letter buckets and word-frequency priors. |
| `SwipeDecoder.swift` | Arc-length resampling and smoothing; location, shape and direct endpoint costs plus frequency prior. |
| `SwipeTypingEngine.swift` | Background one-time lexicon loading, readiness gate, synchronous lift decoding to preserve input order. |

The coordinator buffers from touch-down but leaves ordinary taps and short slide corrections
unchanged. Recognition requires 1.5 key widths of travel and an excursion of at least 0.8 widths
from the starting point; jitter near the origin does not activate it. A direct short slide such
as W→E remains a correction, not the word “we”: tap such words or use a wider swipe curve.
These are SnipKey thresholds, not recovered platform constants.

Recognition cancels the letter's long-press timer, highlight and callout. Other finger-downs
during an active swipe are ignored. Rollover-committed letters and accent-menu presses cannot
later become swipes. Lift includes the final point, decodes once, and inserts the best word;
cancellation, geometry changes, host context changes or keyboard disappearance drop the trace.
Taps remain available while the lexicon loads.

`commitSwipeWord` applies current shift casing, inserts a leading separator after an existing
letter/digit and a trailing smart space. Subsequent punctuation consumes that smart space.
Up to two alternatives use the existing toolbar replacement path, replacing the committed
word **and its trailing space**. Publishing alternatives invalidates earlier asynchronous
predictions; subsequent edits/caret changes invalidate them. Own-write callback classification
still uses the controller's existing 50ms heuristic; unusual host echo timing needs device checks.

Repeated letters collapse geometrically; frequency distinguishes identical paths such as
“god”/“good”. Selected apostrophe-free stems become contractions, while “well”, “were”,
“ill”, “id” and “its” remain literal. This is an offline unigram decoder: no contextual neural
model, learned user vocabulary or non-English lexicon. Out-of-vocabulary names are best tapped.
Candidate confidence is relative ranking, not a calibrated correctness probability.

Trace and candidate templates now use the same spatial smoothing and arc-length resampling.
Previously, smoothing rounded only the observed gesture, so even a key-center trace was compared
with a different target shape. Both pipelines reuse the same scratch buffers; a running-sum box
filter is linear and candidate scoring adds no per-word allocation. A soft in-key distance cost
retains nearby-key evidence instead of discarding it inside a half-key-width dead zone. Rigid
order/shape matching, endpoint gates, frequency priors and top-K pruning remain intact.

A broader throwaway replay compared the prior decoder with this correction using the real
50,000-word lexicon. Development: 270 words / 3,510 traces, top-1 **96.67% → 97.15%**, top-3
**99.40% → 99.60%**. A disjoint 160-word / 2,080-trace set with stronger perturbations:
top-1 **92.50% → 93.03%**, top-3 **98.65% → 98.85%** (25 top-1 gains, 14 losses).
Modes include jitter, uneven speed, corner cutting, curvature, missing endpoints, adjacent-key
bias, repeated-letter loops and sparse samples. Empty/single/stationary traces and zero-candidate
requests still reject. These are synthetic ranking measurements, not real-user accuracy.
Symmetric preprocessing costs more: host release-build p95 was approximately **2.2ms**, versus
**1.5ms** before, after eliminating repeated segment-length square roots during resampling.
Decoding remains synchronous at lift to preserve input order; phone latency
and perceived accuracy require physical-device validation. Flexible alignment and asymmetric
soft-distance variants were rejected after accuracy regressions.

**SwiftKey evidence boundary.** The inspected Microsoft SwiftKey 4.3.7 IPA is FairPlay-encrypted.
Exported symbols included `SKFlowGestureRecognizer` (`beforeRecognizedPoints`,
`minimumDistanceToRecognize`), `SKFlowProcessor`, `flowEnabled`, `FlowSmootherCatmullRom`,
`FluencyTouchHistory.appendTrace`, and continuous-touch curve/direction/endpoint scoring names.
They support an architectural inference of buffered capture → trace decoder → prediction commit
with a separate trail. They do not reveal executable bodies, scoring weights, training data or
accuracy. SnipKey's shape/location matcher is independently implemented; no SwiftKey/QuickPath
equivalence is claimed.

**Resource regeneration:** uses [Norvig's word counts](https://norvig.com/ngrams/) and the local
macOS Web2 dictionary as a word gate. Generator comments record source attribution and exact
input/output hashes; attribution is not a redistribution-license determination.

```sh
python3 tooling/swipe/build_swipe_lexicon.py /path/to/count_1w.txt \
  SnipKeyboard/Resources/swipe-lexicon-en.txt --dictionary /usr/share/dict/words
```

The resource is copied into both app and keyboard-extension bundles. Regeneration was byte-identical,
including after reversing input order. A throwaway executable exercised the real decoder and capture
code: 19 words with ideal and deterministic noisy paths ranked correctly first (38/38), plus checks
for contractions, repeated letters, lift endpoints, jitter, ownership, cancellation and bounded
capture. This small synthetic smoke is not a real-user accuracy benchmark; phone typing and trail
appearance require manual validation. No permanent tests or simulator were added.

### 5.6 Emoji surface and hold chooser

`KeyboardSurface` exclusively selects `.typing`, `.emoji`, or `.snippets`. Tap the smiley key
next to 123 to open emoji; hold for 400ms to use the existing action callout with **Emoji**
and **Snippets** destinations. Selection changes surfaces, never inserts the menu label.
VoiceOver exposes both destinations as custom actions. No new haptics are added.

`EmojiKeyboardView` is lazily mounted as a full-height UIKit sibling of the native keys.
`EmojiBrowseLayout` uses continuous horizontal, column-major four-row scrolling through recents
and eight displayed categories (Smileys/People are combined without removing catalog entries).
Category taps scroll to sections; scrolling updates the selected icon. Portrait density caps at
eight columns. `EmojiSurfaceGeometry` fits all nine category icons between borderless ABC/delete
controls; the selected icon has a circular background. Skin-tone/mixed-tone selection is retained.
Surface changes cancel active key/delete/menu interactions and clear stale predictions.

Search uses a full-width rounded `EmojiSearchField`, a separate 52pt horizontal result strip,
then the original-height native keys. The controller expands the extension only for this search
surface. The `.emojiSearch` layout has wide 123/Done controls and no redundant emoji toggle.
`EmojiSearchField` draws a grapheme-aware caret, supports tap/drag positioning and clear, and never
becomes first responder. Native keys use isolated state, context mirror, caret, actions and callout;
query edits never reach the host. Done returns to browsing; choosing a result inserts only its emoji.
Catalog search runs off-main with cancellation and exact-query validation. Caret-only changes do not
search, unchanged results do not reload or reset the horizontal offset, and the panel never assigns
the popup's frame. Host appearance changes preserve search. Names and controls are accessible.
Recents retain exact sequences, deduplicate, cap at 40, and use a local defaults mirror;
shared App Group persistence is used only with Full Access. Browsing/search require no network.

Verification used actual UIKit components in a temporary Mac Catalyst host (not a simulator):
horizontal collection navigation, grapheme caret/clear actions, light/dark rendered snapshots,
and the production key renderer below search/results. Geometry covered six widths and all three
search key planes. These component probes do not replace physical-device touch/drag validation.

`EmojiCatalog` decodes the bundled binary plist once off-main: 3,781 fully-qualified
Unicode 16.0 sequences, 1,906 bases, nine categories. The data comes from
[Unicode emoji-test.txt](https://www.unicode.org/Public/emoji/16.0/emoji-test.txt),
not SwiftKey assets; Unicode License V3 is bundled. Regenerate with:

```sh
python3 scripts/generate_emoji_catalog.py
```

SwiftKey's inspected resource inventory contains eight category records, versioned variant
records, and `SKEmojiProcessorDelegate.insertEmoji` parameters for skin-tone and insertion
source. This is static resource/header evidence, not observed runtime behavior or recovered
implementation. SnipKey's UI and catalog are independently implemented.

### 5.7 English suggestions

`EnglishSuggestionModel` reuses the immutable 50,000-word swipe lexicon (loaded once across
both consumers) and a bounded [Norvig bigram corpus](https://norvig.com/ngrams/count_2w.txt):
32,768 pairs, 5,946 predecessors, at most 24 successors each, plus unigram priors for `a`/`I`.
Prefix completion starts at one character. A nonempty partial retains its literal typed slot,
then the best and alternate distinct choices. Whitespace enables next-word choices with a
zero-length replacement span. Ranking combines frequency, preceding-word context and bounded
one-edit corrections including transpositions; system spelling supplements it. Apostrophes,
curly contractions, title case, caps and supplementary lexicon shortcuts retain their spans.
The existing system-checker path remains for other languages.

Space does **not** autoaccept a correction. Toolbar acceptance is centralized in the controller:
candidate membership, the exact 64-character input snapshot and an empty host selection must
still match. It then inserts the chosen word plus smart space (typed-slot acceptance adds only
the space). Swipe alternatives use the same validation. URL/email/literal fields opt out.

```sh
python3 tooling/swipe/build_english_bigrams.py /path/to/count_2w.txt /path/to/count_1w.txt \
  SnipKeyboard/Resources/swipe-lexicon-en.txt SnipKeyboard/Resources/english-bigrams-en.tsv
```

Generators record input digests and attribution; Norvig's code license does not establish
a separate corpus redistribution license. This is a bounded web-frequency model, not neural
prediction or SwiftKey accuracy parity. Uncommon contexts back off to frequency.

Throwaway executable smoke checks exercised actual bundled data: emoji search, variants,
local grapheme/caret edits and recents persistence; English prefixes, `hte` → `the`,
`recieve` → `receive`, `thank ` → `you`, contextual `I c` → `can` versus `of c` → `course`,
contractions, casing and boundaries. No permanent tests or simulator were added.
UIKit layout, hold selection and real-host typing remain physical-device manual checks.

### 5.8 Quick commands and natural duration phrases

The top-left code button retains tap-to-insert `/`. Hold it for a native context menu containing
Timer and Reminder; VoiceOver also exposes named actions. Each inserts `/timer ` or `/remind `,
not a scheduled notification. Existing integration settings and explicit Create acceptance remain.

When the host field is empty, a bell immediately left of Paste inserts `/remind ` through the same
command path. It remains available without clipboard content. `isDocumentEmpty` is refreshed with
the coalesced host reconciliation: empty before/after context, `hasText == false`, and no selection;
the start of a populated field is not empty. Own insertion hides it immediately without a proxy read.
The obsolete fixed-delay reminder action has been removed; scheduling still requires Create acceptance.

`CommandInsertionPlan` computes a single selection-aware host edit. A selection receives insertion
only; a live slash query is replaced only at a token boundary. Other text is retained with a
separating space. The controller reads fresh host context, cancels stale touches/predictions and
clears smart-space/auto-period state before applying the edit and coalescing side effects.

`CommandSource` requires a standalone slash trigger and retains original Unicode source indexes.
URLs, embedded/prefix triggers, a subsequent slash command, and newline-crossing text do not activate
the timer/reminder parser. `DurationExpression` is shared by the two parsers: integer digits,
English one–ninety-nine and a/an, compact units, and compound phrases such as `one hour and five
minutes`. Timers also accept `for twenty-five minutes`. Relative reminders accept duration-before-task
or a trailing duration; calendar days/weeks/months retain wall-clock semantics.

The actual parser/insertion smoke identified 29 baseline gaps and passed 84 final checks, including
false triggers, exact deletion spans, selected-text safety, huge values and calendar-relative days.
Decimal/negative durations are rejected rather than partially harvested as unrelated integers.

### 5.9 Inline colon emoji suggestions

`EmojiShortcodeQuery` recognizes a token at the caret such as `:`, `:sm`, `:eyes`, or `:eyes:`.
Opening colons require a document/whitespace/opening-punctuation boundary; URLs, times, embedded
identifiers, escaped colons and double colons do not activate. ASCII letters, digits, underscores,
hyphens and signed aliases are accepted. Open tokens cannot replace the left half of a shortcode.

The existing serial `PredictiveTextEngineAsync` queue handles the query before word prediction.
`EmojiCatalog.loadBundled()` shares one off-main decode between inline suggestions and the browser.
Matching uses Unicode English names/keywords plus common Slack aliases (not the complete Slack
alias inventory). Exact names/aliases rank first; all matching base emoji are offered, without
tone duplicates or the word row's three-result cap. Bare colon browses all 1,906 bases.

`PredictiveTextState.prepareForEmojiQuery` reserves the emoji row immediately, including while
pending or unmatched; command pills retain their existing precedence. `EmojiSuggestionsView`
uses a lazy horizontal row with 44pt targets and spoken names. A new token resets scrolling;
identical publications preserve it. iOS 26 automatic scroll-edge effects are hidden because they
blurred the entire short toolbar in the native host probe. Explicit colon queries remain available
after ordinary word suggestions are dismissed for the session.

Acceptance revalidates candidate membership, the existing 64-grapheme context snapshot, the full
host-window token, after-caret boundary and empty selection. It replaces exactly the colon token,
adds no space, clears smart-space/auto-period/prior state, and records recents. There is no automatic
conversion on typing a closing colon. Emoji results never supply the next-letter touch prior.

Throwaway probes exercised the actual catalog/tracker/state and UIKit prediction queue: `:eyes`
ranked eyes first, `:sm` returned 40 options, aliases/false triggers/mid-token boundaries passed,
and stale/cancelled results did not publish. Actual UIKit text edits preserved a Unicode prefix
and punctuation. The production SwiftUI toolbar was rendered in 36 width/theme/state scenarios;
its real scroll view preserved/reset offsets as intended at 320, 440 and 768pt. Final finger feel
and host-app proxy behavior still require the physical-device check. No permanent tests or simulator.




---

## 6. Optimization Opportunities & Risks

Found in the code (not speculative). Severity is relative to an already-fast baseline.

| # | Item | Severity | Location |
|---|---|---|---|
| 6.1 | ✅ FIXED — setting cached once per session in `configure(...)`; `SmartTouchResolver.resolve` takes `enabled` as a parameter. | — | `KeyboardGestureCoordinator.configure` |
| 6.2 | ✅ FIXED — the `RenderSignature` short-circuit runs before any layout/grid work. | — | `performRebuildLayout` |
| 6.3 | ✅ FIXED — `KeyHitView`s are reused/parked, never destroyed mid-session (also required so mid-gesture page swaps don't cancel the sliding touch). | — | `rebuildHitViews` |
| 6.4 | ✅ FIXED — `TypingContextMirror` (`QWERTYInputTracking.contextMirror`) answers every `- . " '` transform, auto-cap and word-delete with zero XPC; the host is read only off the keystroke path. | — | `KeyboardCommitPipeline.applySmartPunctuation`, `KeyboardViewController.updateAutoCapitalization` |
| 6.7 | ✅ FIXED — page switch / shift toggle no longer tear down and re-rasterize ~35 layers (`KeySurface` per page, pre-built case/icon variants). | — | `KeyLayerRenderer` |
| 6.8 | ✅ FIXED — `UITextInputMode.activeInputModes` no longer read in every `layoutSubviews`; cached in `HostInputTraits.localeCodes`. | — | `KeyboardViewController.refreshHostInputTraits` |
| 6.9 | ✅ FIXED — memory warnings drop rebuildable caches (`handleMemoryPressure` chain) instead of letting iOS kill the extension. | — | `KeyboardViewController.didReceiveMemoryWarning` |
| 6.10 | ✅ FIXED — row changes while sliding now need 10pt past the vertical seam (`SlideHysteresis.vertical`); previously any wobble across the row gap flipped keys. | — | `KeyboardGestureCoordinator.slideClearsHysteresis` |
| 6.5 | ✅ FIXED — the save is deferred off the insert turn (`Task { @MainActor }`). | — | `QWERTYKeyboardView.insertSnippet` |
| 6.6 | One `Task { @MainActor }` allocation per `withObservationTracking` `onChange` fire (re-registration pattern). Short-lived; negligible. | Very low | `NativeKeyboardV2View.swift:91–97` |


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
- **Width-math duplication:** `KeyboardLayoutResolver.computeWidths` is now the single
  source of key widths (V1 `KeyRowView` math and the popup-positioning duplicate in
  `KeyboardDimensions` were removed with V1).
- **`UIColor.label` trap (handled):** `CATextLayer` has no trait collection, so dynamic colors
  resolve against `UITraitCollection.current` (often dark in an extension). The renderer deliberately
  uses explicit `white`/`black` indexed on its own `isDark` flag.
- `KeyboardGestureCoordinator` / `KeyLayerRenderer` / `KeyboardCalloutView` need a view/layer host →
  not unit-testable without a screen context.

---

## 8. V1 → V2 Evolution (V1 removed 2026-08; table kept for design rationale)

| Area | V1 (removed) | V2 |
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

The V2 keyboard is the only implementation — the `useNativeKeyboardV2` flag and the V1
per-key SwiftUI path were removed. Smart Touch Targeting is likewise always on
(`probabilisticTouchEnabled` flag removed).

---

## 9. Settings Reference

| Setting | Key | Default | Effect |
|---|---|---|---|
| **Next-gen touch engine** | `useProbabilisticHitResolver` | `true` | 2D power-diagram resolver + per-user learning vs legacy 1D shift |
| Auto-capitalization | `autoCapitalizationEnabled` | `true` | Sentence/word auto-cap + auto-"I" |
| Swipe to Type | `swipeTypingEnabled` | `true` | Offline English swipe decoding; refreshed when the keyboard appears |
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
- **Predictive text:** `PredictiveTextEngineAsync.swift` + `EnglishSuggestionModel.swift`; see §5.7.
- **Swipe recognition / ranking:** `SwipeGestureController.swift` + `SwipeDecoder.swift`; see §5.5 for lexicon regeneration and limitations.
- **Emoji / local search:** `EmojiKeyboardView.swift` + `EmojiCatalog.swift`; see §5.6.
- **XPC / state hydration:** `KeyboardViewController.swift` + `KeyboardActions.swift` + `QWERTYKeyboardState.swift`.
