import {
  Area, AreaChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis,
} from 'recharts'
import { format, parseISO } from 'date-fns'
import { INK, MARK } from '@/lib/chart-theme'
import { TooltipShell, axisProps } from './primitives'

export interface TrendPoint {
  date: string
  [k: string]: string | number
}

/**
 * A single-measure trend. Two measures of different scale get two of these
 * side by side rather than one chart with two y-axes.
 */
export default function TrendArea({
  data, dataKey, color, label, formatValue, height = 180,
}: {
  data: TrendPoint[]
  dataKey: string
  color: string
  label: string
  formatValue: (n: number) => string
  height?: number
}) {
  const gradientId = `grad-${dataKey}`

  return (
    <ResponsiveContainer width="100%" height={height}>
      <AreaChart data={data} margin={{ top: 4, right: 8, bottom: 0, left: -12 }}>
        <defs>
          <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={color} stopOpacity={0.18} />
            <stop offset="100%" stopColor={color} stopOpacity={0.01} />
          </linearGradient>
        </defs>

        <CartesianGrid stroke={INK.grid} strokeDasharray="0" vertical={false} />

        <XAxis
          {...axisProps}
          dataKey="date"
          minTickGap={28}
          tickFormatter={d => format(parseISO(d), 'd MMM')}
        />
        <YAxis {...axisProps} width={56} tickFormatter={v => formatValue(Number(v))} />

        <Tooltip
          cursor={{ stroke: INK.muted, strokeWidth: 1 }}
          content={({ active, payload }) => {
            if (!active || !payload?.length) return null
            const p = payload[0]
            return (
              <TooltipShell
                label={format(parseISO(String(p.payload.date)), 'EEE d MMM')}
                rows={[{
                  key: dataKey, color, name: label,
                  value: formatValue(Number(p.value)),
                }]}
              />
            )
          }}
        />

        <Area
          type="monotone"
          dataKey={dataKey}
          stroke={color}
          strokeWidth={MARK.strokeWidth}
          fill={`url(#${gradientId})`}
          activeDot={{ r: 4, strokeWidth: 2, stroke: INK.surface }}
          dot={false}
        />
      </AreaChart>
    </ResponsiveContainer>
  )
}
