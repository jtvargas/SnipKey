# SnipKey Keyboard V2 — Next-Gen Typing Quality Plan

> **Status:** **IMPLEMENTED and shipping by default** (see Implementation Status below). One item —
> data-driven *tuning* — is intentionally left as optional future work.
> **Goal:** A keyboard that feels extremely smooth, highly accurate, fast/reliable, consistent under
> high typing speed, predictable and forgiving — comparable to or better than the perceived typing
> quality of the stock iOS keyboard.
>
> Produced via a 4-phase pipeline: Phase 1 four parallel Sonnet research agents → Phase 2 Opus
> synthesis → Phase 3 Sonnet adversarial validation → Phase 4 this plan. Companion reference:
> [`V2_KEYBOARD_ARCHITECTURE.md`](./V2_KEYBOARD_ARCHITECTURE.md).

---

## Implementation Status (current)

The next-gen engine is **enabled by default** alongside the V2 keyboard. What shipped vs. what's
deferred:

| Area | Status | Where |
|---|---|---|
| Left-edge system-gesture deferral | ✅ Shipped | `KeyboardViewController` |
| ProMotion 120 Hz plist flag | ✅ Shipped | `SnipKeyboard/Info.plist` |
| Trait/dark-mode color correctness | ✅ Already handled | `KeyLayerRenderer` |
| 2D power-diagram resolver (Σ-norm argmin, anchor zone, anti-swallow) | ✅ Shipped, **default ON** | `ProbabilisticHitResolver` |
| Per-key weights + smoothing (EMA + deadband, word-boundary reset) | ✅ Shipped | `ProbabilisticTouchContext` |
| Curated trigram boosts (high-confidence patterns) | ✅ Shipped | `TrigramEngine` (in `BigramEngine.swift`) |
| Dynamic λ (β scaled by context confidence) | ✅ Shipped | `ProbabilisticTouchContext.confidence` + coordinator |
| Online per-user offset learning (clustered, confidence-gated, persisted) | ✅ Shipped | `TouchOffsetModel` |
| Shadow-mode telemetry + report screen | ✅ Shipped (off by default) | `TypingTelemetry`, `ShadowTelemetryView` |
| Live Voronoi debug overlay | ✅ Shipped (off by default) | coordinator `updateVoronoiDebugOverlay` |
| Settings toggles + version-string alignment | ✅ Shipped | `SettingsView`, `SettingsModel`, pbxproj |
| **Data-driven tuning** of β / σ / offset sign-scale | ⏸️ **Optional future** — see §15 | — |
| Population-prior fixed offsets (`PopulationOffset`) | ⏸️ Infra present, scale 0 (per-user learning preferred) | `PopulationOffset` |
| Full corpus-trained trigram / sequence decoding | ⏸️ Out of scope (needs a corpus) | — |
| Haptics | 🚫 Excluded by product decision | — |

Shipped defaults (research-shaped, conservative): `β = 0.5`, `σx = 13`, `σy = 16`, anchor inner
`50%×60%`, offset learning `α = 0.06` over 6 clusters with a 30-sample trust ramp.

---

## 0. The One-Sentence Thesis

Both source articles are by the same author (Daniel Buschek): the *Bayesian Keyboard* and *"What if
GUI elements were not limited to boxes"* (the ProbUI framework). Their shared thesis —
**decouple a control's visible box from its probabilistic interaction region** — is the spine of this
plan. We already do half of it (invisible `hitRect` ≠ visible `rect`). V2 makes the interaction
region *probabilistic and dynamic* while the visible keys stay pixel-frozen.

**The unification that drives the whole design:** Bayesian touch correction, dynamic Voronoi, and
per-user offset correction are not three features. They are one engine:

```
P(key k | touch t, context c)  ∝  N(t ; μ_k , Σ)  ·  P(k | c)^λ
```

Take the MAP decision (argmax) and, under a shared Gaussian, its **decision boundary is exactly a
power (Laguerre) diagram** over key centers:

```
choose k  =  argmin_k [ ‖t' − c_k′‖²  −  w_k ]
        w_k =  β · log P(k | c)            (β = 2σ²λ, one calibrated scalar)
        t', c_k′ in σ-normalized space     (handles taller vertical touch scatter, stays convex)
        c_k = key center + offset(row, hand, user)   ← offset correction is just moving the site
```

