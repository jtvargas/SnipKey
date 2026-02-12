# Probabilistic Touch Targeting — Implementation Plan

Dynamic hit-target resolution for SnipKey's QWERTY keyboard, modeled after the
native iOS keyboard's context-aware touch system.

---

## Problem

The keyboard currently uses **static, equal-sized hit targets** for every key.
Each key owns `keyWidth + keyGap/2` on each side — a fixed rectangle regardless
of what the user is likely typing. The native iOS keyboard (and Grammarly,
SwiftKey, etc.) uses **probabilistic touch targeting**: after the user types "t",
the hit area for "h" expands because "th" is an extremely common bigram in
English, while "g" and "b" shrink. This makes typing feel significantly more
accurate without the user consciously noticing.

### How It Works on iOS

1. **Language-model probabilities**: Given the preceding 1–2 characters, each
   letter key receives a probability weight based on bigram/trigram frequency
   data.
2. **Dynamic boundary shifting**: The touch boundary between two adjacent keys
   shifts toward the less-probable key, giving the more-probable key a larger
   tappable area.
3. **Gaussian touch modeling**: The finger contact point is treated as the center
   of a 2D Gaussian distribution, and the key with the highest probability mass
   under that distribution wins.
4. **Visual keys don't change**: This is entirely invisible — key caps, sizes,
   and positions remain fixed. Only the touch resolution logic changes.

---

## Architecture Overview

```
                        ┌──────────────────────────────────┐
                        │    KeyboardViewController        │
                        │  (UIKit — owns textDocumentProxy)│
                        └──────────┬───────────────────────┘
                                   │ provides context
                                   ▼
                        ┌──────────────────────────────────┐
                        │    ProbabilisticTouchContext      │
                        │  (non-observable, updated on each │
                        │   keystroke — zero re-renders)    │
                        └──────────┬───────────────────────┘
                                   │ feeds weights to
                                   ▼
┌──────────────────────────────────────────────────────────────────────┐
│                   ProbabilisticRowTouchLayer                        │
│  (UIViewRepresentable — one per character row)                      │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  On touchDown:                                               │    │
│  │  1. Get touch X position within row                          │    │
│  │  2. Compute dynamic boundaries from key weights              │    │
│  │  3. Resolve to winning key index                             │    │
│  │  4. Fire that key's action (insert char + show popup)        │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  Uses: BigramEngine.weights(after: lastChar) → [Character: Float]   │
│        DynamicHitResolver.resolve(touchX, keyRects, weights)        │
└──────────────────────────────────────────────────────────────────────┘
```

**Key design constraint**: The touch resolution runs on the main thread during
`touchDown`, so it must be extremely fast (< 0.1ms). All lookup tables are
pre-computed static data. No allocations on the hot path.

---

## New Files

| File | Purpose | Estimated Lines |
|------|---------|-----------------|
| `BigramEngine.swift` | Static English bigram frequency table + probability lookup | ~180 |
| `DynamicHitResolver.swift` | Computes adjusted touch boundaries and resolves touch → key | ~120 |
| `ProbabilisticRowTouchLayer.swift` | UIViewRepresentable row-level touch interceptor | ~150 |
| `ProbabilisticTouchContext.swift` | Non-observable context tracker shared via environment | ~60 |

## Modified Files

| File | Changes |
|------|---------|
| `KeyRowView.swift` | Character-only rows use `ProbabilisticRowTouchLayer` overlay instead of per-key `KeyTouchArea` |
| `KeyButtonView.swift` | Character keys in probabilistic rows skip their own `KeyTouchArea`; add external touch trigger API |
| `KeyboardViewController.swift` | Update `ProbabilisticTouchContext` on each keystroke (in `keyboardActionsStruct`) |
| `KeyboardActions.swift` | Add `lastCharacterTyped` closure or context reference |
| `QWERTYKeyboardState.swift` | Extend `QWERTYInputTracking` with `lastCharacterTyped: Character?` |

---

## Detailed Implementation

### Phase 1: Bigram Frequency Engine

**File: `SnipKeyboard/QWERTY/BigramEngine.swift`**

