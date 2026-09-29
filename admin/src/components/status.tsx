/**
 * One status vocabulary for the whole panel.
 *
 * Three pages each had their own StatusBadge, so the same state rendered
 * differently depending on where you were looking — "Pending" was an outline
 * chip in one place and a tinted chip in another. Every status now maps to a
 * single tone, and every tone renders identically.
 */
import { cn } from '@/lib/utils'
import type { Tone } from '@/components/shell'

const TONE_CLASS: Record<Tone, string> = {
  good:     'border-success/30 bg-success/10 text-success',
  warning:  'border-warning/30 bg-warning/10 text-warning',
  critical: 'border-destructive/30 bg-destructive/10 text-destructive',
  neutral:  'border-border bg-muted text-muted-foreground',
}

/** Status -> label + tone. The single source of truth for how a state reads. */
const STATUS_MAP: Record<string, { label: string; tone: Tone }> = {
  // bookings
  requested: { label: 'Requested', tone: 'warning' },
  accepted:  { label: 'Accepted',  tone: 'neutral' },
  paid:      { label: 'Paid',      tone: 'good' },
  completed: { label: 'Completed', tone: 'good' },
  cancelled: { label: 'Cancelled', tone: 'critical' },
  declined:  { label: 'Declined',  tone: 'critical' },
  no_show:   { label: 'No-show',   tone: 'critical' },
  // doctors
  verified:  { label: 'Verified',  tone: 'good' },
  pending:   { label: 'Pending',   tone: 'warning' },
  rejected:  { label: 'Rejected',  tone: 'critical' },
  suspended: { label: 'Suspended', tone: 'critical' },
  // complaints
  open:      { label: 'Open',      tone: 'critical' },
  in_review: { label: 'In Review', tone: 'warning' },
  resolved:  { label: 'Resolved',  tone: 'good' },
  closed:    { label: 'Closed',    tone: 'neutral' },
  // procedure bills
  under_review: { label: 'Under Review', tone: 'warning' },
  flagged:      { label: 'Flagged',      tone: 'critical' },
}

export function statusLabel(status: string) {
  return STATUS_MAP[status]?.label ?? status
}

export function StatusPill({ status, className }: { status: string; className?: string }) {
  const entry = STATUS_MAP[status] ?? { label: status, tone: 'neutral' as Tone }
  return (
    <span
      className={cn(
        'inline-flex shrink-0 items-center rounded-full border px-2 py-0.5 text-xs font-medium',
        TONE_CLASS[entry.tone],
        className,
      )}
    >
      {entry.label}
    </span>
  )
}

/** A quieter chip for attributes that aren't states (channels, roles, ids). */
export function MetaChip({ children, mono }: { children: React.ReactNode; mono?: boolean }) {
  return (
    <span
      className={cn(
        'inline-flex items-center rounded-md border border-border bg-muted/60 px-1.5 py-0.5 text-xs text-muted-foreground',
        mono && 'font-mono',
      )}
    >
      {children}
    </span>
  )
}