So: **offset correction moves the site, the language model sets the weight, and the "Voronoi" the
debug tool draws is literally the decision boundary.** One engine, three knobs.

---

## 1. Research Findings Summary

| Source / area | Most important takeaways |
|---|---|
| **Bayesian Keyboard** (Buschek, TDS) + Goodman 2002, Bi&Zhai 2013, Gunawardana 2010, Gboard/Sivek 2022 | Posterior `P(k|t,c) ∝ N(t;μ_k,Σ_k)·P(k|c)`; per-key μ is **not** the geometric center (systematic offset); **anchor zones** prevent overcorrection; key-target resizing is the spatial face of the posterior; log-space fusion with weight λ; per-user μ-offset learning is the single highest-ROI lever in production. |
| **Non-box GUI / ProbUI** (Buschek, UX Collective) + Bubble Cursor, CATKey, AVC, power diagrams | Visual bounds ≠ interaction bounds; weighted Voronoi (**power/Laguerre** variant keeps cells convex) "expands likely, shrinks unlikely" without moving visible keys; brute-force argmin over ~30 sites beats any tree (~150 ns); Apple patents the invisible post-touchdown target resize. |
| **Ergonomics & perceived latency** (Holz&Baudisch, Azenkot&Zhai, GripSense, FFitts, Ng/Deber) | Users land **above** key center, bias grows toward top rows; offset differs by hand/region/user; tap-latency JND ~69 ms but **variance hurts more than mean**; commit-on-touch-down removes the press-duration delay; immediate feedback defines *perceived* latency even when work is deferred. |
| **iOS feel & realtime rendering** (WWDC'15 #233, extension limits, Core Animation) | Stock-feel ingredients: commit-on-down, callouts, invisible target resize, multi-touch rollover, haptics; **hard ~30–40 MB dirty / ~77 MB total jetsam ceiling** kills in-extension neural LMs; `CADisableMinimumFrameDurationOnPhone` unlocks 120 Hz; haptics need **Full Access** or silently no-op; left-edge `UIScreenEdgePanGestureRecognizer` steals touches; CAShapeLayer ≫ drawRect for overlays; keep UserDefaults/XPC off the hot path. |

Full agent reports are condensed into §2–§4; primary citations are listed in §13.

---

## 2. Sonnet Agent Reports (condensed)

**Agent A — Bayesian prediction.** Verified the Medium article and the production lineage. Concrete
upgrade path for our 1D heuristic: (1) per-user key-center offset learning [highest ROI], (2) 2D
posterior scoring replacing the 1D shift, (3) anchor zone replacing the 60% clamp, (4) char trigram
replacing bigram, (5) dynamic λ by prior entropy, (6) on-device n-gram replacing UITextChecker on the
prior path. Pitfalls: overcorrection on proper nouns/code, secure fields, multilingual, cold start.

**Agent B — Voronoi / non-box.** Confirmed the ProbUI thesis and mapped it to a **power diagram** over
key centers with `w_i = k·log P(i|c)`. Brute-force argmin (~150–200 ns for 30 keys) replaces `HitGrid`
with no tree. Keep `KeyHitView` tiling (it solves UIKit's transparent-view hit-test quirk, a different
problem). Use power (not multiplicative) Voronoi so cells stay convex. Jitter mitigations: commit-touch
lock, EMA weight smoothing, deadband, log-scaling, anchor radius.

**Agent C — Ergonomics & perceived latency.** Quantified the touch-offset phenomenon (above-center,
growing top→bottom rows; lateral bias by hand). Hierarchical offset model: population prior →
per-posture → per-user EMA, clustered to avoid overfit (<50 samples ⇒ prior only). Perceived
responsiveness: keep highlight/haptic/commit synchronous; defer everything else; variance of latency
matters more than mean. Pitfalls: overfitting, posture changes mid-session, haptic battery.

**Agent D — iOS feel & rendering.** Established the hard extension memory ceiling and Full-Access haptic
gating, the left-edge gesture bug + fix, ProMotion plist flag, CAShapeLayer-over-CADisplayLink debug
overlay with a dirty-flag (≈0 GPU in steady state), CATextLayer dynamic-color trait trap, and "separate
the per-keystroke region recompute from the per-frame draw."

---

## 3. Opus Synthesis Report

**Recurring patterns (independently surfaced by ≥2 agents → high confidence):**
1. **Anchor zones** — every key always owns a central strip (A + B). Generalizes our `minWidthRatio=0.60`.
2. **Per-user/region offset μ-correction** is the top accuracy lever (A + C).
3. **Visual stability is sacrosanct** — keys never move; only invisible regions breathe (B + requirements).
4. **Keep settings/LM off the hot path** (A + D) — validates the per-keystroke UserDefaults read we already removed.

**Conflicts resolved:**
- *Haptics*: Full-Access-gated, `prepare()` once on appear (not per key), throttle in bursts, honor Low
  Power Mode. Low priority.
- *LM size*: jetsam ceiling forbids neural LMs → bundle a tiny char trigram/PPM (~280 KB–5 MB).
- *Sequence decoding* (token-passing, insertion/deletion, retroactive word rewrite): **out of scope** for
  V2 — it conflicts with commit-on-touch-down and our snippet-centric product. Future phase.

**Assumptions challenged:**
- No IMU/CoreMotion posture detection (risky in an extension) → infer handedness from **touch-X
  distribution** statistics instead.
- No per-frame Voronoi recompute → recompute **once per committed keystroke, off-main**; touch-down is a
  pure argmin.
- No speculative predicted-touch highlight (jitter risk, low value).

**Single unified engine** (the §0 formula) replaces both `HitGrid` resolution and the 1D
`DynamicHitResolver` shift with one offset-corrected, prior-weighted power-diagram argmin guarded by
anchor zones.

---

## 4. Sonnet Validation Report (key results folded into the plan)

Validation confirmed the math and surfaced gaps now incorporated below:

- **β = 2σ²λ is one identifiable parameter, not two.** Expose a single calibrated scalar `β`; never tune
  σ and λ separately. (§7)
- **Use a shared anisotropic Σ = diag(σx², σy²)** with σy > σx via a coordinate pre-transform — keeps
  cells convex while modeling taller vertical scatter. Per-key Σ would make boundaries hyperbolic
  (non-convex) — rejected. (§6)
- **Clip log P(k|c) to [log(1/V), 0]** so rare trigrams can't overwhelm clear touch evidence. (§7)
- **Ground-truth circular dependency (CRITICAL):** offset learning must only update on **high-confidence
  correct** keystrokes (trigram prob in top decile **and** no backspace within 500 ms), with a divergence
  guard that freezes/reset on runaway offsets. (§8)
- **Layout/rotation invalidates offsets** → store offsets as **fractions of key width/height, keyed by a
  layout hash** {keyboardType, orientation, size}. (§8)
- **Symbols/numbers pages** → set **β = 0** (uninformative prior), anchor-zones only, skip offset learning. (§6)
- **Per-update boundary-displacement clamp** (≤ ~12% key width) protects fast-typist muscle memory. (§6)
- **EMA reset on page/language change** to avoid stale-context jitter. (§6)
- Gaps the validator raised that our **existing architecture already handles** — reuse, don't rebuild:
  accent long-press (we delete the optimistic touch-down commit when the 400 ms menu fires),
  space-cursor (`SpaceBarCursorController`), and multi-touch rollover (`activePresses` keyed by touch).
  The new resolver changes **only which key a touch-down resolves to**, never the commit timing or the
  gesture lifecycle.
- Full **measurement & rollout** design (shadow mode, replay harness, metrics, CI gates) adopted in §10–§11.

---

## 5. Keyboard V2 Architecture (target)

The mount/render/state architecture from `V2_KEYBOARD_ARCHITECTURE.md` is **unchanged**. We replace one
seam — touch→key resolution — and add three off-hot-path subsystems.

```
touchesBegan ─► findKey(at:)                     [CHANGED]
                  └─ ProbabilisticHitResolver.resolve(t):
                       t' = Σ-normalize(t)                       // shared anisotropic transform
                       argmin_k ‖t' − c_k′‖² − w_k               // power-diagram, ~30 keys, ~150ns
                       anchor-zone guard + page/secure gates
              ─► (existing) commit-on-touch-down, highlight, callout, long-press, space-cursor — UNCHANGED

Off the hot path (per committed keystroke, main-async / background):
  • LanguagePrior      → w_k = β·clip(log P(k|c))     [bigram → trigram/PPM]
  • WeightSmoother     → EMA(α) + deadband + per-update displacement clamp → publishes w_k snapshot
  • OffsetModel        → confidence-gated EMA of (touch − center) per cluster, layout-keyed, App-Group persisted

Debug (DEBUG + runtime flag):
  • VoronoiDebugLayer  → CAShapeLayer cells + heatmap + telemetry HUD, CADisplayLink dirty-flag draw
```

**Components and where they live (all new types under `SnipKeyboard/QWERTY/V2/`):**

| Component | Replaces / extends | Notes |
|---|---|---|
| `ProbabilisticHitResolver` | `HitGrid` lookup + `DynamicHitResolver` 1D shift inside `SmartTouchResolver` | The power-diagram argmin. Pure function, unit-testable. |
| `LanguagePrior` | `BigramEngine` (kept as fallback) | Adds a bundled char **trigram/PPM** table; emits per-key `P(k|c)`. |
| `WeightSmoother` | (new) | Owns EMA, deadband, displacement clamp, page/lang reset. Runs off the touch path (hook into `rebakeBlendedWeights()` in `ProbabilisticTouchContext`). |
| `TouchOffsetModel` | `predictivePrior` slot in `ProbabilisticTouchContext` | Confidence-gated, clustered, layout-hash-keyed, App-Group persisted. |
| `VoronoiDebugLayer` | the red-border `KeyHitView` debug overlay | Real cells + heatmap + HUD. |
| `TypingTelemetry` | (new) | Shadow-mode counterfactual log, privacy-safe aggregates, replay export. |

**Invariants preserved:** visible `KeyFrame.rect` never changes; `KeyHitView` tiling stays (it forwards
touches; the dynamic decision happens inside `findKey`); commit-on-touch-down; CALayer instant highlight;
non-QWERTY/secure/symbol safety.

---

## 6. Dynamic Voronoi Engine Design

**Representation.** Per character key `k`: site `c_k = rect.center + offset_k` (offset in σ-normalized
fractional units), weight `w_k`. Non-character keys (shift/space/return/mode/snippet): `w_k = 0`, no
offset, no prior — purely geometric cells. This makes the engine a strict generalization of today's
nearest-rect behavior.

**Resolution (touch-down only).**
```
t'  = ((t.x − Cx)/σx , (t.y − Cy)/σy)            // Σ-normalize once
k*  = argmin over character keys of  ‖t' − c_k′‖² − w_k
```
~30 iterations, branchless inner loop, float32 centers in one cache line. ~150 ns; called once per
`touchesBegan`, **never** in `touchesMoved` (commit-touch lock — reuses existing 12 pt slide hysteresis).

**Anchor-zone guard (overcorrection safety).** After the argmin, if the chosen key's center is farther
than `anchorRadius` from the touch (an implausibly large cell swallowed a distant touch), fall back to
nearest-center. Equivalently, pre-check: if `t` lies inside key K's central anchor rect (≈ inner 50%×60%
of `rect`), return K immediately regardless of prior. This subsumes the current `minWidthRatio=0.60` clamp
and the Gunawardana anchored-key result.