```swift
/// Static English bigram frequency table.
/// Provides P(nextChar | prevChar) weights for all 26 letter keys.
///
/// Data source: Peter Norvig's English letter pair frequencies
/// (compiled from Google's Trillion Word Corpus).
///
/// Design: All data is static — zero allocations per query.
/// Lookup is O(1) via Dictionary<Character, [Character: Float]>.
enum BigramEngine {

    /// Returns probability weights for each letter given the preceding character.
    /// Weights are normalized to sum to 1.0 across all 26 letters.
    /// Returns uniform weights (nil) if prevChar is nil or not a letter.
    static func weights(after prevChar: Character?) -> [Character: Float]?

    /// Raw bigram frequency table: bigrams["t"]!["h"] = 0.33 (etc.)
    /// Pre-normalized so each inner dictionary sums to 1.0.
    private static let bigrams: [Character: [Character: Float]] = [
        // 26 entries, each mapping to 26 floats
        // Example: "t" → ["h": 0.330, "o": 0.155, "i": 0.105, "e": 0.092, ...]
        // ...
    ]
}
```

**Data strategy**:
- Use the top ~100 most impactful bigram pairs (covering ~80% of English text).
- For uncommon preceding characters, fall back to **unigram frequencies**
  (overall letter frequency: E=12.7%, T=9.1%, A=8.2%, etc.).
- For non-letter preceding characters (space, punctuation, digits), use
  **word-initial letter frequencies** (T=16%, A=11%, S=8%, etc.) which differ
  from overall unigram frequencies.

**Performance**: Single dictionary lookup = ~20ns. Well within budget.

---

### Phase 2: Dynamic Hit Target Resolver

**File: `SnipKeyboard/QWERTY/DynamicHitResolver.swift`**

```swift
/// Resolves a touch X-coordinate to the intended key index within a row,
/// using probability-weighted dynamic boundaries.
///
/// Algorithm:
/// 1. Start with equal-width key regions (current static layout)
/// 2. For each boundary between adjacent keys, shift it proportionally
///    to the ratio of their probability weights
/// 3. Clamp the shift so no key shrinks below 60% of its original width
///    (prevents keys from becoming untappable)
/// 4. Find which adjusted region contains the touch point
enum DynamicHitResolver {

    /// Resolve a touch point to a key index.
    ///
    /// - Parameters:
    ///   - touchX: X coordinate of the touch within the row (0 = left edge)
    ///   - keyRects: Array of (x, width) tuples for each key's visual center
    ///   - weights: Probability weight for each key (same count as keyRects)
    ///   - minWidthRatio: Minimum key width as fraction of original (default 0.60)
    /// - Returns: Index of the winning key
    static func resolve(
        touchX: CGFloat,
        keyRects: [(centerX: CGFloat, width: CGFloat)],
        weights: [Float],
        minWidthRatio: CGFloat = 0.60
    ) -> Int
}
```

**Boundary adjustment algorithm**:

```
For keys A (left) and B (right) with weights wA and wB:
  Original boundary = midpoint between A's right edge and B's left edge
  Weight ratio = wB / (wA + wB)
  Shift = (weight ratio - 0.5) * keyGap * shiftMultiplier
  Adjusted boundary = original boundary + shift

  shiftMultiplier controls how aggressively boundaries move.
  Recommended: 2.0 (moderate) to 4.0 (aggressive)
```

The shift is **clamped** so neither key shrinks below `minWidthRatio` of its
original width. This prevents extreme cases (like Q→U after "Q") from making
neighboring keys impossibly small.

**Gaussian refinement** (optional, Phase 2b):
- Instead of hard boundaries, model the touch as a Gaussian with σ ≈ 8pt
- For each key, compute the integral of the Gaussian over the key's region,
  multiplied by the key's language-model probability
- Pick the key with the highest product
- This is more accurate but costs ~0.5μs more per touch (still negligible)

---

### Phase 3: Row-Level Touch Interceptor

**File: `SnipKeyboard/QWERTY/ProbabilisticRowTouchLayer.swift`**

```swift
/// A transparent UIKit touch layer that covers an entire row of character keys.
/// Intercepts touches and resolves them to the most probable key using
/// DynamicHitResolver, then fires that key's action.
///
/// This replaces individual KeyTouchArea instances on character keys.
/// Special keys (shift, backspace, space, return) are NOT covered by this
/// layer — they keep their own touch handling.
struct ProbabilisticRowTouchLayer: UIViewRepresentable {
    let keys: [String]                    // Characters in this row (e.g., ["Q","W","E",...])
    let keyRects: [(centerX: CGFloat, width: CGFloat)]  // Visual key positions
    let rowIndex: Int
    let dimensions: KeyboardDimensions
    let onKeyTouchDown: (Int, String) -> Void   // (keyIndex, character) → insert + popup
    let onKeyTouchUp: () -> Void                // Hide popup
    let context: ProbabilisticTouchContext       // Current probability context

    func makeUIView(context: Context) -> ProbabilisticRowControl { ... }
    func updateUIView(_ uiView: ProbabilisticRowControl, context: Context) { ... }
}

/// UIControl subclass that handles touch events for an entire row.
final class ProbabilisticRowControl: UIControl {
    var keys: [String] = []
    var keyRects: [(centerX: CGFloat, width: CGFloat)] = []
    var weights: [Float] = []  // Updated by updateUIView when context changes
    var onKeyTouchDown: ((Int, String) -> Void)?
    var onKeyTouchUp: (() -> Void)?

    // On touchDown:
    // 1. Get touch location: let x = touch.location(in: self).x
    // 2. Resolve: let idx = DynamicHitResolver.resolve(touchX: x, ...)
    // 3. Fire: onKeyTouchDown?(idx, keys[idx])
}
```

