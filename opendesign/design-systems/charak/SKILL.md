# CHARAK Design System (V2)

**The spec lives in [`design-system/README.md`](../../../design-system/README.md)**, with
the original board at `design-system/CHARAK_Design_System_V2.pdf`. This file is
the short brief for building HTML mockups in opendesign.

## Tokens

Link `colors_and_type.css` (generated from `design-system/tokens.json`; do not
edit it by hand). It loads **Anek Latin + Anek Devanagari** and defines:

- Ramps `--blue-50…900`, `--chandan-*`, `--sage-*`, `--ink-*`.
- Two schemes: `--patient-*` (ground `#F7F3EC`, card `#FFFFFF`) and `--doctor-*`
  (ground `#0E1726`, card `#182031`). Roles: ground, card, tint, warm, fill, text,
  text-muted, line, line-strong, primary, primary-soft, on-primary-soft, accent-warm,
  success, warning, danger, plus status soft/on pairs.
- Type `--type-<style>` (font shorthand) + `--type-<style>-width` (use with
  `font-stretch`): display 56/60 w125, title-large 36/42 w122, title-medium 26/32 w118,
  title-small 20/26 w112, body-large 18/26, body 16/24, label 15/20, caption 13/18,
  overline 12/16, numeric 20/24 w80 tabular.
- Shape: `--radius-pill 999`, `--radius-sheet 32`, `--radius-card 26`,
  `--radius-tile 20`; `--size-button-min-height 52`.
- Motion: `--dur-press 150ms`, `--dur-standard 300ms`, `--dur-emphasized 450ms`,
  `--dur-exit 200ms` with matching `--ease-*` curves; `.pressable` scales to 0.96.

## Rules

- Look up top, reach down low: big wide title in the top third, actions low.
- Blue acts, Chandan welcomes. Chandan is never a button.
- Flat, tonal, rounded. **No shadows**; white cards on cream (or ink-800 on ink-900).
- Numbers are tabular + narrow (`.tnum`).
- One colour per booking status (Requested chandan, Accepted blue, Confirmed sage,
  Active violet, Needs review orange, Declined red), always with a label.
- Doctor App = the same components on the ink scheme.