**Visual stability / no jitter — the five guarantees:**
1. **Keys never move.** Only `w_k` and `offset_k` change; both feed touch resolution only, never `rect`.
2. **Commit-touch lock.** Decision is taken at touch-down and pinned for the press.
3. **EMA weight smoothing** (`α≈0.3–0.5`) off the hot path — no sudden partition jumps between keys.
4. **Deadband.** Skip a weight republish unless `max_k |Δw_k|` exceeds a threshold.
5. **Per-update displacement clamp.** Clamp each `Δw_k` so no decision boundary moves more than ~12% of a
   key width in a single update — protects expert muscle memory (validator R8).

**Power (not multiplicative) Voronoi** so cells stay convex (intersection of half-planes), which keeps the
argmin exact, the debug overlay legible, and behavior predictable.

**Page/context gates:**
- **Symbols/numbers/emoji pages:** `β = 0` → degrades to plain Σ-Voronoi + anchor zones; no offset learning.
- **Secure / URL / email / code fields** (`isSecureTextEntry`, `keyboardType`, `textContentType`): `β = 0`
  and offset learning frozen — never silently change deliberate characters.
- **Language switch / page change:** reset EMA weights to uniform; reselect the language's prior table or
  fall back to anchor-only for unsupported languages.

---

## 7. Bayesian Prediction System Design

