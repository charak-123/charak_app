import { INK, MARK } from '@/lib/chart-theme'

export interface Segment {
  name: string
  value: number
  color: string
}

/**
 * Part-to-whole as a single horizontal stacked bar, with a 2px surface gap
 * between segments and every segment direct-labelled — the palette's light-mode
 * contrast warning requires visible labels rather than colour alone.
 */
export default function CompositionBar({
  segments, format,
}: {
  segments: Segment[]
  format: (n: number) => string
}) {
  const total = segments.reduce((s, x) => s + x.value, 0)
  const shown = segments.filter(s => s.value > 0)

  if (total === 0) {
    return (
      <div
        className="h-2.5 w-full rounded-full"
        style={{ background: INK.grid }}
        role="img"
        aria-label="No data yet"
      />
    )
  }

  return (
    <div className="space-y-3">
      <div className="flex h-2.5 w-full overflow-hidden rounded-full" style={{ gap: MARK.stackGap }}>
        {shown.map(s => (
          <div
            key={s.name}
            title={`${s.name}: ${format(s.value)}`}
            style={{ width: `${(s.value / total) * 100}%`, background: s.color }}
            className="h-full first:rounded-l-full last:rounded-r-full"
          />
        ))}
      </div>

      <div className="flex flex-wrap gap-x-6 gap-y-2">
        {segments.map(s => (
          <div key={s.name} className="flex min-w-[96px] items-start gap-1.5">
            <span
              className="mt-1 h-2 w-2 shrink-0 rounded-[2px]"
              style={{ background: s.color }}
            />
            <div className="min-w-0">
              <p className="truncate text-xs text-muted-foreground">{s.name}</p>
              <p className="text-sm font-medium tabular-nums">{format(s.value)}</p>
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
