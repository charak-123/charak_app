import { INK } from '@/lib/chart-theme'

/** Shared tooltip shell, so every chart's hover layer reads the same. */
export function TooltipShell({
  label, rows,
}: {
  label: string
  rows: { key: string; color?: string; name: string; value: string }[]
}) {
  return (
    <div className="rounded-lg border border-border bg-popover px-3 py-2 shadow-md">
      <p className="mb-1.5 text-xs font-medium text-foreground">{label}</p>
      <div className="space-y-1">
        {rows.map(r => (
          <div key={r.key} className="flex items-center gap-2 text-xs">
            {r.color && (
              <span
                className="h-2 w-2 shrink-0 rounded-[2px]"
                style={{ background: r.color }}
              />
            )}
            <span className="text-muted-foreground">{r.name}</span>
            <span className="ml-auto font-medium tabular-nums text-foreground">{r.value}</span>
          </div>
        ))}
      </div>
    </div>
  )
}

/** Recessive axis styling shared by every chart. */
export const axisProps = {
  stroke: INK.grid,
  tickLine: false,
  axisLine: false,
  tick: { fill: INK.muted, fontSize: 11 },
} as const

/** A legend swatch + label. Identity is never carried by colour alone. */
export function LegendRow({
  items,
}: {
  items: { name: string; color: string; value?: string }[]
}) {
  return (
    <div className="flex flex-wrap items-center gap-x-4 gap-y-1.5">
      {items.map(i => (
        <div key={i.name} className="flex items-center gap-1.5">
          <span className="h-2 w-2 rounded-[2px]" style={{ background: i.color }} />
          <span className="text-xs text-muted-foreground">{i.name}</span>
          {i.value && (
            <span className="text-xs font-medium tabular-nums text-foreground">{i.value}</span>
          )}
        </div>
      ))}
    </div>
  )
}