**Posterior.** `log P(k|t,c) = −‖t'−c_k′‖²/2 + β·log P(k|c) + const`, `β = 2σ²λ` (one calibrated scalar).

**Touch likelihood.** Shared anisotropic Gaussian `Σ = diag(σx², σy²)`, `σy > σx`, applied as a coordinate
pre-transform. Fixed **population** parameters (not per-key, not per-user) — keeps the model identifiable
and the boundaries straight/convex. σx, σy estimated from the touch corpus (§10).

**Language prior `P(k|c)` — staged:**
- **Stage 1 (ship first):** keep the existing `BigramEngine` (26×26) but route it through the new
  `w_k = β·clip(log P)` weight path. Pure refactor of how the prior is *consumed*.
- **Stage 2:** add a bundled **character trigram** (26³ ≈ 17.6 k entries, ~70 KB float32) with bigram
  backoff; within-word context uses the last two characters. Optionally PPM order-3/4 for graceful backoff.
- **Stage 3 (optional):** at word boundaries, seed `P(first_char | word_context)` from a small bundled word
  unigram/bigram table — **replacing the UITextChecker round-trip on the prior path** (UITextChecker stays
  for the visible suggestion bar only). All tables bundled, queried in-process (<1 µs), well under jetsam.
- **Numerical safety:** `clip(log P) ∈ [log(1/V), 0]`, V = keys on current page. Bounds weights to
  `[−β·log V, 0]`.
