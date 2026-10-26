import { useQuery } from '@tanstack/react-query'
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
  if (typeof m.version === 'number') out.push(`version ${m.version}${m.corrects ? ' (correction)' : ''}`)
  if (m.kind === 'notes') out.push('consultation notes')
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
      </DialogContent>
    </Dialog>
  )
}
