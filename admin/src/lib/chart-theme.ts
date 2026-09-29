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

export const SERIES = {
  blue:   '#2a78d6',
  orange: '#eb6834',
  aqua:   '#1baf7a',
  yellow: '#eda100',
} as const

/** Ink and furniture, matching the app's foreground/muted tokens. */
export const INK = {
  primary:   '#25272b',
  secondary: '#5b6472',
  muted:     '#8b93a1',
  grid:      '#eceef1',
  surface:   '#ffffff',
}

/** Status hues, reserved — never reused as a categorical slot. */
export const STATUS = {
  good:     '#1baf7a',
  warning:  '#eda100',
  critical: '#e34948',
  neutral:  '#8b93a1',
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
