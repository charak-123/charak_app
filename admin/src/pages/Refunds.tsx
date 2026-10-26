import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { format, formatDistanceToNowStrict } from 'date-fns'
import { AlertCircle, Clock, RotateCcw, Undo2 } from 'lucide-react'
import { api } from '@/lib/api'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs'
import {
  PageBody, PageHeader, Section, StatGrid, StatTile, Toolbar,
  EmptyState, ErrorState, ListSkeleton,
} from '@/components/shell'
import { MetaChip, StatusPill } from '@/components/status'

/**
 * The refunds queue (backend services/refunds.py).
 *
 * A refund is 'processed' only once Razorpay confirms it. 'pending' and
 * 'processing' clear on their own (the retry sweep and Razorpay's webhook);
 * 'failed' is the state that needs a person: Razorpay refused it, or retries
 * ran out. Retry sends it again; anything else (a wrong account, a disputed
 * payment) is handled in the Razorpay dashboard, and the webhook records it.
 */
type RefundStatus = 'pending' | 'processing' | 'processed' | 'failed'

type Refund = {
  id: string
  amount_paise: number
  status: RefundStatus
  reason: 'booking_cancelled' | 'late_capture' | 'ops'
  attempts: number
  failure_reason: string | null
  razorpay_refund_id: string | null
  requested_by_role: string
  created_at: string
  processed_at: string | null
  bookings: {
    id: string
    channel: string
    scheduled_start: string
    cancelled_by: string | null
    doctors: { name: string | null } | null
    users: { name: string | null } | null
  } | null
}

type View = 'open' | 'failed' | 'processed'

const VIEWS: { label: string; value: View }[] = [
  { label: 'Not yet refunded', value: 'open' },
  { label: 'Needs attention', value: 'failed' },
  { label: 'Refunded', value: 'processed' },
]

const REASON: Record<Refund['reason'], string> = {
  booking_cancelled: 'Booking cancelled',
  late_capture: 'Paid after slot released',
  ops: 'Refunded by ops',
}

const inr = new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', minimumFractionDigits: 0, maximumFractionDigits: 2 })
const rupees = (paise: number) => inr.format(paise / 100)