- **Dynamic λ (optional):** scale β down when the prior is high-entropy (ambiguous, e.g., first char of a
  word) and up when confident — prevents correction when context says nothing.

**What it does and doesn't do.** It changes **which key a near-boundary touch-down selects** (≈ 1 in 5–6
keystrokes land within a key-width of a boundary). It does **not** rewrite already-committed text. No
autocorrect-style word replacement in V2.

---

## 8. Touch-Offset Model (per-region / per-user)

**Hierarchy:** `offset_k = population_prior(row, lateral) + user_delta(cluster_k)`.

**Population prior (zero-learning, ship immediately):** users land above center, bias growing top→bottom
rows; lateral bias by hand. Encode as **fractions of key height/width** (e.g., small upward fraction on
home row, larger on the top row), validated on the corpus — never hardcoded pixels.

**Clusters:** 6 groups = 3 row-bands (top/home/bottom) × 2 lateral zones (left third / right two-thirds).
Interpretable, maps to the documented offset structure, and avoids per-key overfit. `<50` samples per
cluster ⇒ population prior only; 50–200 ⇒ blend; `>200` ⇒ user delta dominates.

**Handedness:** inferred from the **touch-X distribution** (one thumb = narrow/biased X; two thumbs =
bimodal). Requires ≥50 touches before committing an estimate; neutral until then. No CoreMotion.

**Ground-truth gating (CRITICAL — prevents the self-confirming error loop):** update a cluster's EMA with
`(touch − center)` **only when** the committed key's trigram probability is in the top decile **and** no
backspace follows within 500 ms. Divergence guard: if a learned offset exceeds a cap (fraction of key
size), freeze updates and reset that cluster to the population prior (log it in DEBUG).

**Persistence:** offsets stored as fractional units, **keyed by a layout hash** {keyboardType,
orientation, frame.size}. Writes are **batched** (in-memory accumulator → flush on `viewWillDisappear` or
every ~50 keystrokes). **Never write to App Group from the touch handler** (mirrors the read we already
removed).

---

## 9. Rendering & Performance Strategy

**Hot path (synchronous, main, in `touchesBegan`, must finish < 8 ms / ideally < 1 ms):** Σ-normalize →
argmin → anchor guard → commit → CALayer highlight via `CATransaction(disableActions:)` → (Full-Access)
haptic. No `DispatchQueue.main.async` around the highlight (a hop costs a frame).

**Off the hot path (per committed keystroke):** recompute `P(k|c)`, EMA-smooth/clamp weights, publish a
snapshot consumed by the next touch-down; offset-model EMA update; telemetry. Recompute regions **per
keystroke, not per frame**.

**Separation rule:** region recompute (per keystroke) ≠ debug draw (per frame). The debug layer reads an
atomic snapshot via a dirty flag.

**ProMotion:** add `CADisableMinimumFrameDurationOnPhone = YES` to the extension Info.plist and set
`preferredFrameRateRange` on any `CADisplayLink`. **Validate empirically inside the extension** (the
host-provided surface may not honor it — validator Risk 8).