**Critical detail**: The `UIControl` must be **transparent to non-character
touches**. If the row contains shift or backspace, those keys sit outside the
probabilistic layer and handle their own touches independently. The layer only
covers the character key region of the row.

---

### Phase 4: Context Tracking (Zero Re-renders)

**File: `SnipKeyboard/QWERTY/ProbabilisticTouchContext.swift`**

```swift
/// Tracks the last typed character for probabilistic touch resolution.
/// This is a plain class (NOT @Observable) — updates cause zero SwiftUI
/// re-renders. The ProbabilisticRowTouchLayer reads it via UIKit path only.
///
/// Updated on every keystroke via KeyboardActions, same pattern as
/// QWERTYInputTracking.
final class ProbabilisticTouchContext {
    /// The last character typed (lowercased). nil if last action wasn't a character.
    private(set) var lastCharacter: Character?

    /// Pre-computed weights for the current context.
    /// Recomputed only when lastCharacter changes.
    private(set) var currentWeights: [Character: Float]?

    /// Update after a character is typed
    func recordCharacter(_ char: Character) {
        let lower = Character(char.lowercased())
        if lower != lastCharacter {
            lastCharacter = lower
            currentWeights = BigramEngine.weights(after: lower)
        }
    }

    /// Reset context (after space, backspace, or non-character action)
    func recordNonCharacter() {
        lastCharacter = nil
        currentWeights = BigramEngine.weights(after: nil) // word-initial freqs
    }
}
```

**Performance**: `recordCharacter()` only recomputes weights when the preceding
character actually changes. During rapid typing of different characters, this
is one dictionary lookup per keystroke (~20ns).

---

### Phase 5: Integration into Existing Architecture

#### 5a. Extend `QWERTYInputTracking`

In `QWERTYKeyboardState.swift`, add a reference to the probabilistic context:

```swift
final class QWERTYInputTracking {
    // ... existing properties ...

    /// Probabilistic touch context — updated per keystroke, read by touch layers
    let touchContext = ProbabilisticTouchContext()
}
```

#### 5b. Update `KeyButtonView.handleTap()`

In the `.character` case, after `actions.insertText(textToInsert)`:

```swift
case .character(let char):
    let textToInsert = state.shiftState == .disabled ? char.lowercased() : char.uppercased()
    actions.insertText(textToInsert)
    state.inputTracking.recordAction(.character)
    state.inputTracking.touchContext.recordCharacter(Character(char))  // NEW
    // ...
```

Similarly for space/backspace/return, call `touchContext.recordNonCharacter()`.

#### 5c. Modify `KeyRowView` for Character-Only Rows

For rows 0 and 1 (all character keys), overlay the `ProbabilisticRowTouchLayer`
on top of the existing `HStack`:

```swift
var body: some View {
    let isAllCharacterRow = actions.allSatisfy { if case .character = $0 { return true }; return false }

    HStack(spacing: 0) {
        ForEach(Array(actions.enumerated()), id: \.element) { index, action in
            KeyButtonView(
                action: action,
                // ...
                isProbabilisticRow: isAllCharacterRow  // NEW: skip per-key KeyTouchArea
            )
        }
    }
    .overlay(alignment: .leading) {
        if isAllCharacterRow {
            ProbabilisticRowTouchLayer(
                keys: actions.compactMap { if case .character(let c) = $0 { return c } else { return nil } },
                keyRects: computeKeyRects(),
                rowIndex: rowIndex,
                dimensions: dimensions,
                onKeyTouchDown: { index, char in
                    // Insert character, show popup, haptic, etc.
                },
                onKeyTouchUp: {
                    // Hide popup
                },
                context: state.inputTracking.touchContext
            )
        }
    }
}
```

