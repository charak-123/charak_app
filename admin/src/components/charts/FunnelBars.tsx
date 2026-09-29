import { INK, MARK, SERIES, STATUS } from '@/lib/chart-theme'

export interface FunnelRow {
  label: string
  value: number
  tone?: 'default' | 'good' | 'bad'
}

/**
 * Magnitude across a handful of named stages. Sequential single hue — these are
 * stages of one funnel, not distinct series, so identity colour would mislead.
 * Terminal states (cancelled, declined, no-show) are the exception and carry a
 * reserved status hue.
 */
export default function FunnelBars({ rows }: { rows: FunnelRow[] }) {
  const max = Math.max(...rows.map(r => r.value), 1)

  return (
    <div className="space-y-2.5">
      {rows.map(r => {
        const color =
          r.tone === 'bad' ? STATUS.critical
          : r.tone === 'good' ? SERIES.aqua
          : SERIES.blue
        const pct = (r.value / max) * 100

        return (
          <div key={r.label} className="grid grid-cols-[96px_1fr_auto] items-center gap-3">
            <span className="truncate text-xs text-muted-foreground">{r.label}</span>
            <div className="h-5 w-full rounded-[4px]" style={{ background: INK.grid }}>
              <div
                className="h-full transition-[width] duration-500"
                style={{
                  width: `${Math.max(pct, r.value > 0 ? 2 : 0)}%`,
                  background: color,
                  borderRadius: MARK.barRadius,
                  opacity: r.value === 0 ? 0 : 1,
                }}
              />
            </div>
            <span className="w-6 text-right text-sm font-medium tabular-nums">{r.value}</span>
          </div>
        )
      })}
    </div>
  )
}