**Memory:** all LM tables bundled and small; assert extension dirty memory stays well under the
~30–40 MB ceiling (CI gate, §10). Check `os_proc_available_memory()` before loading optional tables;
`didReceiveMemoryWarning` purges caches; graceful fallback to bigram/anchor-only.

**Trait safety:** keep the existing explicit `isDark`-indexed colors for `CATextLayer`/`CAShapeLayer`;
update them in `traitCollectionDidChange` under `disableActions` (the dynamic-color/CATextLayer trap).

**Correctness pre-reqs (cheap, high-certainty — do first):** left-edge `UIScreenEdgePanGestureRecognizer`
fix; audit that *every* commit path is touch-down (accent/space excepted by design); ProMotion plist;
trait-color refresh.

---

## 10. Debug Tooling Specification

A single `VoronoiDebugLayer` (gated by `#if DEBUG` **and** `AppGroupSettings.debugHitOverlayEnabled`),
replacing today's red-border overlay. Driven by a `CADisplayLink` that redraws **only** when a dirty flag
is set (≈ 0 GPU in steady state). Visualizes, per the brief:

- **Live Voronoi cells** — power-diagram boundaries as `CAShapeLayer` polygons (convex ⇒ clean).
- **Touch points** — current/recent touch-down dots in normalized space.
- **Predicted key probabilities** — per-cell `P(k|c)` label and/or **heatmap** fill (cell color ∝ weight).
- **Dynamic expansion/shrink** — cells animate (off-hot-path) as weights breathe; show the per-update
  displacement clamp visually.
- **Touch-correction decisions** — when argmin ≠ nearest-center, draw an arrow from touch → chosen key.
- **Bayesian confidence** — show `P(chosen|c)`, the runner-up, and the margin (posterior gap).
- **Typing heatmap** — accumulated touch density per key region (reveals learned offsets vs. centers).
- **Frame timing & latency HUD** — touch-down→highlight ms, argmin ns, frame time, EMA update count,
  shadow disagreement rate, current `β`, handedness estimate, active layout hash.

Toggles: cells / heatmap / arrows / HUD / offset-overlay independently. Export current session telemetry
to the host app for the replay harness.

---

## 11. Instrumentation & Metrics Plan

**Privacy-safe, on-device only.** Never log raw coordinates, characters, or text. Log normalized
in-cell position (`Δx/keyW, Δy/keyH`), anonymous key indices, layout hash, hashed session id. Aggregate to
a 3×3 region grid before anything leaves memory. Ring buffer (≤ 10 k events ≈ 1 MB), flushed to App Group
on `viewWillDisappear`; export only via the host app's debug screen.

**Offline replay harness (host app).** Re-runs recorded touch-down logs through configurable resolvers
(`old` = HitGrid+1D, `new` = power-diagram) to A/B **without retyping**. CI snapshot test on a fixed
corpus.

**Key metrics & targets:**

| Metric | Definition | Target |
|---|---|---|
| KSPC | keystrokes (incl. backspace) / final chars | ≤ 1.05 |
| Resolver disagreement | % touches new ≠ old at uniform prior | baseline; must be conservative |
| Hit-region flip rate | % EMA updates that flip the argmin at a neighbor's centroid | < 2% / session |
| Touch-down→highlight | UITouch.began → visible commit | < 16 ms (60 Hz), < 8 ms (120 Hz) |
| Boundary displacement / update | max boundary move per EMA step | < 12% key width |
| KSPC Δ vs. baseline | on labeled ambiguous-touch corpus | strictly ≥ 0 |
| WPM | MacKenzie–Soukoreff 500-phrase set | no regression vs. current |

**Labeled corpus without autocorrect:** (1) unambiguous touches (≥40% key-width from 2nd-nearest center)
→ clean labels; (2) backspace-retype-at-same-position pairs → adversarial labels; (3) one ~30-min manual
annotation session of the MacKenzie–Soukoreff set for ~200–400 boundary touches to calibrate `β`.

**Synthetic suite:** "the the the" boundary stress; deliberate "zxq" rare-char (β must not suppress);
"asdfasdf" fast-alternation (displacement clamp holds); corner keys (anchor guarantees); rotation
mid-session (fractional offsets survive); "123!@#" symbols (β=0, no prior interference).

