/**
 * Chart palette and mark specs.
 *
 * The hues are the validated categorical order (adjacent-pair CVD ΔE 9.1,
 * normal-vision 22.9 on a light surface). Slots are assigned in fixed order and
 * never cycled — a fifth series folds into "Other" rather than inventing a hue.
 *
 * Defined here as plain hex rather than as Tailwind tokens because the theme's
 * colour vars are bare oklch channels that only resolve inside the config's
 * oklch() wrapper; Recharts needs a literal colour.
 */

// Left as the validated generic palette rather than swapped for CHARAK's own
// blue/chandan/sage hues: the ΔE figures above were measured for THIS set.
// Substituting brand hues here needs the same validator re-run against the
// new set, not an eyeballed swap — an accessibility regression is worse than
// an off-brand chart. INK and STATUS below carry no such risk: they're
// neutrals and single-value accents, not an adjacent categorical set.
export const SERIES = {
  blue:   '#2a78d6',
  orange: '#eb6834',
  aqua:   '#1baf7a',
  yellow: '#eda100',
} as const

/**
 * Ink and furniture — the CHARAK ink ramp (design-system/tokens.json), not a
 * generic grey scale. `primary`/`secondary` are exactly `--foreground` and
 * `--muted-foreground` (see charak-tokens.css); a chart label now reads the
 * same grey as the rest of the page around it.
 */
export const INK = {
  primary:   '#0E1726', // ink-900 — --foreground
  secondary: '#566072', // ink-500 — --muted-foreground
  muted:     '#7A8494', // ink-400 — a step fainter, for axis ticks
  grid:      '#E6E8EC', // ink-100
  surface:   '#ffffff',
}

/**
 * Status hues — the exact `--success`/`--warning`/`--destructive` values
 * (charak-tokens.css, patient scheme), not a separate chart-only palette.
 * Without this, "confirmed" could render teal-green in a StatusPill and
 * olive-green in a chart for the same booking. Reserved: never reused as a
 * categorical slot.
 */
export const STATUS = {
  good:     '#5E7F3A', // --patient-success
  warning:  '#E07A1F', // --patient-warning
  critical: '#D23B3B', // --patient-danger
  neutral:  '#566072', // --patient-text-muted (= INK.secondary)
}

export const MARK = {
  /** 2px strokes; markers appear on hover only, at >= 8px. */
  strokeWidth: 2,
  /** Rounded data-end on bars, anchored to the baseline. */
  barRadius: 4,
  /** Surface-coloured gap between stacked segments. */
  stackGap: 2,
}

export const money = (n: number) => `₹${n.toLocaleString('en-IN', { maximumFractionDigits: 0 })}`

const trim = (s: string) => s.replace(/\.0$/, '')

/** Axis-width money. Keeps one decimal so ticks stay evenly spaced. */
export const compactMoney = (n: number) =>
  n >= 100000 ? `₹${trim((n / 100000).toFixed(1))}L`
  : n >= 1000 ? `₹${trim((n / 1000).toFixed(1))}k`
  : `₹${n}`