export default function Refunds() {
  const [view, setView] = useState<View>('open')
  const [busy, setBusy] = useState<string | null>(null)
  const [errors, setErrors] = useState<Record<string, string>>({})
  const queryClient = useQueryClient()

  // The strip counts everything Razorpay hasn't confirmed, whichever tab is open.
  const open = useQuery<Refund[]>({
    queryKey: ['admin-refunds', 'open'],
    queryFn: () => api.get<Refund[]>('/admin/refunds'),
  })

  const { data: refunds = [], isLoading, isError, error } = useQuery<Refund[]>({
    queryKey: ['admin-refunds', view],
    queryFn: () => api.get<Refund[]>(view === 'open' ? '/admin/refunds' : `/admin/refunds?status=${view}`),
  })

  const openRows = open.data ?? []
  const failed = openRows.filter(r => r.status === 'failed')
  const inFlight = openRows.filter(r => r.status !== 'failed')
  const sum = (rows: Refund[]) => rupees(rows.reduce((t, r) => t + r.amount_paise, 0))

  async function retry(id: string) {
    setBusy(id)
    setErrors(e => ({ ...e, [id]: '' }))
    try {
      const row = await api.post<Refund>(`/admin/refunds/${id}/retry`, {})
      if (row.status === 'failed') {
        setErrors(e => ({ ...e, [id]: row.failure_reason ?? 'Razorpay refused it again.' }))
      }
    } catch (e) {
      setErrors(prev => ({ ...prev, [id]: (e as Error).message }))
    } finally {
      setBusy(null)
      queryClient.invalidateQueries({ queryKey: ['admin-refunds'] })
      queryClient.invalidateQueries({ queryKey: ['admin-metrics'] })
    }
  }

  return (
    <div>
      <PageHeader
        title="Refunds"
        description="Money on its way back to patients. A refund counts as done only once Razorpay confirms it."
      />

      <PageBody>
        <Section title="At a glance">
          <StatGrid>
            <StatTile
              icon={AlertCircle} tone={failed.length ? 'critical' : 'good'} value={failed.length}
              label="Needs attention" hint={failed.length ? sum(failed) : 'Nothing stuck'}
            />
            <StatTile
              icon={Clock} tone="neutral" value={inFlight.length}
              label="In flight" hint={inFlight.length ? `${sum(inFlight)} with Razorpay or queued` : 'None'}
            />
          </StatGrid>
        </Section>

        <Section title="Queue" hint={`${refunds.length} shown`}>
          <Toolbar>
            <Tabs className="min-w-0 max-w-full" value={view} onValueChange={v => setView(v as View)}>
              <TabsList className="max-w-full justify-start overflow-x-auto overflow-y-hidden [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
                {VIEWS.map(({ label, value }) => (
                  <TabsTrigger key={value} value={value}>{label}</TabsTrigger>
                ))}
              </TabsList>
            </Tabs>
          </Toolbar>

          {isLoading && <ListSkeleton rows={4} height="h-20" />}
          {isError && <ErrorState what="refunds" error={error} />}
          {!isLoading && !isError && refunds.length === 0 && (
            <EmptyState
              icon={Undo2}
              title={view === 'failed' ? 'No stuck refunds' : 'Nothing in this view'}
              hint={view === 'open' ? 'Every refund has been confirmed by Razorpay.' : undefined}
            />
          )}

          {!isLoading && !isError && refunds.length > 0 && (
            <div className="space-y-3">
              {refunds.map(r => {
                const b = r.bookings
                return (
                  <Card key={r.id}>
                    <CardContent className="space-y-3 p-4">
                      <div className="flex flex-wrap items-center gap-2">
                        <StatusPill status={r.status} />
                        <span className="text-base font-semibold tabular-nums">{rupees(r.amount_paise)}</span>
                        <MetaChip>{REASON[r.reason] ?? r.reason}</MetaChip>
                        {b && <MetaChip mono>Booking {b.id.slice(0, 8)}</MetaChip>}
                        <span
                          className="ml-auto text-xs text-muted-foreground"
                          title={format(new Date(r.created_at), 'd MMM yyyy, h:mm a')}
                        >
                          {formatDistanceToNowStrict(new Date(r.created_at), { addSuffix: true })}
                        </span>
                      </div>

                      {b && (
                        <p className="text-sm text-muted-foreground">
                          {b.users?.name ?? 'Patient'} · {b.doctors?.name ?? 'Doctor'} ·{' '}
                          {b.channel === 'home_visit' ? 'Home visit' : 'Online consult'} on{' '}
                          {format(new Date(b.scheduled_start), 'd MMM, h:mm a')}
                          {b.cancelled_by ? ` · cancelled by ${b.cancelled_by}` : ''}
                        </p>
                      )}

                      {(r.failure_reason || errors[r.id]) && (
                        <p className="flex items-start gap-1.5 text-xs text-destructive">
                          <AlertCircle size={13} className="mt-0.5 shrink-0" />
                          {errors[r.id] || r.failure_reason}
                        </p>
                      )}

                      <div className="flex flex-wrap items-center gap-x-4 gap-y-1 border-t pt-3 text-xs text-muted-foreground">
                        <span>{r.attempts} attempt{r.attempts === 1 ? '' : 's'}</span>
                        {r.razorpay_refund_id && <span className="font-mono">{r.razorpay_refund_id}</span>}
                        {r.processed_at && <span>Confirmed {format(new Date(r.processed_at), 'd MMM, h:mm a')}</span>}
                        {r.status === 'failed' && (
                          <Button
                            size="sm" className="ml-auto"
                            disabled={busy === r.id}
                            onClick={() => retry(r.id)}
                          >
                            <RotateCcw size={14} />
                            {busy === r.id ? 'Sending…' : 'Retry refund'}
                          </Button>
                        )}
                      </div>
                    </CardContent>
                  </Card>
                )
              })}
            </div>
          )}
        </Section>
      </PageBody>
    </div>
  )
}
