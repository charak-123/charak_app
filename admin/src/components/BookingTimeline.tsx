import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useMe } from '@/lib/me'
import { Button } from '@/components/ui/button'
import { format } from 'date-fns'
import { api } from '@/lib/api'
import {
  Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle,
} from '@/components/ui/dialog'
import { ErrorState, ListSkeleton } from '@/components/shell'
import { MetaChip, StatusPill } from '@/components/status'

/**
 * A booking's full history (GET /admin/bookings/{id}/timeline): every change
 * of state, who made it, and the facts recorded with it. The rows come from
 * booking_events, which is append-only, so this is the record, not a summary
 * of it.
 */
type Event = {
  id: number
  event: string
  from_status: string | null
  to_status: string
  actor_role: 'patient' | 'doctor' | 'ops' | 'system'
  actor_id: string | null
  occurred_at: string
  metadata: Record<string, unknown>
}

const EVENT_LABEL: Record<string, string> = {
  created: 'Requested',
  accept: 'Accepted',
  decline: 'Declined',
  pay: 'Payment confirmed',
  cancel: 'Cancelled',
  complete: 'Completed',
  no_show: 'Marked no-show',
  start_journey: 'Doctor started journey',
  start_consultation: 'Consultation started',
  end_consultation: 'Consultation ended',
  prescription_sent: 'Prescription sent',
  rescheduled: 'Moved to a new time',
  ops_complete: 'Completed by ops',
  ops_revert: 'Start undone by ops',
  hold_expire: 'Payment window closed',
  request_expire: 'Request expired',
  status_changed_outside_state_machine: 'Changed outside the app',
}

const ACTOR: Record<Event['actor_role'], string> = {
  patient: 'Patient', doctor: 'Doctor', ops: 'Ops', system: 'System',
}

/** The recorded facts worth reading, in words. */
function details(m: Record<string, unknown>): string[] {
  const out: string[] = []
  if (typeof m.refund_pct === 'number') out.push(`${m.refund_pct}% refunded`)
  if (typeof m.refund_paise === 'number' && m.refund_paise > 0) {
    out.push(`₹${(m.refund_paise / 100).toLocaleString('en-IN')} back`)
  }
  if (typeof m.policy_version === 'string') out.push(`policy ${m.policy_version}`)
  if (typeof m.reason_code === 'string') out.push(`reason: ${m.reason_code.replace(/_/g, ' ')}`)
  if (typeof m.method === 'string') out.push(`paid by ${m.method}`)
  if (typeof m.db_user === 'string') out.push(`as ${m.db_user}`)
  if (typeof m.reason === 'string') out.push(`reason: ${m.reason}`)
  if (typeof m.version === 'number') out.push(`version ${m.version}${m.corrects ? ' (correction)' : ''}`)
  if (m.kind === 'notes') out.push('consultation notes')
  if (typeof m.from === 'string' && typeof m.to === 'string') {
    out.push(`${format(new Date(m.from), 'd MMM h:mm a')} → ${format(new Date(m.to), 'd MMM h:mm a')}`)
  }
  if (m.remedy === 'replacement') out.push('replaced by another doctor')
  if (typeof m.paid_from_payment_id === 'string') out.push('paid from an earlier booking')
  if (typeof m.completion_source === 'string') out.push(m.completion_source.replace(/_/g, ' '))
  return out
}

export default function BookingTimeline({
  bookingId, onClose,
}: { bookingId: string | null; onClose: () => void }) {
  const { data = [], isLoading, isError, error } = useQuery<Event[]>({
    queryKey: ['admin-booking-timeline', bookingId],
    queryFn: () => api.get<Event[]>(`/admin/bookings/${bookingId}/timeline`),
    enabled: bookingId != null,
  })
  const { can } = useMe()
  const qc = useQueryClient()
  const [reason, setReason] = useState('')
  const [overrideError, setOverrideError] = useState<string | null>(null)
  const status = data.length ? data[data.length - 1].to_status : null
  const actions: { action: 'complete' | 'revert'; label: string }[] = [
    ...(status && ['paid', 'in_progress', 'consulted'].includes(status)
      ? [{ action: 'complete' as const, label: 'Mark completed' }] : []),
    ...(status === 'in_progress' ? [{ action: 'revert' as const, label: 'Undo start' }] : []),
  ]

  async function override(action: 'complete' | 'revert') {
    setOverrideError(null)
    try {
      await api.post(`/admin/bookings/${bookingId}/override`, { action, expected_status: status, reason: reason.trim() })
      setReason('')
      qc.invalidateQueries({ queryKey: ['admin-booking-timeline', bookingId] })
    } catch (e) {
      setOverrideError((e as Error).message)
    }
  }

  return (
    <Dialog open={bookingId != null} onOpenChange={open => { if (!open) onClose() }}>
      <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Booking timeline</DialogTitle>
          <DialogDescription>
            Every change, oldest first. <MetaChip mono>{bookingId?.slice(0, 8)}</MetaChip>
          </DialogDescription>
        </DialogHeader>

        {isLoading && <ListSkeleton rows={4} height="h-10" />}
        {isError && <ErrorState what="the timeline" error={error} />}
        {!isLoading && !isError && data.length === 0 && (
          <p className="text-sm text-muted-foreground">
            No events recorded. Bookings made before the event log existed have none.
          </p>
        )}

        {data.length > 0 && (
          <ol className="relative space-y-4 border-l border-border pl-5">
            {data.map(e => (
              <li key={e.id} className="relative">
                <span className="absolute -left-[25px] top-1.5 h-2.5 w-2.5 rounded-full bg-primary" />
                <div className="flex flex-wrap items-center gap-2">
                  <span className="text-sm font-medium">{EVENT_LABEL[e.event] ?? e.event}</span>
                  <StatusPill status={e.to_status} />
                  <span className="ml-auto text-xs text-muted-foreground"
                        title={format(new Date(e.occurred_at), 'd MMM yyyy, HH:mm:ss')}>
                    {format(new Date(e.occurred_at), 'd MMM, HH:mm')}
                  </span>
                </div>
                <p className="mt-0.5 text-xs text-muted-foreground">
                  {ACTOR[e.actor_role] ?? e.actor_role}
                  {e.from_status ? ` · from ${e.from_status}` : ''}
                  {details(e.metadata ?? {}).map(d => ` · ${d}`).join('')}
                </p>
              </li>
            ))}
          </ol>
        )}

        {/* An audited correction through the state machine (no "edit anything"). */}
        {can('bookings.override') && actions.length > 0 && (
          <div className="space-y-2 border-t pt-3">
            <p className="text-xs font-semibold uppercase text-muted-foreground">Correct the status</p>
            <input className="w-full rounded-md border bg-background px-2 py-1.5 text-sm"
              placeholder="Why (at least 10 characters; recorded on the booking and in the audit log)"
              value={reason} onChange={e => setReason(e.target.value)} />
            <div className="flex gap-2">
              {actions.map(a => (
                <Button key={a.action} size="sm" variant="outline" disabled={reason.trim().length < 10}
                  onClick={() => override(a.action)}>{a.label}</Button>
              ))}
            </div>
            {overrideError && <p className="text-xs text-destructive">{overrideError}</p>}
          </div>
        )}
      </DialogContent>
    </Dialog>
  )
}