**CI gates:** golden-file snapshot diff on 1 k touches; latency gate (median < 8 ms, p99 < 16 ms on an
A12-class target); memory gate (extension dirty < 25 MB after loading tables); the λ=0/offset=0
**equivalence test** (new resolver must match nearest-center exactly with no prior/offset).

---

## 12. Rollout & Experimentation Strategy

1. **Tier 0 correctness fixes** ship independently behind no flag (pure bug fixes).
2. **Shadow mode.** The new power-diagram resolver runs in parallel on a background queue; the **old
   resolver still commits**. Log only disagreements (privacy-safe). Goal: characterize how often and where
   `new ≠ old` before it ever affects a user.
3. **Gating thresholds to flip new → acting:** shadow disagreement < 3%; KSPC(new) ≤ KSPC(old) on the
   labeled corpus; hit-region flip < 2%/session; zero synthetic-suite regressions; latency + memory CI
   green.
4. **Staged enablement** behind `AppGroupSettings` flags, each defaulting off until its gate passes:
   `useProbabilisticHitResolver` → `useTouchOffsetCorrection` → `useTrigramPrior`. Each is independently
   reversible (the current resolver remains the fallback path).
5. **Kill-switch & fallback:** any divergence guard trip, memory pressure, or unsupported
   language/secure-field context falls back to anchor-only / nearest-center. The new engine is a strict
   superset of current behavior at β=0/offset=0, so fallback is always safe.

---

## 13. Prioritized Implementation Roadmap

Effort = rough size; Impact = expected effect on real typing quality.

| Tier | Item | Impact | Effort | Notes / files |
|---|---|---|---|---|
| **0** | Left-edge `UIScreenEdgePanGestureRecognizer` fix | High (correctness) | XS | `KeyboardViewController` — real-device left-column bug |
| **0** | Commit-on-touch-down audit (all paths) | Med (confirm) | XS | reuse existing; verify no touch-up commits crept in |
| **0** | `CADisableMinimumFrameDurationOnPhone` + validate in-extension | Med | XS | Info.plist; empirically confirm |
| **0** | CATextLayer/CAShapeLayer trait-color refresh | Med (correctness) | XS | `traitCollectionDidChange`, `KeyLayerRenderer` |
| **1** | `ProbabilisticHitResolver` (Σ-normalize + power-diagram argmin + anchor guard) behind flag; **equivalence test** at β=0/offset=0 | **High** | M | replaces `HitGrid`/`DynamicHitResolver` seam in `SmartTouchResolver`/`findKey` |
| **1** | `WeightSmoother` (EMA + deadband + displacement clamp + page/lang reset) off hot path | High | M | hook `ProbabilisticTouchContext.rebakeBlendedWeights()` |
| **1** | Single calibrated `β`; log-prob clip; symbols/secure gates (β=0) | High (safety) | S | |
| **2** | Population-prior offsets (fractional, per row/lateral) | **High** | S | zero-learning; immediate accuracy |
| **2** | `TouchOffsetModel` online (confidence-gated EMA, 6 clusters, layout-hash keyed, batched App-Group, divergence guard) | High | L | the top production lever; the riskiest loop |
| **2** | Handedness from touch-X distribution | Med | M | no CoreMotion |
| **3** | Char **trigram/PPM** prior + bigram backoff (bundled) | Med–High | M | within-word depth without XPC |
| **3** | Word-boundary prior seeding (replace UITextChecker on prior path) | Med | M | UITextChecker stays for suggestion bar |
| **4** | `VoronoiDebugLayer` (cells, heatmap, arrows, HUD) + `TypingTelemetry` shadow log + replay harness + CI gates | High (enables tuning) | L | build alongside Tier 1 so Tier 1 is measurable |
| **5** | Full-Access haptics (prepare-once, burst-throttle, Low-Power honor) | Low–Med | S | gated; silent no-op without Full Access |
| **5** | Dynamic λ by prior entropy | Low–Med | S | after trigram |
| **5** | Sequence decoding / retroactive autocorrect | (future) | XL | out of scope this phase |

**Suggested execution order:** Tier 0 (independent) → Tier 4 telemetry+debug scaffold (so everything after
is measurable) → Tier 1 engine in **shadow mode** → validate gates → enable Tier 1 → Tier 2 population
offsets, then online offsets → Tier 3 trigram → Tier 5 polish.

---

## 14. Open Questions to Resolve Before Coding