#### 5d. Mixed Rows (Row 2: shift + letters + backspace)

Row 2 has both character and special keys. Two approaches:

**Option A (Simpler)**: Only apply probabilistic targeting to the character
portion of the row. The `ProbabilisticRowTouchLayer` covers only the middle
section (e.g., Z-X-C-V-B-N-M), sized and positioned to exclude shift/backspace
areas.

**Option B (Uniform)**: Apply probabilistic targeting to all character keys,
with the layer geometrically clipped to the character key region. Special keys
keep their own `Button`/`KeyTouchArea` handlers.

Recommended: **Option A** — simpler and row 2 has fewer ambiguous touches
because the character keys are flanked by distinctly wider special keys.

#### 5e. Pass Context Through Environment or Direct Reference

Since `ProbabilisticTouchContext` is non-observable, it can't use SwiftUI
environment. Two options:

1. **Direct reference via `KeyboardActions`**: Add a
   `touchContext: ProbabilisticTouchContext` property to `KeyboardActions`.
   Simple, no new plumbing.

2. **Closure in `KeyboardActions`**: Add `getCurrentWeights: () -> [Character: Float]?`
   that reads from the context lazily. Avoids storing the reference.

Recommended: Option 1 — the struct already carries other non-SwiftUI state.

---

## Row Layout & Touch Geometry

Understanding exactly how keys are laid out is critical for the resolver.

### Current Static Layout (Row 0: QWERTYUIOP)

```
Screen edge                                                    Screen edge
│←sideEdge→│←───keyWidth───→│←keyGap→│←───keyWidth───→│  ...  │←sideEdge→│
│           ╔═══════════════╗        ╔═══════════════╗        │
│           ║       Q       ║        ║       W       ║   ...  │
│           ╚═══════════════╝        ╚═══════════════╝        │
│                                                              │
│←─── tappable area: sideEdge + keyWidth + keyGap/2 ──→│      │
```

### Dynamic Layout (After Typing "T")

```
Touch boundaries shift — "H" expands, neighbors shrink:

│           ╔═══════╗   ╔═══════╗  ╔═══════╗           │
│           ║   G   ║   ║   H   ║  ║   J   ║           │
│           ╚═══════╝   ╚═══════╝  ╚═══════╝           │
│                                                        │
│←──── G touch ────→│←────── H touch ──────→│←─ J ──→│  │
         shrunk            expanded            shrunk
```

The visual key rendering stays identical. Only the invisible touch boundaries
move.

---

## Bigram Data (Top Pairs)

The following are the most impactful English bigrams that will meaningfully
shift touch boundaries. Full table has all 676 (26x26) pairs.

| Preceding | Most Likely Next | Weight | Impact |
|-----------|-----------------|--------|--------|
| T | H (33%), O (15%), I (10%), E (9%) | Very high | H dominates after T |
| Q | U (97%) | Extreme | U nearly guaranteed after Q |
| S | T (18%), H (12%), E (11%), I (9%) | High | Multiple likely successors |
| H | E (30%), I (16%), A (15%), O (13%) | High | Vowels dominate after H |
| W | A (22%), I (20%), H (18%), O (15%) | High | Spread across vowels+H |
| N | G (16%), D (13%), E (12%), T (11%) | Medium | Several competitors |
| Space | T (16%), A (11%), S (8%), I (7%) | High | Word-initial frequencies |

This data should cover English well. For a first pass, just the English bigram
table is sufficient. Multi-language support can be added later as separate
frequency tables.

---

## Performance Budget

| Operation | Time | When |
|-----------|------|------|
| `touchContext.recordCharacter()` | ~20ns | After each character insertion |
| `BigramEngine.weights()` lookup | ~20ns | Only when lastChar changes |
| `DynamicHitResolver.resolve()` | ~100ns | On each touchDown |
| `ProbabilisticRowControl.touchDown` | ~200ns | On each touchDown |
| **Total added per keystroke** | **< 0.5μs** | Well within 1.2ms budget |

The probabilistic system adds essentially zero measurable overhead. All data is
pre-computed, all lookups are O(1), and no allocations occur on the hot path.

---

## Testing Strategy

### Unit Tests

1. **BigramEngine**:
   - `weights(after: "t")` returns "h" as highest weight
   - `weights(after: "q")` returns "u" with weight > 0.9
   - `weights(after: nil)` returns word-initial frequencies
   - All weight arrays sum to ~1.0

