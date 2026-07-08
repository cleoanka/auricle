# Auricle — UI/UX Specification v1.0

Menu-bar audio control app for macOS. SwiftUI `MenuBarExtra` with `.menuBarExtraStyle(.window)`. Minimum target: **macOS 14.4**. SF Symbols only. No third-party dependencies. This document is implementation-ready; all values are in points (pt) unless noted.

---

## 0. Design Principles

- **Native but premium.** Everything derives from system materials, system colors, and SF Pro. Premium comes from spacing discipline, restrained motion, and live meters — never from custom chrome.
- **One accent.** `Color.accentColor` (user's system accent) everywhere interactive. No brand color inside the popover.
- **Density like Control Center, hierarchy like Settings.** Section headers are quiet; controls are the loudest thing on screen.
- **Never block audio for UI.** All state changes are optimistic; errors surface inline on the affected row, never as modal alerts.

---

## 1. Global Tokens

### 1.1 Typography (system font only, dynamic type ignored — fixed sizes, this is a menu bar utility)

| Token | SwiftUI | Size / Weight | Usage |
|---|---|---|---|
| `type.sectionHeader` | `.system(size: 11, weight: .semibold)` + `.tracking(0.6)` + uppercase | 11 / semibold | "OUTPUT", "APPS", "INPUT" |
| `type.rowTitle` | `.system(size: 13, weight: .medium)` | 13 / medium | App names, device names |
| `type.rowSubtitle` | `.system(size: 11, weight: .regular)` | 11 / regular | Status lines ("Recently active", "Muted") |
| `type.value` | `.system(size: 11, weight: .medium).monospacedDigit()` | 11 / medium mono-digit | dB and % readouts |
| `type.bandLabel` | `.system(size: 9, weight: .medium).monospacedDigit()` | 9 / medium | EQ frequency labels |
| `type.banner` | `.system(size: 12, weight: .regular)` | 12 / regular | Permission banner copy |
| `type.bannerTitle` | `.system(size: 12, weight: .semibold)` | 12 / semibold | Permission banner title |
| `type.footer` | `.system(size: 11, weight: .regular)` | 11 / regular | Version string |
| `type.menuItem` | `.system(size: 13, weight: .regular)` | 13 / regular | Menus, pickers |

### 1.2 Color tokens (all semantic — light/dark for free)

| Token | Value |
|---|---|
| `color.textPrimary` | `.primary` |
| `color.textSecondary` | `.secondary` |
| `color.textTertiary` | `Color(nsColor: .tertiaryLabelColor)` |
| `color.accent` | `Color.accentColor` |
| `color.meterFill` | `Color.accentColor` at 100% up to −12 dBFS segment; top segment `Color(nsColor: .systemYellow)` above −12, `Color(nsColor: .systemRed)` above −3 |
| `color.meterTrack` | `Color.primary.opacity(0.08)` |
| `color.warning` | `Color(nsColor: .systemYellow)` |
| `color.error` | `Color(nsColor: .systemRed)` |
| `color.rowHover` | `Color.primary.opacity(0.06)` |
| `color.rowPressed` | `Color.primary.opacity(0.10)` |
| `color.separator` | `Color(nsColor: .separatorColor)` |
| `color.eqDrawerBG` | `Color.primary.opacity(0.04)` (a subtle inset well on top of the popover material) |
| `color.boostTint` | `Color(nsColor: .systemOrange)` — Boost sliders only, signals "hot" range |

### 1.3 Materials

- **Popover root background:** none added — the `.window` MenuBarExtra already provides the system popover material. Do **not** stack another material behind the whole popover.
- **Inset wells (EQ drawer, permission banner):** `RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color.eqDrawerBG)` — opacity fill, not Material, so it reads as inset rather than floating.
- **Permission banner:** same well + `strokeBorder(color.warning.opacity(0.35), lineWidth: 1)`.
- All rounded rects use `style: .continuous`.

### 1.4 Spacing scale

`2, 4, 6, 8, 10, 12, 16, 20`. Popover horizontal content inset: **12** on both sides everywhere. Corner radius scale: controls 5, rows 6, wells/drawers 8.

---

## 2. Popover Layout Tree

Width fixed **380**. Height is content-driven; cap with `.frame(maxHeight: 640)` and make only the APPS list scrollable (`ScrollView` around apps only) when overflow occurs.

```
MenuBarExtra window (380 × auto, max 640)
└─ VStack(spacing: 0)
   ├─ [PermissionBanner]            — only when permission missing; 12pt outer margins
   ├─ SectionHeader "OUTPUT"        — padding: top 14, leading 12, bottom 6
   ├─ OutputDeviceRow               — height 36, h-padding 12
   ├─ MasterVolumeRow               — height 44, h-padding 12
   ├─ MasterChainDisclosureRow      — height 28, h-padding 12
   │   └─ [MasterChainDrawer]       — expands: Boost row (36) + EQPanel (see §5)
   ├─ Divider                       — h-padding 12, top 10, bottom 0
   ├─ SectionHeader "APPS"          — padding: top 12, leading 12, bottom 6
   ├─ ScrollView (max 5.5 rows visible)
   │   └─ VStack(spacing: 2)
   │       ├─ AppRow ×N             — height 52 collapsed; + EQ drawer when expanded
   │       └─ [EmptyState]          — when N == 0; height 96
   ├─ Divider                       — h-padding 12, top 10
   ├─ SectionHeader "INPUT"         — padding: top 12, leading 12, bottom 6
   ├─ InputRow                      — height 36, h-padding 12
   ├─ Divider                       — full-bleed, top 12
   └─ FooterBar                     — height 40, h-padding 12
```

Section headers: `type.sectionHeader`, `color.textSecondary`, leading-aligned.

---

## 3. OUTPUT Section

### 3.1 OutputDeviceRow (height 36)

```
HStack(spacing: 8)
├─ Image(systemName: transportIcon)   16×16, .secondary, frame 20×20
├─ Menu { devices } label:
│   HStack(spacing: 4)
│   ├─ Text(deviceName)  type.rowTitle, .primary, lineLimit(1), truncationMode(.tail)
│   └─ Image(systemName: "chevron.up.chevron.down")  size 9, .tertiary
└─ Spacer
```

- Implement as borderless `Menu` (`.menuStyle(.borderlessButton)` equivalent: `Menu` with `.buttonStyle(.plain)` label). Whole row is the hit target; hover shows `color.rowHover` rounded-6 background with 2pt inset.
- Menu items: device name + trailing checkmark on current (`Menu`/`Picker` with `.pickerStyle(.inline)` inside the Menu gives the checkmark for free). Each item gets a leading transport icon.

**Transport-type SF Symbols** (used everywhere a device appears — output picker, input picker, per-app routing submenu):

| Transport | Symbol |
|---|---|
| Built-in speakers | `laptopcomputer` (or `speaker.wave.2` for desktop built-in) |
| Built-in / wired headphones | `headphones` |
| Bluetooth | `wave.3.right.circle` — fallback: `headphones` for BT headphones class |
| USB | `cable.connector` |
| HDMI / DisplayPort | `tv` |
| AirPlay | `airplay.audio` |
| Aggregate/Virtual | `square.stack.3d.down.right` |
| Unknown | `speaker.wave.2` |

### 3.2 MasterVolumeRow (height 44)

```
HStack(spacing: 10)
├─ MuteButton        28×28
├─ Slider            flexible width
└─ Text("67%")       type.value, .secondary, frame(width: 34, alignment: .trailing)
```

- **MuteButton:** `Button` plain style, 28×28 hit area, icon 15pt. Symbol: variable by level — `speaker.slash.fill` when muted (tint `color.error` at 80% opacity... no: keep it `.secondary` when muted is *not* an error; use `.primary` when muted to draw the eye, `.secondary` otherwise). Final rule: unmuted → `speaker.wave.3.fill` with `.symbolVariant(.none)` and level-driven variants (`speaker.fill`, `speaker.wave.1.fill`, `speaker.wave.2.fill`, `speaker.wave.3.fill` at 0 / ≤33 / ≤66 / >66%), color `.secondary`; muted → `speaker.slash.fill`, color `.primary`. Hover: `color.rowHover` circle behind. Pressed: `color.rowPressed`. Toggle animates with `.symbolEffect(.bounce, value: isMuted)` (macOS 14 OK).
- **Slider:** stock SwiftUI `Slider(value: 0...1)`. This is the one "big" control: give the row 44 height so the thumb breathes. Continuous updates throttled to 30 Hz toward CoreAudio.
- **Scroll wheel:** wrap row in an `NSViewRepresentable` scroll-event catcher (or `onContinuousHover` + local event monitor for `.scrollWheel` while hovered). Each wheel tick: ±2% (±6% with Option? No — Option = fine ±1%, Shift = coarse ±6%). Clamp 0–100. While scrolling, show the % readout in `.primary` for 800 ms, then fade back to `.secondary` over 200 ms ease-out.
- When muted: slider `.disabled(true)` at 40% opacity, % text replaced by "Muted" in `type.rowSubtitle` `.tertiary`.

### 3.3 MasterChainDisclosureRow (height 28)

```
Button (plain, full-width)
└─ HStack(spacing: 6)
   ├─ Image("chevron.right") 9pt .secondary — rotates 90° when expanded
   ├─ Text("Master Effects")  type.rowSubtitle weight .medium, .secondary
   ├─ [ActiveDot]  5×5 circle, color.accent — shown when Boost ≠ 0 dB OR master EQ enabled
   └─ Spacer
```

Chevron rotation and drawer expand share the spring in §8.

### 3.4 MasterChainDrawer (expanded content)

```
VStack(spacing: 0)  — inside a rounded-8 well (color.eqDrawerBG), margins: h 12, top 4, bottom 8; inner padding 10
├─ BoostRow  height 32
│   HStack(spacing: 10)
│   ├─ Text("Boost") type.rowSubtitle .medium, .primary, frame(width 44, leading)
│   ├─ Slider 0...12, tint color.boostTint
│   └─ Text("+0 dB") type.value, frame(width 44, trailing) — .secondary at 0, color.boostTint when > 0
├─ Divider  opacity 0.5, v-padding 8
└─ EQPanel (shared component, §5) bound to master EQ
```

Boost slider: default 0, step free, double-click the value label resets to 0 (animate value with `.spring(duration: 0.25)`).

---

## 4. APPS Section

### 4.1 AppRow anatomy (height 52 collapsed)

```
VStack(spacing: 0)
├─ HStack(spacing: 10)  — h-padding 10 inside the row, row itself inset 8 from popover edges? No: rows span h-padding 8 from edges with internal padding 8.
│   ├─ AppIcon        26×26  (NSRunningApplication.icon → Image(nsImage:), .interpolation(.high))
│   ├─ VStack(alignment: .leading, spacing: 2)
│   │   ├─ HStack(spacing: 6)
│   │   │   ├─ Text(appName)  type.rowTitle, lineLimit(1), .truncationMode(.tail), max width via layout priority
│   │   │   └─ [StereoMeter]  width 44, height 8  — only when managed & running
│   │   └─ HStack(spacing: 8)
│   │       ├─ VolumeSlider  .controlSize(.mini), flexible
│   │       └─ Text("80%") type.value .tertiary, width 30 trailing
│   ├─ MuteButton     22×22, icon 12pt (same rules as master mute)
│   └─ OverflowButton 22×22, "ellipsis.circle" 14pt .secondary
└─ [InlineEQDrawer]   — per-app EQPanel when expanded (§5), inside same row card
```

Row background: `RoundedRectangle(8)`; default clear; hover `color.rowHover`; when EQ drawer expanded, persistent `color.eqDrawerBG`.

### 4.2 StereoMeter (44 × 8)

- Two horizontal bars 44 × 3, spacing 2 (L on top, R below). Track `color.meterTrack`, fill leading-anchored, per-channel.
- Fill color segments (by dBFS mapped to 0–44 pt linearly over −60…0 dB): accent up to −12, yellow −12…−3, red −3…0. Implement as a single `Canvas`/`GeometryReader` bar with a gradient mask only over the lit portion — simpler: three stacked capsule segments clipped to fill width.
- **Smoothing:** attack instant (display max of frames since last tick), release exponential: `display = max(newPeak, display * pow(0.001, dt/0.35))` (≈ −60 dB decay over 350 ms). UI tick 30 Hz via `TimelineView(.animation(minimumInterval: 1/30))`. Never animate with SwiftUI implicit animations — draw directly from smoothed value.
- Peak-hold: 1.5-pt-wide tick at the 1 s max, fades over 600 ms. Optional; ship if cheap.

### 4.3 Row states (must read differently at a glance)

| State | Visual recipe |
|---|---|
| **Playing (managed)** | Icon 100% opacity; meter visible and moving; name `.primary` |
| **Recently active** (audio in last 5 min, silent now) | Icon 100%; meter hidden (reserve no space — name gets full width); subtitle absent; volume % `.tertiary`; name `.primary` |
| **Configured but silent** (has saved settings, not currently emitting; app may not be running) | Icon desaturated + 55% opacity (`.saturation(0)` NO — keep color, just `.opacity(0.55)`); name `.secondary`; slider enabled but at 70% opacity; sorts below the other two groups |
| **Muted (any state)** | Mute icon `speaker.slash.fill` `.primary`; slider disabled 40% opacity; % replaced by "Muted" `type.rowSubtitle` `.tertiary` |
| **Error (engine failed)** | Leading 16pt `exclamationmark.triangle.fill` in `color.warning` overlapping icon's trailing-bottom corner as 12pt badge; slider + meter hidden; in their place: `Text("Audio engine couldn't attach — click to retry")` `type.rowSubtitle` `color.warning`; whole subtitle is a button (retry); overflow menu still available with extra item "Copy Diagnostics" |

Sort order: playing (alphabetical) → recently active (most recent first) → configured-silent (alphabetical). Group changes animate with `.animation(.default, value: order)` — rows slide, 0.25 s.

### 4.4 Overflow menu (`ellipsis.circle`)

Standard `Menu`, items top to bottom:

1. **Output** ▸ submenu — "System Default" (checkmark when active), separator, each output device with transport icon + checkmark on active.
2. **Boost** ▸ submenu — slider is not native in Menu; instead 5 check-items: "Off (0 dB)", "+3 dB", "+6 dB", "+9 dB", "+12 dB". (Fine control lives in the EQ drawer's Boost row — mirror the master drawer's BoostRow at top of per-app EQ drawer.)
3. **Show Equalizer** — toggles inline EQ drawer; title becomes "Hide Equalizer" when open; shows checkmark when per-app EQ is *enabled* (independent of drawer visibility).
4. Separator
5. **Reset App Settings** — role `.destructive`? No: not destructive to data of consequence; plain item. Resets volume 100%, mute off, routing default, boost 0, EQ off/flat. Confirm nothing.
6. **Forget This App** — only for configured-silent rows; removes saved settings and the row.

### 4.5 Empty state (no apps)

Height 96, centered VStack(spacing: 6):
- `waveform.slash` 28pt `.quaternary` (`Color(nsColor: .quaternaryLabelColor)`)
- `Text("No apps are playing audio")` `type.rowTitle` `.secondary`
- `Text("Apps appear here when they start playing.")` `type.rowSubtitle` `.tertiary`

No button, no illustration. If permission is missing, the empty state is suppressed in favor of the banner explaining *why* it's empty (banner adds line: "Apps can't be listed until permission is granted.").

---

## 5. EQ PANEL (shared component)

One SwiftUI view `EQPanel(model:)` used by master drawer and per-app drawers. Total width when embedded: 380 − 12·2 (popover inset) − 10·2 (well padding) = **336**.

```
VStack(spacing: 8)
├─ HeaderRow  height 24
│   HStack(spacing: 8)
│   ├─ Toggle("")  .toggleStyle(.switch) .controlSize(.mini)   — EQ enable
│   ├─ Text("Equalizer") type.rowSubtitle .medium — .primary when enabled, .secondary when off
│   ├─ Spacer
│   ├─ PresetMenu  (see below)
│   └─ ResetButton "arrow.counterclockwise" 12pt, 20×20 hit, .secondary; hover .primary; disabled when already flat
├─ BandsRow  height 108
│   HStack(alignment: .bottom, spacing: 4)
│   ├─ PreampColumn (width 24)
│   │   ├─ VerticalSlider  height 84
│   │   └─ Text("Pre") type.bandLabel .tertiary, top-padding 4
│   ├─ Divider (vertical, height 84, opacity 0.5), h-margin 2
│   └─ 10 × BandColumn (width 24 each, fills remaining 336−24−1−4−spacing → spacing computed: use HStack spacing 4; 24·11 + divider ≈ 336 ✓)
│       ├─ VerticalSlider  height 84, range −12…+12
│       └─ Text(label)     type.bandLabel .tertiary
└─ (when disabled) entire BandsRow at 45% opacity + .allowsHitTesting(false)
```

- **Band labels** (10): `32`, `64`, `125`, `250`, `500`, `1k`, `2k`, `4k`, `8k`, `16k`. No "Hz" suffix — implied, saves width.
- **Vertical slider:** SwiftUI has no vertical slider on macOS 14 → custom control. Track: capsule 3 wide × 84 high, `color.meterTrack`. Fill: from vertical center (0 dB) toward thumb, `color.accent` (capsule 3 wide). Center detent: 1×7 hairline tick at mid-height, `color.separator`. Thumb: 12×12 circle, `Color(nsColor: .controlColor)` fill, shadow `black.opacity(0.25)` radius 1 y 0.5, hairline stroke `black.opacity(0.08)`. Hover: thumb scales to 1.15 (spring 0.2 s). Drag: vertical delta maps linearly; **snap to 0 dB within ±0.75 dB** while dragging (haptic-free; visual snap only). Option-drag disables snap. Double-click a band → that band to 0 (animated 0.2 s). Scroll wheel over a band: ±0.5 dB per tick.
- **Value feedback:** while dragging any band, show a transient value bubble? No — restrained: show value in the header, right of "Equalizer": `Text("1k  +4.5 dB")` `type.value` `.secondary`, appears while dragging, fades 300 ms after release.
- **Preamp:** identical slider, range −12…+12 dB, label "Pre". Auto-preamp is engineering's call; UI treats it as a normal band.
- **PresetMenu:** `Menu` with label `HStack{ Text(presetName) type.value .secondary; Image("chevron.up.chevron.down") 8pt .tertiary }`, max label width 110, truncate tail. Items: Flat, Bass Boost, Bass Reducer, Vocal, Treble Boost, Loudness, Electronic, Rock, Podcast — separator — user presets (alphabetical, each with a right-click-free "Delete" via submenu? No: user presets are plain items; deletion lives in Settings) — separator — "Save as…". Checkmark on active preset; when bands are hand-modified after choosing a preset, label shows "Custom" and no checkmark. "Save as…" opens an `alert` with `TextField` (macOS 14 supports TextField in alert): title "Save Preset", field placeholder "Preset Name", buttons Cancel / Save (Save disabled when empty; duplicate name → appends " 2").
- **Reset:** sets all bands + preamp to 0 and preset to Flat; bands animate to zero with a single spring (0.3 s, stagger 0 — simultaneous, restrained).

Fits check: header 24 + 8 + 108 = 140 panel height; master drawer total ≈ 32 + 17 + 140 + padding = ~200. Popover worst case remains under the 640 cap with scrolling apps list.

---

## 6. INPUT Section

### InputRow (height 36) — one compact line

```
HStack(spacing: 8)
├─ Image(systemName: "mic")  14pt .secondary, frame 18
├─ DevicePicker (Menu, same pattern as §3.1, transport icons) — flexible, min 90
├─ Slider (gain 0…1)  width 110 fixed
├─ Text("72%") type.value .secondary width 30
└─ MuteButton 22×22 — "mic.fill" / "mic.slash.fill", muted state tints icon color.error (input mute IS a privacy-relevant state; red is warranted here)
```

If the device name would collide, name truncates first (layoutPriority: slider 2, name 1). No input level meter in v1 (keeps the section honest to "compact"); leave 0 reserved space.

---

## 7. PERMISSION Banner

Shown at very top when System Audio Recording permission (TCC audio-capture) is missing. Margins 12/12/0/12 (L/R/bottom handled by section header's top padding? No — banner has bottom margin 4).

```
RoundedRectangle(8) fill color.eqDrawerBG, strokeBorder color.warning.opacity(0.35) 1pt
└─ HStack(alignment: .top, spacing: 10) padding 10
   ├─ Image("waveform.badge.exclamationmark") 18pt, color.warning
   ├─ VStack(alignment: .leading, spacing: 3)
   │   ├─ Text("Audio Capture Permission Needed") type.bannerTitle .primary
   │   ├─ Text("Auricle needs System Audio Recording permission to control per-app volume and show levels.") type.banner .secondary, fixedSize(horizontal: false, vertical: true)
   │   └─ Button("Open Privacy Settings…") .buttonStyle(.link) size 12 — opens
   │       x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture
   └─ (no dismiss X — banner disappears only when permission granted; re-check on popover open and on NSWorkspace didActivate)
```

While banner visible: APPS section still renders but rows show no meters and sliders are disabled at 40% with subtitle "Requires permission" `.tertiary` on hover tooltip (`.help(...)`). OUTPUT/INPUT device pickers and master volume remain fully functional (they don't need the permission).

---

## 8. FOOTER (height 40)

```
HStack(spacing: 8)
├─ SettingsButton  "gearshape" 13pt, 24×24, .secondary → .primary on hover — opens Settings window (below), then `NSApp.activate`
├─ Text("Auricle 1.0.0") type.footer .tertiary
├─ Spacer
└─ QuitButton  Text("Quit") type.footer .secondary + ⌘Q keyboardShortcut; hover underline-free, color → .primary; also plain "power" icon? No — text only, native.
```

Footer sits on a hairline `Divider` (full-bleed). No extra background.

### Settings window (standard `Settings` scene, 420 × auto, `.formStyle(.grouped)`)

Single pane, `Form`:
- Toggle "Launch at Login" → `SMAppService.mainApp`
- Toggle "Remember per-app settings" (footer text: "Volume, EQ, and routing are restored when an app returns.")
- Section "Presets": list of user EQ presets with delete (minus) buttons
- Section "About": app icon 64, name + version, `Link("Auricle on GitHub", destination:)` , copyright line `.footnote .secondary`

---

## 9. Motion Spec

| Interaction | Animation |
|---|---|
| Drawer expand/collapse (master chain, per-app EQ) | `.spring(response: 0.32, dampingFraction: 0.86)` on height; chevron rotation same spring; content inside fades in with `.opacity` over the last 60% of the expansion (`.transition(.opacity.combined(with: .move(edge: .top)))` clipped) |
| Row hover background | fade in 0.12 s ease-out, fade out 0.20 s ease-out |
| Mute toggle | `.symbolEffect(.bounce, value:)` + slider disable fade 0.15 s |
| Meter | no SwiftUI animation — 30 Hz redraw with exponential release τ = 350 ms attack-instant (§4.2) |
| Row reorder (state group change) | `.spring(response: 0.35, dampingFraction: 0.9)`; new rows `.transition(.opacity.combined(with: .scale(0.97, anchor: .top)))` |
| EQ reset-to-flat | single `.spring(response: 0.3, dampingFraction: 0.9)` on all band values simultaneously |
| Scroll-wheel volume readout emphasis | color to `.primary` instant, revert after 800 ms with 0.2 s ease-out |
| Banner appear/disappear | `.transition(.opacity.combined(with: .move(edge: .top)))`, 0.25 s |

Respect `accessibilityReduceMotion`: replace springs with 0.15 s linear opacity; meters keep updating (informational).

---

## 10. Truncation & Overflow Rules

- App and device names: `lineLimit(1)`, `.truncationMode(.tail)`, always add `.help(fullName)` tooltip when truncated.
- Layout priorities in AppRow: mute/overflow buttons fixed; meter fixed 44; name truncates before slider shrinks; slider min width 70.
- Device picker in OUTPUT: name max width = 380 − 12·2 − 20 − 8 − 13(chevron) → truncate tail.
- Preset menu label max 110, tail truncation.
- % / dB readouts: fixed-width frames (30–44) with `.monospacedDigit()` — never reflow while scrubbing.
- More than ~12 devices in a routing submenu: native Menu scrolls; do nothing special.

---

## 11. Menu Bar Icon

- **Template image** (monochrome, respects dark/light + "reduce transparency" automatically). Base: SF Symbol `waveform` at `.medium` weight, 16 pt point-size in an 18×18 template canvas — but give Auricle identity with a custom template PDF later; v1 ships the symbol.
- State variants: default `waveform`; master muted → `speaker.slash`; permission missing → `waveform.badge.exclamationmark` (badge inherits template color; acceptable).
- Set via `MenuBarExtra("Auricle", systemImage:)` with dynamic `systemImage` binding. No colored/animated menu bar icon — ever.

---

## 12. App Icon — Geometric Recipe (Python/PIL renderable)

Render at 1024×1024, then downscale set.

1. **Canvas** 1024×1024 transparent.
2. **Squircle background:** rounded rect inset 100 px on all sides (macOS icon grid), i.e. rect (100,100)–(924,924), corner radius = **0.225 × 824 ≈ 185 px**, `ImageDraw.rounded_rectangle` (true superellipse not needed at this radius ratio; 22.5% reads as the macOS squircle).
3. **Background gradient:** vertical linear, top `#1E2430` → bottom `#0C0F16` (deep slate, premium-neutral). Implement: draw gradient on full canvas, mask with squircle.
4. **Inner rim light:** stroke the same rounded rect, width 3 px, color `#FFFFFF` at 8% alpha, offset 0 (draws just inside the edge).
5. **Waveform bars** (the mark): 7 vertical capsules, centered horizontally as a group, baseline-centered vertically at y = 512.
   - Bar width **44 px**, gap **36 px** → group width 7·44 + 6·36 = 524 px; first bar left x = 512 − 262 = 250.
   - Heights (px, symmetric about y=512): `[180, 300, 460, 620, 460, 300, 180]` — a smooth arch.
   - Rounded caps: corner radius = 22 (half width) → capsules.
   - **Bar gradient:** each bar filled with vertical linear gradient top `#5AC8FA` → bottom `#7A5CFF` (cyan → violet; one gradient shared across the group, masked per-bar, so hue shifts with height).
6. **Center-bar accent:** the tallest (4th) bar gets a 1.0 alpha white overlay capsule inset 14 px at its top cap? No — restrained: skip. Instead add a subtle glow: duplicate the 4 middle bars, Gaussian blur radius 40, alpha 22%, composite *under* the bars.
7. **No text, no gloss, no border.** Export sizes: 16, 32, 64, 128, 256, 512, 1024 (@1x/@2x pairs). At 16–32 px the 7 bars merge acceptably; optionally re-render small sizes with 5 bars (`[300, 460, 620, 460, 300]`, width 56, gap 48) — recommended.

---

## 13. Accessibility & Misc

- Every custom control gets `accessibilityLabel` + `accessibilityValue` ("Master volume, 67 percent") and `accessibilityAdjustableAction` for sliders/meterless increments (±5%).
- Full keyboard: popover is focusable; Tab traverses rows; arrow keys adjust focused slider ±2% / ±0.5 dB; Space toggles mute/toggles.
- `controlActiveState` — when popover loses key, meters keep running (it's a monitoring surface); do not dim.
- All strings in a localizable table from day one; layouts already tolerate +30% string growth via truncation rules.
