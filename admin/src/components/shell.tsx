/**
 * The page shell every admin screen is built from.
 *
 * Each page used to hand-roll its own header, spacing, empty and loading
 * states, which is why the panel read as six unrelated screens. Layout lives
 * here now: pages supply content, not chrome.
 */
import { Link } from 'react-router-dom'
import { ArrowRight, Inbox, type LucideIcon } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { cn } from '@/lib/utils'
import { STATUS } from '@/lib/chart-theme'

/* ── Page frame ───────────────────────────────────────────────────────────── */

export function PageHeader({
  title, description, right,
}: {
  title: string
  description: string
  right?: React.ReactNode
}) {
  return (
    <div className="border-b bg-background px-6 py-5">
      <div className="flex items-start justify-between gap-6">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">{title}</h1>
          <p className="mt-0.5 text-sm text-muted-foreground">{description}</p>
        </div>
        {right && <div className="shrink-0">{right}</div>}
      </div>
    </div>
  )
}

/** One vertical rhythm for every page body. */
export function PageBody({ children }: { children: React.ReactNode }) {
  return <div className="space-y-6 p-6">{children}</div>
}

export function SectionHeading({
  children, hint,
}: {
  children: React.ReactNode
  hint?: string
}) {
  return (
    <div className="flex items-baseline justify-between gap-4">
      <h2 className="text-sm font-semibold">{children}</h2>
      {hint && <span className="text-xs text-muted-foreground">{hint}</span>}
    </div>
  )
}

export function Section({
  title, hint, children,
}: {
  title: React.ReactNode
  hint?: string
  children: React.ReactNode
}) {
  return (
    <section className="space-y-3">
      <SectionHeading hint={hint}>{title}</SectionHeading>
      {children}
    </section>
  )
}

/** Filters and search sit in one row above the content, on every page. */
export function Toolbar({
  children, right,
}: {
  children: React.ReactNode
  right?: React.ReactNode
}) {
  return (
    <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
      <div className="flex flex-wrap items-center gap-2">{children}</div>
      {right && <div className="shrink-0 text-sm text-muted-foreground">{right}</div>}
    </div>
  )
}

/* ── Stat tiles ───────────────────────────────────────────────────────────── */

export type Tone = 'good' | 'warning' | 'critical' | 'neutral'

/**
 * The one number-tile used across the panel. `to` turns it into a queue tile
 * that links where the work gets done; the coloured rail carries urgency by
 * position as well as hue, so it survives greyscale and colour-blindness.
 */
export function StatTile({
  label, value, icon: Icon, tone = 'neutral', to, hint,
}: {
  label: string
  value: React.ReactNode
  icon?: LucideIcon
  tone?: Tone
  to?: string
  hint?: string
}) {
  const idle = value === 0
  const accent = STATUS[tone]

  const body = (
    <Card
      className={cn(
        'relative h-full overflow-hidden transition-all',
        to && 'group-hover:-translate-y-0.5 group-hover:shadow-md',
        to && 'group-focus-visible:ring-2 group-focus-visible:ring-ring',
      )}
    >
      <span
        aria-hidden
        className="absolute inset-y-0 left-0 w-[3px]"
        style={{ background: accent, opacity: idle ? 0.25 : 1 }}
      />
      <CardContent className="p-4 pl-5">
        <div className="flex items-start justify-between gap-2">
          {Icon
            ? <Icon size={16} style={{ color: accent }} />
            : <span className="h-2.5 w-2.5 rounded-full" style={{ background: accent }} />}
          {to && (
            <ArrowRight
              size={14}
              className="text-muted-foreground opacity-0 transition-opacity group-hover:opacity-100"
            />
          )}
        </div>
        <p
          className={cn(
            'mt-2 text-3xl font-semibold leading-none tabular-nums',
            idle && 'text-muted-foreground',
          )}
        >
          {value}
        </p>
        <p className="mt-1.5 text-xs leading-snug text-muted-foreground">{label}</p>
        {hint && <p className="mt-0.5 text-xs text-muted-foreground/70">{hint}</p>}
      </CardContent>
    </Card>
  )

  return to
    ? <Link to={to} className="group block focus-visible:outline-none">{body}</Link>
    : body
}

/** Summary strips are always this grid, so tiles line up across pages. */
export function StatGrid({ children }: { children: React.ReactNode }) {
  return <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">{children}</div>
}

/* ── States ───────────────────────────────────────────────────────────────── */

export function Pulse({ className }: { className?: string }) {
  return <div className={cn('animate-pulse rounded bg-muted', className)} />
}

export function EmptyState({
  icon: Icon = Inbox, title, hint,
}: {
  icon?: LucideIcon
  title: string
  hint?: string
}) {
  return (
    <Card>
      <CardContent className="flex flex-col items-center justify-center gap-2 px-6 py-14 text-center">
        <Icon size={28} className="text-muted-foreground/50" />
        <p className="text-sm font-medium">{title}</p>
        {hint && <p className="text-xs text-muted-foreground">{hint}</p>}
      </CardContent>
    </Card>
  )
}

export function ErrorState({ what, error }: { what: string; error: unknown }) {
  const message = error instanceof Error ? error.message : String(error ?? 'Unknown error')
  return (
    <Card className="border-destructive/30">
      <CardContent className="p-4">
        <p className="text-sm font-medium text-destructive">Couldn't load {what}</p>
        <p className="mt-0.5 text-xs text-muted-foreground">{message}</p>
      </CardContent>
    </Card>
  )
}

/** Row skeleton used wherever a list or table is loading. */
export function ListSkeleton({ rows = 5, height = 'h-12' }: { rows?: number; height?: string }) {
  return (
    <Card>
      <CardContent className="space-y-2 p-4">
        {Array.from({ length: rows }).map((_, i) => (
          <Pulse key={i} className={height} />
        ))}
      </CardContent>
    </Card>
  )
}

/** Every table gets the same surface, so borders and radii match. */
export function TableCard({ children }: { children: React.ReactNode }) {
  return (
    <Card>
      <CardContent className="overflow-x-auto p-0">{children}</CardContent>
    </Card>
  )
}