2. **DynamicHitResolver**:
   - Equal weights → tap at key center resolves to that key
   - High weight for key B → tap at boundary A|B resolves to B
   - MinWidthRatio respected — no key shrinks below 60%
   - Edge keys (first/last in row) handle boundary correctly

3. **ProbabilisticTouchContext**:
   - `recordCharacter("t")` → `currentWeights` has "h" highest
   - `recordNonCharacter()` → resets to word-initial weights
   - Repeated same character → no recomputation

### Integration Tests

4. **Simulated typing sequences**:
   - Type "t" → touch between H and J → resolves to H
   - Type "q" → touch between U and I → resolves to U
   - Type "x" → touch between any two keys → nearly equal boundaries
   - Type space → touch near T → resolves to T (word-initial boost)

### Manual Testing Checklist

- [ ] Type common English words rapidly — verify accuracy improvement
- [ ] Type "the", "that", "this", "than" — H should feel easier to hit after T
- [ ] Type "qu" sequences — U should be very easy to hit after Q
- [ ] Type uncommon sequences ("qx", "zz") — boundaries should be near-equal
- [ ] Verify popup appears on the correct key (not the visually closest)
- [ ] Verify haptic fires on the resolved key
- [ ] Test in both light and dark mode
- [ ] Test on iPhone SE (small screen) and iPhone 16 Pro Max (large screen)
- [ ] Verify numbers and symbols pages are unaffected
- [ ] Verify special keys (shift, backspace, space, return) are unaffected
- [ ] Type in a non-English language — should fall back to unigram/uniform weights

---

## Implementation Order

| Step | Description | Dependencies |
|------|-------------|-------------|
| 1 | `BigramEngine.swift` — frequency table + lookup | None |
| 2 | `DynamicHitResolver.swift` — boundary computation + resolve | BigramEngine |
| 3 | `ProbabilisticTouchContext.swift` — context tracker | BigramEngine |
| 4 | `ProbabilisticRowTouchLayer.swift` — UIKit row touch handler | DynamicHitResolver, Context |
| 5 | Integrate into `KeyRowView` — overlay on character rows | All above |
| 6 | Update `KeyButtonView` — skip per-key touch for probabilistic rows | Step 5 |
| 7 | Update `QWERTYInputTracking` + `KeyboardActions` — wire context | Step 3 |
| 8 | Tune parameters — shiftMultiplier, minWidthRatio, σ | All above |
| 9 | Unit tests | Steps 1–3 |
| 10 | Manual testing + parameter tuning | All |

---

## Edge Cases & Safeguards

1. **Non-English text**: When the preceding character is not a-z (accented
   chars, CJK, emoji), fall back to uniform weights — no boundary shifting.

2. **Numbers/symbols pages**: Probabilistic targeting is **disabled** on
   non-letter pages. Static hit targets remain.

3. **First character** (no preceding context): Use word-initial letter
   frequencies (T, A, S, I are most common word starters).

4. **After space/punctuation**: Use word-initial frequencies, not overall
   unigram frequencies. This is important because the first letter of a word
   has a very different distribution than mid-word letters.

5. **After backspace**: Reset to word-initial frequencies (context is
   unreliable after deletion).

6. **Caps lock / shift**: The probabilistic engine operates on lowercased
   characters. The shift state affects the inserted character but not the
   probability weights. "T" and "t" use the same bigram row.

7. **Rapid typing**: The context updates synchronously in `handleTap()` before
   the next touch can arrive. No race conditions possible since all keyboard
   touches are serialized on the main thread.

8. **Special key adjacency**: In row 2 (shift-Z-X-C-V-B-N-M-backspace), the
   probabilistic layer does NOT extend over shift or backspace. Touches near
   the shift/backspace boundary resolve to Z or M respectively (no probability
   stealing from special keys).

---

## Future Enhancements (Out of Scope for V1)

- **Trigram support**: Use the last 2 characters instead of 1 for even better
  predictions (e.g., "th" → "e" is 50%+ vs "t" → "h" at 33%).
- **Per-user adaptation**: Track the user's actual bigram frequencies over time
  and blend with the static table.
- **Multi-language**: Swap frequency tables based on keyboard language setting.
- **Vertical boundary shifting**: Adjust boundaries between rows (e.g., after
  "t", expand row 1's "h" upward slightly into row 0's "y" region).
- **Touch velocity modeling**: Faster typing = wider Gaussian σ, accounting for
  less precise finger placement at speed.
- **Gaussian touch model** (Phase 2b): Replace hard boundaries with soft
  probability integration for even smoother resolution.