1. Calibrate `β`, `σx/σy`, `α`, anchor radius, displacement clamp on the §11 corpus — these are empirical,
   not guessable.
2. Confirm `CADisableMinimumFrameDurationOnPhone` actually raises the extension's effective frame rate
   (host-surface dependency).
3. Decide trigram coverage: English-only first, or bundle the top N languages (each ~70 KB) and gate by
   `primaryLanguage`.
4. Confirm Full-Access status assumptions for haptics in the current entitlements.
5. Confirm the offset divergence-guard caps and the confidence-decile threshold against real corpus stats.

---

## 15. Optional Future Work — Data-Driven Tuning (NOT yet implemented)

> Recorded here as a deliberate, optional follow-up. The engine ships with conservative,
> research-shaped defaults that already feel good; this step would *refine* those numbers from real
> typing data. It changes constants only — **no performance or size impact**, and it is not required
> for the engine to work well.

**What it is.** Calibrate the engine's dials — `β` (language pull), `σx/σy` (touch scatter), the
offset learning rate/threshold, the anchor size, and the dynamic-λ confidence mapping — against a real
typing corpus instead of literature averages.

**How to do it when wanted (the tooling already exists):**
1. Enable **Settings → Experimental → Shadow-Mode Logging** and type normally for a while (ideally on a
   real device, since simulator clicks aren't representative thumb input).
2. Open **Settings → Experimental → Shadow Telemetry Report** and read:
   - the **disagreement rate** (is the engine too aggressive `>~3%` or too timid?), and
   - the **mean in-cell touch landing** (confirms the offset direction/magnitude — i.e. whether to give
     `PopulationOffset` a non-zero scale and which sign).
3. Adjust `ProbabilisticHitResolver.Config.default` (β, σ) and, if a clear population bias shows,
   `PopulationOffset.scale`/fractions; optionally tune `TouchOffsetModel` (`alpha`, `learnThreshold`)
   and the confidence mapping in `ProbabilisticTouchContext`.
4. Re-run shadow mode to confirm the disagreement rate and subjective feel improved; gate per §12.

**Adjacent optional items (also deferred, also no perf/size cost to typing):**
- **Full corpus-trained trigram / character LM** — replace the curated `TrigramEngine` boosts with a
  real table generated offline from an English corpus (still small, ~tens of KB), and optionally per
  major language gated by `primaryLanguage`.
- **Population fixed offsets** — give `PopulationOffset` a calibrated non-zero scale so brand-new users
  get offset correction before per-user learning converges.
- **Per-update boundary displacement clamp** — an extra jitter bound on top of the EMA smoothing, only
  worth adding if fast-typist testing ever shows boundary drift.

None of the above are needed for the current shipping experience; they are pure refinements.

---

*Companion docs: [`V2_KEYBOARD_ARCHITECTURE.md`](./V2_KEYBOARD_ARCHITECTURE.md) (current system),
`KEYBOARD_PERF_PLAN.md`, `PROBABILISTIC_TOUCH_PLAN.md` (prior work this builds on).*

### Primary citations
Buschek, "A Look Inside the Bayesian Keyboard" (Towards Data Science) · Buschek, "What if GUI elements were
not limited to boxes" (UX Collective) + ProbUI (CHI 2017) · Goodman et al., "Language Modeling for Soft
Keyboards" (IUI 2002) · Gunawardana, Paek & Meek, "Usability-Guided Key-Target Resizing" (IUI 2010) · Bi &
Zhai, "Bayesian Touch" (UIST 2013) + FFitts (CHI 2013) · Sivek & Riley, "Spatial Model Personalization in
Gboard" (MobileHCI 2022) · Yin et al., "Making Touchscreen Keyboards Adaptive…" (CHI 2013) · Holz &
Baudisch, "Generalized Perceived Input Point Model" (CHI 2010) · Azenkot & Zhai, "Touch Behavior with
Different Postures…" (MobileHCI 2012) · Goel et al., ContextType (CHI 2013) · Wigdor/Deber/Ng latency
studies (CHI 2013/2015) · Grossman & Balakrishnan, "Bubble Cursor" (CHI 2005) · Cheung et al., "Additive
Voronoi Cursor" (INTERACT 2019) · Aurenhammer, "Power Diagrams" (1987) · Apple WWDC 2015 #233; Apple HIG;
US Patents 8,232,973 / 9,459,775.
