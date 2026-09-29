# CHARAK Design System · V2

> **Care that reads at a glance.** One visual language for the Patient App and the
> Doctor App: calm surfaces, big headers you can read from across the room, and
> controls where your thumb already is.

This folder is the **single source of truth** for how CHARAK looks and moves. The
original board is [`CHARAK_Design_System_V2.pdf`](./CHARAK_Design_System_V2.pdf)
(11 pages: principles, colour, type, components, motion, three annotated
screens). Everything in the PDF is written down here and wired into code, so the
system can be rebuilt, extended or audited without the PDF.

V2 replaces the V1 direction ("Premium Banking": white + lake blue `#376CD5`,
Inter, hairlines, soft shadows). §13 lists what changed.

---

## Contents

1. [Where things live](#1-where-things-live)
2. [Principles](#2-principles)
3. [Colour](#3-colour)
4. [Typography](#4-typography)
5. [Shape, size & space](#5-shape-size--space)
6. [Layout: look up top, reach down low](#6-layout-look-up-top-reach-down-low)
7. [Components](#7-components)
8. [Motion](#8-motion)
9. [Screens](#9-screens)
10. [Brand](#10-brand)
11. [Using the system in code](#11-using-the-system-in-code)
12. [Changing the system](#12-changing-the-system)
13. [V1 → V2 migration map](#13-v1--v2-migration-map)
14. [Review checklist](#14-review-checklist)

---

## 1. Where things live

| Path | What it is | Edit by hand? |
|---|---|---|
| `design-system/tokens.json` | **Every raw value**: ramps, schemes, status colours, type scale, radii, sizes, spacing, motion | ✅ This is the only place values change |
| `design-system/tool/generate.py` | Turns `tokens.json` into the platform files below (Python 3.8+, stdlib only) | ✅ |
| `design-system/tool/fetch_fonts.sh` | Re-downloads the Anek variable fonts | ✅ |
| `design-system/CHARAK_Design_System_V2.pdf` | The original design board | ❌ reference |
| `design-system/assets/` | Brand mark PNGs (transparent), cut from PDF page 1 | ❌ |
| `design-system/screenshots/` | Golden renders of the component gallery, patient + doctor | ❌ regenerate |
| `packages/charak_core/lib/design/tokens.g.dart` | Generated Dart tokens | ❌ generated |
| `packages/charak_core/lib/design/tokens.dart` | Maps tokens onto the names screens use (`CharakColors`, `CharakText`, `CharakRadius` …) and picks the scheme | ✅ |
| `packages/charak_core/lib/design/theme.dart` | Material + shadcn themes built from the active scheme | ✅ |
| `packages/charak_core/lib/design/motion.dart` | Curves, transitions, press, stagger, live pulse | ✅ |
| `packages/charak_core/lib/components/` | All shared widgets (§7) | ✅ |
| `packages/charak_core/lib/gallery.dart` | Every component on one page (living reference) | ✅ |
| `packages/charak_core/test/gallery_golden_test.dart` | Renders the gallery to `design-system/screenshots/` | ✅ |
| `packages/charak_core/fonts/` | Anek Latin + Anek Devanagari variable TTFs (SIL OFL) | ❌ use `fetch_fonts.sh` |
| `packages/charak_core/assets/brand/` | Brand mark bundled with the Flutter package | ❌ |
| `admin/src/styles/charak-tokens.css` | Generated CSS variables for the admin console | ❌ generated |
| `admin/src/index.css`, `admin/tailwind.config.js` | Map the generated vars onto shadcn/Tailwind names | ✅ |
| `opendesign/design-systems/charak/colors_and_type.css` | Generated CSS variables for HTML mockups | ❌ generated |

---

## 2. Principles

The four rules on page 1 of the board. Every decision below follows from them.

1. **Look up top, reach down low.** A big title fills the top third, where you
   read. Actions (search, slots, Accept, Pay) sit in the lower two-thirds, within
   thumb reach. The title folds into a slim bar as you scroll.
2. **One family, three widths.** Anek goes *wide* for headers, *normal* for
   reading and *narrow* for fees and times. It is one typeface in two scripts,
   matching the Devanagari mark.
3. **Flat, tonal, rounded.** There are **no drop shadows**. White cards on a
   cream ground, grouped into big 26px blocks, provide the depth.
4. **Blue acts, Chandan welcomes.** Anything you tap is blue. Chandan appears in
   greetings, ratings, the wordmark and the "Requested" moment. It is **never**
   used for a button, so the two roles don't mix.

---

## 3. Colour

### 3.1 Ramps

Four hues with 10-step ramps. The **bold** value is the brand value of each ramp.

| Step | Charak Blue | Chandan | Sage | Ink |
|---|---|---|---|---|
| 50  | `#EEF3FD` | `#FDF8EF` | `#F3F4EC` | `#F4F5F7` |
| 100 | `#D9E4FA` | `#F7EAD4` | `#E3E6D4` | `#E6E8EC` |
| 200 | `#B3C8F4` | `#EDD2A6` | `#C8CDAE` | `#CDD1D8` |
| 300 | `#84A5EC` | `#DDB06A` | `#A9B087` | `#A6ADB8` |
| 400 | `#4F7CDD` | `#C88442` | `#8A9266` | `#7A8494` |
| 500 | **`#2456C9`** | **`#A85A26`** | **`#6F774F`** | `#566072` |
| 600 | `#1D45A6` | `#8E4B1F` | `#5C613F` | `#3C4556` |
| 700 | `#183885` | `#733C19` | `#4A4F33` | `#283142` |
| 800 | `#132B66` | `#572D13` | `#373B27` | `#182031` |
| 900 | `#0D1D45` | `#3B1E0C` | `#25281A` | **`#0E1726`** |

- **Charak Blue**: primary. Means trust, so it carries every action.
- **Chandan**: brand warmth, from the logo's copper wordmark and gold halo.
- **Sage**: health and success, from the logo's leaves.
- **Ink**: text, chrome and the whole doctor app.

In Flutter: `CharakPalette.blue500`, `CharakPalette.chandan300` … In CSS:
`var(--blue-500)`.

### 3.2 Surfaces: two schemes

The patient app is **light** (cream + white). The doctor app is **ink**. Same
screen code, different scheme; see §11.1.

| Role | Patient (light) | Doctor (ink) | Flutter |
|---|---|---|---|
| Ground (screen background) | `#F7F3EC` | `#0E1726` | `CharakColors.ground` |
| Card (cards, bars, sheets) | `#FFFFFF` | `#182031` | `CharakColors.card` (= `.bg`) |
| Tint (blue surface) | `#EEF3FD` | `#132B66` | `CharakColors.tint` |
| Warm (chandan surface) | `#FDF8EF` | `#3B1E0C` | `CharakColors.warm` |
| Fill (quiet fill inside cards) | `#F4F5F7` | `#283142` | `CharakColors.bgSubtle` |
| Text | `#0E1726` | `#F4F5F7` | `CharakColors.ink` |
| Text muted | `#566072` | `#A6ADB8` | `CharakColors.inkMuted` |
| Text faint (placeholder, disabled) | `#A6ADB8` | `#7A8494` | `CharakColors.inkFaint` |
| Line (dividers) | `#E6E8EC` | `#283142` | `CharakColors.border` |
| Line strong (outlines, inputs) | `#CDD1D8` | `#3C4556` | `CharakColors.borderStrong` |
| Primary / on primary | `#2456C9` / white | `#2456C9` / white | `.primary` / `.onPrimary` |
| Primary soft / text on it | `#EEF3FD` / `#183885` | `#132B66` / `#B3C8F4` | `.primarySoft` / `.primaryDeep` |
| Chandan accent | `#A85A26` | `#DDB06A` | `.chandan` |
| Greeting line | `#8E4B1F` | `#DDB06A` | `.greeting` |
| Danger / soft / text on soft | `#D23B3B` / `#FBE3E3` / `#A12A2A` | `#F07C7C` / `#3A1F24` / `#F4A5A5` | `.danger` / `.dangerSoft` / `.onDangerSoft` |

**Share of a typical patient screen:** cream ground 58%, white cards 24%, blue
10%, Chandan + Sage 5%, status 3%. Keep blue near 10% so it keeps meaning
"tap here".

### 3.3 Status

Every booking state owns **exactly one** colour. Chips use the soft fill with the
"on" ink; dots and icons use the solid.

| State | Solid | Patient soft / on | Doctor soft / on | Tone |
|---|---|---|---|---|
| Requested | `#C88442` | `#F7EAD4` / `#733C19` | `#3B1E0C` / `#EDD2A6` | `CharakStatusTone.requested` |
| Accepted | `#2456C9` | `#D9E4FA` / `#183885` | `#132B66` / `#B3C8F4` | `.accepted` (= `.primary`) |
| Paid · Confirmed | `#5E7F3A` | `#E6EEDC` / `#3F5A24` | `#25281A` / `#C8CDAE` | `.confirmed` (= `.success`) |
| Active visit | `#6B4FC9` | `#ECE7FA` / `#4A3499` | `#2A2152` / `#CFC3F5` | `.active` |
| Needs review | `#E07A1F` | `#FDEBD9` / `#9A4E0C` | `#3D2410` / `#F6C08F` | `.review` (= `.warning`) |
| Declined | `#D23B3B` | `#FBE3E3` / `#A12A2A` | `#3A1F24` / `#F4A5A5` | `.declined` (= `.danger`) |
| Neutral | ink-500 | `#F4F5F7` / `#3C4556` | `#283142` / `#CDD1D8` | `.muted` |

`charakStatusFor(status)` maps API status strings (`requested`, `accepted`,
`paid`, `in_progress`, `completed`, `declined`, `cancelled` …) to tone + label,
and `CharakStatusPill.forStatus(status)` renders it. Always pair colour with a
text label; colour alone is never the signal.

### 3.4 Specialty tiles

| Tile | Background | Ink |
|---|---|---|
| General | `#EEF3FD` | `#183885` |
| Paediatrics | `#FDF8EF` | `#733C19` |
| Cardiology | `#FBEAEA` | `#A12A2A` |
| Ayurveda / Physio | `#E3E6D4` | `#4A4F33` |
| Skin | `#ECE7FA` | `#4A3499` |
| Ortho | `#F4F5F7` | `#283142` |

---

## 4. Typography

**Anek** by Ek Type (Mumbai), a variable family with a **width axis from 75 to
125** and matching Devanagari (SIL OFL, free). Samsung pairs a wide display face
with a plain UI face; CHARAK gets both from one family, so the brand sounds the
same in English, Hindi and Marathi.

- Axes: `wdth 75–125`, `wght 100–800`.
- Files: `packages/charak_core/fonts/AnekLatin-Variable.ttf` (primary) and
  `AnekDevanagari-Variable.ttf` (fallback for Hindi/Marathi). Flutter family names
  are `packages/charak_core/Anek` and `packages/charak_core/AnekDevanagari`
  (`CharakType.family`, `CharakType.familyDevanagari`). The apps declare no fonts
  of their own.
- Web: Google Fonts `Anek Latin` + `Anek Devanagari` with the `wdth,wght` axes.

**The width axis is the identity:** Wide 125 for headers · Normal 100 for
reading · Narrow 75–80 for data.

| Token | Specimen | Size / line | Weight | Width | Flutter |
|---|---|---|---|---|---|
| display | Good morning | 56/60 | 750 | 125 | `CharakText.display` |
| title.large | Your bookings | 36/42 | 700 | 122 | `CharakText.titleLarge` |
| title.medium | Dr. Meera Kulkarni | 26/32 | 650 | 118 | `CharakText.titleMedium` |
| title.small | Available slots | 20/26 | 650 | 112 | `CharakText.titleSmall` |
| body.large | Describe what you are feeling | 18/26 | 400 | 100 | `CharakText.bodyLarge` |
| body | The doctor reviews your request and decides. | 16/24 | 400 | 100 | `CharakText.body` |
| label | Send request | 15/20 | 600 | 105 | `CharakText.label` |
| caption | Home visit · 4.2 km away | 13/18 | 500 | 100 | `CharakText.caption` |
| overline | UPCOMING | 12/16 | 700 | 110, +1.2 tracking, UPPERCASE | `CharakText.overline` |
| numeric | ₹650 · 10:30 AM · 4.8 | 20/24 | 600 | 80, tabular | `CharakText.numeric` |

Rules:

- **Numbers always use tabular figures** (`font-variant-numeric: tabular-nums`)
  and the narrow width, so fees and times line up in lists and countdowns never
  jitter. In Flutter: `style.tabular`.
- **Headers never go below width 118**, so the brand stays recognisable on small
  screens.
- Fractional weights (650, 750) ride on the `wght` axis. To change the weight of
  a title style use `style.weight(600)`, not `copyWith(fontWeight:)` (the axis
  value would win). `style.width(125)` sets the width.
- Styles carry **no colour**; they inherit the theme text colour, so they work
  on both schemes. Add colour with `.copyWith(color: CharakColors.inkMuted)`.
- Greeting screens scale `display` down to 44/48 on phones
  (`CharakScreenHeader(display: true)`).

---

## 5. Shape, size & space

| Token | Value | Use | Flutter |
|---|---|---|---|
| radius.pill | 999 | Every button, chip, segment, search bar, status chip | `CharakRadius.button` / `.pill` |
| radius.sheet | 32 | Top corners of bottom sheets | `CharakRadius.sheet` |
| radius.card | 26 | Cards, grouped-list blocks, hero | `CharakRadius.card` |
| radius.tile | 20 | Specialty tiles, day chips, inner blocks, banners | `CharakRadius.tile` |
| radius.field | 20 | Text fields | `CharakRadius.input` |
| radius.avatar | ⅓ of size | Rounded-square avatars | `CharakAvatar` |
| size.buttonMinHeight | 52 | Minimum button height | `CharakSizes.buttonMinHeight` |
| size.buttonCompact | 44 | Compact buttons in bars | `CharakSizes.buttonCompact` |
| size.chipHeight | 40 | Chips, slot pills | `CharakSizes.chipHeight` |
| size.touchMin | 44 | Smallest touch target | `CharakSizes.touchMin` |
| size.bottomBarHeight | 68 | Tab bar (plus safe area) | |
| size.navPill | 56×32 | Active-tab pill | |
| size.nowBarHeight | 60 (→ 140 expanded) | Now Bar | |

Spacing: `4 · 8 · 12 · 16 · 20 (gutter) · 24 · 32 · 48`. The screen gutter is
**20**. Cards are padded 20, and vertical rhythm between blocks is 24.

**Elevation: none.** Never add `BoxShadow`. Depth comes from tone (white on
cream, ink-800 on ink-900). Selected states use a 2px blue outline or a blue
fill, never a glow. Focus is a 2px blue outline.

---

## 6. Layout: look up top, reach down low

Every **tab-root screen** uses `CharakLargeTitleScaffold`:

```
┌───────────────────────────────┐
│ ░ slim frosted bar (appears)  │  ← 170–230 px of scroll: small title fades in
│                               │
│ Wednesday, 30 September       │  ← eyebrow (Chandan: greeting colour)
│ Good evening,                 │  ← display / title.large, wide
│ Aarav                         │
│ Riya's consult starts soon.   │  ← subtitle (muted, or greeting colour for counts)
├───────────────────────────────┤  ── top third: read
│ [ Search ……………………… 🎤 ]      │
│ ┌ blue hero: next booking ──┐ │
│ │ … 11:00 AM   [ Pay ₹800 ] │ │  ── lower two-thirds: act
│ └───────────────────────────┘ │
│ Find care            See all  │
│ [tile] [tile] [tile]          │
│ ( ● Now Bar · in 11:53     )  │  ← floats above the tab bar
├───────────────────────────────┤
│  (Home)  Bookings History Pro │  ← bottom bar, active pill
└───────────────────────────────┘
```

- **Pushed screens** use `CharakTopBar` (round back button, centred small title)
  and put the screen's question as a big `charakScreenTitleStyle`
  (title.large) at the top of the body.
- **Primary actions live at the bottom**: in `CharakCtaBar` (pinned, 26px top
  corners), in a card's lower half, or in the Now Bar. Never put the main action
  in the top bar.
- **Confirmations are sheets**, not centred dialogs (`showCharakConfirm`), so
  both answers are in thumb reach.

---

## 7. Components

All in `packages/charak_core/lib/components/`, exported from
`package:charak_core/charak_core.dart`. The gallery (`lib/gallery.dart`) shows
each one, and `design-system/screenshots/` has both schemes rendered.

| Board element | Widget | Notes |
|---|---|---|
| Button, primary | `CharakButton(label:, onPressed:)` | Blue pill, 52px. `null` onPressed = quiet grey ("wakes up" to blue when enabled). `isLoading` keeps colour, swallows taps |
| Button, tonal | `variant: CharakButtonVariant.tonal` | "Add family member" |
| Button, outline | `.outline` (or V1 `outlined: true`) | "Reschedule" |
| Button, ink | `.ink` | Decisive confirm next to a soft decline ("Accept"). Blue on the ink scheme |
| Button, danger | `.danger` / `CharakDestructiveButton` | Soft red "Decline", "Cancel" |
| Button, inverse | `.inverse` | White on a blue hero ("Pay ₹800") |
| Text button | `CharakGhostButton` | "View all", "See all" |
| Round icon button | `CharakIconButton`, `CharakRoundIconButton` | Video, call, back, bell |
| Chip | `CharakChip(label:, selected:, numeric:, disabled:)` | 40px pill. Off: outlined. On: blue. Disabled: struck through |
| Chip strip | `CharakChipRow` | Horizontal, no scrollbar |
| Segmented | `CharakSegmented` | Thumb **slides** (300ms), labels cross-fade |
| Status chip | `CharakStatusPill`, `.forStatus()` | Sentence case, soft fill, live dot for waiting |
| Badge | `CharakBadge` | Smaller status label |
| Rating | `CharakRatingChip`, `CharakStarRating` | Chandan, since ratings welcome |
| Search | `CharakSearchBar` | 56px pill, optional voice button |
| Text field | `CharakField` | Label **inside** the 20px box, 2px blue outline on focus. `CharakInput` is the shadcn-backed variant |
| Card | `CharakCard(tone:)` | `plain` / `tint` / `warm` / `hero` (solid blue). 26px, no border, no shadow. `onTap` adds the press |
| Grouped list | `CharakGroupedList` + `CharakListRow` | One UI settings block: overline label, rows in one 26px block, mark the last row `last: true` |
| Switch | `CharakSwitch` | 52×32, thumb slides 20px |
| Toggle card | `CharakToggleCard` | Settings row as its own card |
| Section header | `CharakSectionHeader` | "Find care ···· See all" |
| Section label | `CharakSectionTitle` | Overline above grouped content |
| Specialty tile | `CharakSpecialtyTile(toneIndex:)` | 20px tonal tile, icon top, name bottom |
| Avatar | `CharakAvatar` | Rounded square (⅓ radius), six ramp tones, `circle: true` for the account button |
| Doctor card | Composed: `CharakCard` + avatar + `CharakRatingChip` + hairline + tabular fee | See `directory_screen.dart` |
| Bottom bar | `CharakBottomBar` + `CharakNavItem` | Patient: white bar, blue-100 pill. Doctor: ink bar, solid blue pill. `badge:` count |
| Large title → app bar | `CharakLargeTitleScaffold` | §6 |
| Top bar | `CharakTopBar` | Pushed screens |
| Screen header | `CharakScreenHeader` | Eyebrow + big title + subtitle |
| Now Bar | `CharakNowBar` | Ink pill above the tab bar, rises after 600ms, tap to expand 60→140 |
| Heads-up | `showCharakHeadsUp()` | Blue banner drops from the top, "Later" / "Review" |
| Sheet | `showCharakSheet`, `showCharakConfirm` | 32px corners, rises (450ms), leaves (200ms) |
| CTA bar | `CharakCtaBar` | Pinned bottom action block |
| Summary | `CharakSummaryCard`, `CharakSummaryRow`, `CharakSummaryDivider` | Key/value blocks |
| Fees | `CharakFeeList` | Tabular amounts |
| Banner / strip | `CharakNoteBanner`, `CharakInfoStrip` | Tinted, one status tone |
| Empty / outcome | `CharakEmptyState`, `CharakOutcomeState`, `CharakSuccessCheck` | Success = sage disc, tick draws in |
| Loading | `CharakSkeleton`, `CharakSkeletonCard/List/Detail` | Waiting shimmer, 1.4s linear |
| Toast | `showCharakToast` | Ink chrome |
| Call | `CharakCallScaffold` | Always ink, both apps |
| Brand | `CharakLogoMark`, `CharakWordmark` | §10 |

---

## 8. Motion

**Quick out, soft landing.** Everything moves the way One UI does: it leaves
fast and settles slowly, so taps feel instant and nothing jerks.

| Token | Duration | Curve | Used for | Flutter |
|---|---|---|---|---|
| motion.press | 150ms | `cubic-bezier(0.22, 1, 0.36, 1)` | Buttons, tiles, rows: scale **0.96** while held | `CharakPressable`, `CharakMotion.press` |
| motion.standard | 300ms | `cubic-bezier(0.33, 0, 0.1, 1)` | Tabs, segments, status, colour | `CharakMotion.standard`, `CharakCurves.standard` |
| motion.emphasized | 450ms | `cubic-bezier(0.22, 1, 0.36, 1)` | Enter, Now Bar, sheets, card → screen | `CharakMotion.emphasized`, `CharakCurves.emphasized` |
| motion.exit | 200ms | `cubic-bezier(0.4, 0, 1, 1)` | Dismiss, heads-up out, close | `CharakMotion.exit`, `CharakCurves.exit` |
| motion.stagger | +40ms per item | (emphasized) | Screen enter, max 6 items, 240ms tail | `CharakStaggerIn` |
| motion.live | 1600ms loop | standard | Pulse on anything happening now | `CharakLivePulse` |
| motion.header | scroll-linked | linear | Large title fades, app bar appears between 170 and 230px; title drifts at 0.35× | `CharakLargeTitleScaffold` |

**Rules**

1. Only **one hero motion** per screen. The rest stays quiet.
2. **Nothing longer than 450ms.** People are waiting on care, not a show.
3. **Enter from where it lives:** sheets rise, heads-up drops, lists lift 20px.
4. **Numbers never animate their value.** Fees and times stay tabular so they
   don't jitter.
5. With **Reduce motion** on, everything becomes a 150ms fade and loops stop
   (`charakReduceMotion(context)`; every widget above honours it).

**Recurring moments**

| Moment | Spec | Where |
|---|---|---|
| Status change | cross-fade, no slide, 300ms, plus a soft flash of the row | `CharakFadeSwap`, `CharakStatusPulse` |
| Tab pill / segment thumb | slides, never jumps, 300ms | `CharakBottomBar`, `CharakSegmented` |
| Day & slot select | fill fades to blue, chosen item pops 0.9 → 1.05 → 1 | `slot_selection_screen.dart` (`_Pop`) |
| Button wakes up | grey → blue as it becomes available, label changes, arrow slides in | `CharakButton` with `trailingIcon` |
| Payment / booking success | emphasized scale, tick draws in over 300ms | `CharakSuccessCheck` |
| Declined card | fades and slides away on exit (200ms) | doctor `requests_tab.dart` |
| Save doctor (heart) | fills Chandan and pops once | **not built yet**: the heart is a top-bar action that shows a toast (no saved-doctors API) |
| Waiting | shimmer, linear 1.4s loop | `CharakSkeleton` |

---

## 9. Screens

The board annotates three screens (PDF pages 6–11). Their implementation:

### Patient · Home (`apps/patient_app/lib/screens/home/home_tab.dart`)
1. **Screen enter** (450ms emphasized, on open): search, hero card, then tiles
   rise 20px and fade in, 40ms apart (`CharakStaggerIn`).
2. **Large title → app bar** (scroll 0–230px): the greeting fades and drifts up
   at 0.35× scroll speed; from 170px the small "Home" title slides in and the bar
   turns to frosted glass.
3. **Now Bar arrives** (600ms after enter): the live-consult pill rises 90px
   from above the tab bar. Shown when a paid online consult starts within 60 min.
4. **Now Bar expands** (tap): 60 → 140px, shows "Join waiting room". The
   countdown ticks each second in tabular figures.
5. **Press** (150ms) on any tile, card or row.
6. **Reduce motion**: plain fades, pulse stops.

Content: date eyebrow (Chandan) · display greeting · status line · search ·
next booking as a **blue hero** with its action (Pay / View / Status) · Find care
tiles (3 columns).

### Patient · Doctor & slot (`directory/doctor_profile_screen.dart`, `booking/slot_selection_screen.dart`)
In this codebase the board's single screen is split in two: the profile, then
"Pick a day and time".
1. Profile: the doctor's name is the big header, with a rounded-square avatar,
   a Chandan rating chip and "Online · ₹650" / "Home visit · ₹1,100" price pills.
   "Book a slot" sits in the CTA block.
2. Day & slot select: the fill fades to blue and the chosen chip pops
   0.9 → 1.05 → 1.
3. **Button wakes up**: "Pick a slot to continue" (grey) → "Thu 1, 10:30 AM ·
   Continue →" (blue).
4. A tint card explains what happens next ("You pay only after the doctor accepts").
5. Board items not built yet: the Online / Home segment on this screen (the
   channel is picked on the next screen), the staggered entrance on the profile,
   and the save-doctor heart fill.

### Doctor · Requests (`apps/doctor_app/lib/screens/home/requests_tab.dart`)
1. Screen enter: header and request cards rise in, 40ms apart.
2. **Heads-up request**: when a new request arrives live, a blue banner drops
   from the top (450ms emphasized); "Later" / "Review" sends it back up (200ms
   exit) and the new card slides into the list.
3. Header: doctor name eyebrow · "Requests" · "N waiting for your decision" in
   the greeting colour.
4. Request card: avatar, name, "Waiting" chip · hairline · time · channel ·
   fee (tabular) · **Decline** (soft red) + **Review** (blue).
5. Declined cards fade and slide away (exit curve).
6. Large title → frosted ink bar.

The remaining screens (auth, booking flow, onboarding, setup) use the same
components and rules: a big title.large question on top, content in flat cards,
the action in `CharakCtaBar`.

---

## 10. Brand

- **Mark**: Charak with the rod and serpent, a gold halo and leaves.
  `design-system/assets/charak_mark.png` (mark only) and `charak_lockup.png`
  (with चरक). Both are transparent PNGs cut from PDF page 1. In Flutter:
  `CharakLogoMark(height:, lockup:)`. **The mark sets the warm palette; blue does
  the work.**
- **Wordmark**: `CHARAK` at width 125 / weight 800 with tracking, followed by
  `चरक` in Chandan (`CharakWordmark(suffix: 'Partner')` in the doctor app). The
  wordmark is a Chandan moment.
- Splash screens: mark (140px) + wordmark + one muted line, on the ground colour.
- For a vector mark or app icons, re-cut from the source artwork. The PNGs here
  are raster (720px wide).

---

## 11. Using the system in code

### 11.1 Flutter (patient + doctor apps)

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  CharakColors.useScheme(CharakScheme.doctor); // patient app: CharakScheme.patient
  runApp(...ShadApp.router(
    theme: charakShadTheme(),
    materialThemeBuilder: (_, __) => charakMaterialTheme(),
    ...
  ));
}
```

Do:

- Read colours only through **roles**: `CharakColors.ground / card / ink /
  inkMuted / primary …`. They switch with the scheme, so one screen works in both
  apps. Use `CharakPalette.*` only for fixed things (text on a blue hero, avatar
  tones).
- Build screens from the components in §7. Tab roots use
  `CharakLargeTitleScaffold(children: [...])`.
- Use `CharakText.*`. Numbers get `.tabular`. Titles get `.weight(…)` for
  weight changes.
- Use `CharakMotion.*` / `CharakCurves.*` for every duration and curve.
- Wrap anything tappable that isn't a Charak button in `CharakPressable`.

Don't:

- Hard-code hex colours, `Colors.white` fills, `TextStyle(fontFamily: …)` or
  `BoxShadow` in screens.
- Use `CharakColors.ink` as a **fill** (it is text colour; on the doctor scheme
  it is near-white). Selected fills are `CharakColors.primary`.
- Use Chandan for a button.
- Use `const` around widgets that read `CharakColors` (they are getters).

### 11.2 Admin console (React + Tailwind v3 + shadcn)

`admin/src/index.css` imports the generated `styles/charak-tokens.css` and maps
it onto shadcn variables as RGB triples, so `bg-primary/50` works. Extra
Tailwind colours: `ground`, `chandan-*`, `sage-*`, `blue-*`, `ink-*`,
`success`, `warning`, `danger`. Radii: `rounded-card` (26), `rounded-tile`
(20), `rounded-pill`. Shadows are disabled in `tailwind.config.js`. The admin
uses the patient (light) scheme with an ink sidebar.

### 11.3 HTML mockups (opendesign)

Link `opendesign/design-systems/charak/colors_and_type.css`. It loads Anek from
Google Fonts and exposes `--blue-500`, `--patient-ground`,
`--doctor-card`, `--type-title-large` (+ `--type-title-large-width` for
`font-stretch`), `--radius-card`, `--dur-emphasized`, `--ease-emphasized`,
plus the `.tnum`, `.display`, `.title-*` and `.pressable` helpers.

---

## 12. Changing the system

1. **Edit `design-system/tokens.json`.** Don't touch generated files.
2. Run the generator:
   ```bash
   python3 design-system/tool/generate.py          # writes Dart + 2 CSS files
   python3 design-system/tool/generate.py --check  # CI: fails if outputs are stale
   ```
3. If a **role** was added, expose it in `packages/charak_core/lib/design/tokens.dart`
   (`CharakColors`) and, for the admin, in `admin/src/index.css`.
4. Update or add the component in `packages/charak_core/lib/components/`, and
   show it in `lib/gallery.dart`.
5. Re-render the goldens and look at them:
   ```bash
   cd packages/charak_core
   flutter test --update-goldens test/gallery_golden_test.dart
   ```
6. Check everything compiles:
   ```bash
   (cd packages/charak_core && flutter analyze)
   (cd apps/patient_app && flutter analyze)
   (cd apps/doctor_app && flutter analyze)
   (cd admin && npm run build)
   ```
7. Update this README (tables in §3–§8) and bump `meta.version` in
   `tokens.json` (major for a new visual direction, minor for new tokens or
   components, patch for value tweaks).

**Fonts:** `design-system/tool/fetch_fonts.sh` re-downloads Anek from
google/fonts. **Brand mark:** re-cut from the source artwork; if you only have
the PDF, page 1's embedded JPEG is 4320px wide and the mark sits at roughly
x 2880–3820, y 360–1620. Knock out the cream background (`#FEFBF2`).

---

## 13. V1 → V2 migration map

V1 names still compile and now resolve to V2 values, so old code picks up the
new look. New code should use the V2 names.

| V1 | V2 value / replacement |
|---|---|
| `CharakColors.bg` (#FFFFFF) | = `CharakColors.card`. Scaffolds now use `CharakColors.ground` |
| `CharakColors.bgSubtle` (#F5F8FA) | fill: ink-50 / ink-700 |
| `CharakColors.primary` (#376CD5) | Charak Blue 500 `#2456C9` |
| `CharakColors.primarySoft` / `primaryDeep` | blue-50 / blue-700 (doctor: blue-800 / blue-200) |
| `CharakColors.ink` / `inkMuted` | ink-900 / ink-500 (doctor: ink-50 / ink-300) |
| `CharakColors.border` (#E4E8EE) | ink-100 line. Outlines use `borderStrong` |
| `success` / `warning` / `danger` | Confirmed `#5E7F3A` / Review `#E07A1F` / Declined `#D23B3B` |
| `CharakText` Inter 30/22/18/16/14/11 | Anek scale, §4. `h1` → titleMedium, `h2` → titleSmall, `micro` → overline |
| `CharakRadius.card` 20 / `input` 14 | 26 / 20 |
| `CharakShadow.*` | **removed**: V2 is flat |
| `CharakDurations.*` (100–600ms) | mapped to motion tokens (150–450ms) |
| `CharakCurves.out` / `inOut` | = `emphasized` / `standard`; new `exit`, `press` |
| Uppercase status pills | Sentence-case chips with one colour per state |
| Ink-filled selected chips | Blue-filled |
| Hand-rolled tab bars | `CharakBottomBar` |
| Inline screen headers | `CharakLargeTitleScaffold` |
| Centred dialogs | `showCharakConfirm` sheets |
| Doctor app: light screens + ink tab bar | Fully ink (`CharakScheme.doctor`) |

---

## 14. Review checklist

For any new or changed screen:

- [ ] Big title in the top third; main action in the lower two-thirds (CTA bar,
      card bottom or Now Bar).
- [ ] Tab root uses `CharakLargeTitleScaffold`; pushed screen uses `CharakTopBar`.
- [ ] Only role colours. No hex, no `BoxShadow`, no Chandan buttons.
- [ ] Looks right on **both** schemes (check the doctor app for anything shared).
- [ ] Every number (fee, time, rating, count) is `.tabular`.
- [ ] Headers use title.* styles (width ≥ 118).
- [ ] Buttons ≥ 52px (44px compact), touch targets ≥ 44px.
- [ ] One hero motion. Durations ≤ 450ms, all from `CharakMotion`. Reduce motion
      honoured.
- [ ] Status shown with `CharakStatusPill`, never colour alone.
- [ ] `flutter analyze` clean; goldens refreshed if a shared component changed.
