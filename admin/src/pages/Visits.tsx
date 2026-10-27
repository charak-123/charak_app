import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { format, formatDistanceToNowStrict } from 'date-fns'
import { FileClock, FileWarning, History, Lock, Navigation } from 'lucide-react'
import { api } from '@/lib/api'
import { Card, CardContent } from '@/components/ui/card'
import { Button, buttonVariants } from '@/components/ui/button'
import {
  Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle,
} from '@/components/ui/dialog'
import {
  PageBody, PageHeader, Section, StatGrid, StatTile,
  EmptyState, ErrorState, ListSkeleton,
} from '@/components/shell'
import { MetaChip, StatusPill } from '@/components/status'
import BookingTimeline from '@/components/BookingTimeline'

/**
 * The visit queues (backend services/visits.py ops_queues). Flags for a
 * person to look at, not verdicts: a home visit with no journey near its time
 * is not assumed to be a no-show.
 *
 * Prescriptions are clinical records. This page shows whether one was sent
 * and opened, never what it says. Reading the content takes a written reason,
 * and every read is recorded in the audit log before anything is shown
 * (POST /admin/prescriptions/{id}/access).
 */
type Row = {
  id: string
  channel: 'online_consult' | 'home_visit'
  status: string
  scheduled_start: string
  journey_started_at: string | null
  prescription_sent_at: string | null
  patient_name: string | null
  doctor_name: string | null
}

type Queues = {
  journey_not_started: Row[]
  prescription_overdue: Row[]
  prescription_unviewed: Row[]
}

type RxVersion = {
  id: string
  version: number
  kind: 'prescription' | 'notes'
  status: 'draft' | 'submitted' | 'superseded'
  submitted_at: string | null
  first_viewed_at: string | null
  superseded_at: string | null
}

type RxContent = {
  id: string
  version: number
  kind: string
  complaints: string | null
  diagnosis: string | null
  investigations: string | null
  advice: string | null
  items: { position: number; medicine: string; strength: string | null; dose: string | null;
           frequency: string | null; duration: string | null; instructions: string | null }[]
  pdf_url: string | null
  upload_url: string | null
}

const QUEUES: { key: keyof Queues; title: string; hint: string }[] = [
  { key: 'journey_not_started', title: 'Home visits: no journey yet',
    hint: 'Starting within 30 minutes, or already started, and the doctor hasn’t tapped Start journey.' },
  { key: 'prescription_overdue', title: 'Nothing sent to the patient',
    hint: 'More than 2 hours past the start and no prescription or notes sent.' },
  { key: 'prescription_unviewed', title: 'Prescription not opened',
    hint: 'Sent over a day ago. The visit completes on its own 72 hours after sending.' },
]

const when = (iso: string) => format(new Date(iso), 'd MMM, h:mm a')

export default function Visits() {
  const [timeline, setTimeline] = useState<string | null>(null)
  const [rxFor, setRxFor] = useState<string | null>(null)
  const { data, isLoading, isError, error } = useQuery<Queues>({
    queryKey: ['admin-visit-queues'],
    queryFn: () => api.get<Queues>('/admin/visits/queues'),
    refetchInterval: 60_000,
  })

  return (
    <div>
      <PageHeader
        title="Visits"
        description="Visits that may need a nudge. Nothing here changes a booking on its own."
      />
      <PageBody>
        <Section title="At a glance">
          <StatGrid>
            <StatTile icon={Navigation} tone={data?.journey_not_started.length ? 'warning' : 'good'}
              value={data?.journey_not_started.length ?? '—'} label="No journey yet" />
            <StatTile icon={FileWarning} tone={data?.prescription_overdue.length ? 'warning' : 'good'}
              value={data?.prescription_overdue.length ?? '—'} label="Nothing sent" />
            <StatTile icon={FileClock} tone="neutral"
              value={data?.prescription_unviewed.length ?? '—'} label="Not opened" />
          </StatGrid>
        </Section>

        {isLoading && <ListSkeleton rows={4} height="h-20" />}
        {isError && <ErrorState what="visit queues" error={error} />}

        {data && QUEUES.map(q => (
          <Section key={q.key} title={q.title} hint={q.hint}>
            {data[q.key].length === 0 ? (
              <EmptyState icon={History} title="All clear" />
            ) : (
              <div className="space-y-3">
                {data[q.key].map(r => (
                  <Card key={r.id}>
                    <CardContent className="flex flex-wrap items-center gap-2 p-4">
                      <StatusPill status={r.status} />
                      <MetaChip>{r.channel === 'home_visit' ? 'Home visit' : 'Online consult'}</MetaChip>
                      <span className="text-sm">
                        {r.patient_name ?? 'Patient'} · {r.doctor_name ?? 'Doctor'}
                      </span>
                      <span className="text-sm tabular-nums text-muted-foreground">
                        {q.key === 'prescription_unviewed' && r.prescription_sent_at
                          ? `sent ${formatDistanceToNowStrict(new Date(r.prescription_sent_at), { addSuffix: true })}`
                          : when(r.scheduled_start)}
                      </span>
                      <div className="ml-auto flex gap-2">
                        <Button size="sm" variant="outline" onClick={() => setTimeline(r.id)}>Timeline</Button>
                        {q.key === 'prescription_unviewed' && (
                          <Button size="sm" variant="outline" onClick={() => setRxFor(r.id)}>Prescription</Button>
                        )}
                      </div>
                    </CardContent>
                  </Card>
                ))}
              </div>
            )}
          </Section>
        ))}
      </PageBody>

      <BookingTimeline bookingId={timeline} onClose={() => setTimeline(null)} />
      <PrescriptionAccess bookingId={rxFor} onClose={() => setRxFor(null)} />
    </div>
  )
}

/** A booking's prescription versions (status only), and the audited read. */
export function PrescriptionAccess({ bookingId, onClose }: { bookingId: string | null; onClose: () => void }) {
  const [reason, setReason] = useState('')
  const [reading, setReading] = useState<string | null>(null)
  const [content, setContent] = useState<RxContent | null>(null)
  const [err, setErr] = useState<string | null>(null)
  const versions = useQuery<RxVersion[]>({
    queryKey: ['admin-booking-rx', bookingId],
    queryFn: () => api.get<RxVersion[]>(`/admin/bookings/${bookingId}/prescriptions`),
    enabled: !!bookingId,
  })

  function close() {
    setReason(''); setContent(null); setErr(null); setReading(null)
    onClose()
  }

  async function read(id: string) {
    setReading(id); setErr(null)
    try {
      setContent(await api.post<RxContent>(`/admin/prescriptions/${id}/access`, { reason: reason.trim() }))
    } catch (e) {
      setErr((e as Error).message)
    } finally {
      setReading(null)
    }
  }

  return (
    <Dialog open={!!bookingId} onOpenChange={o => { if (!o) close() }}>
      <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Prescription</DialogTitle>
          <DialogDescription>
            Sent and opened times are shown. The content is a patient’s medical record: reading it
            needs a reason, and the read is recorded under your name.
          </DialogDescription>
        </DialogHeader>

        {versions.isLoading && <ListSkeleton rows={2} />}
        {versions.data?.map(v => (
          <div key={v.id} className="flex flex-wrap items-center gap-2 border-b py-2 text-sm last:border-0">
            <MetaChip>v{v.version}</MetaChip>
            <StatusPill status={v.status === 'submitted' ? 'sent' : v.status} />
            <span className="tabular-nums text-muted-foreground">
              {v.submitted_at ? `sent ${when(v.submitted_at)}` : 'not sent'}
              {v.first_viewed_at ? ` · opened ${when(v.first_viewed_at)}` : v.submitted_at ? ' · not opened' : ''}
            </span>
          </div>
        ))}

        {!content && versions.data?.some(v => v.status !== 'draft') && (
          <div className="space-y-2 pt-2">
            <label className="text-sm font-medium" htmlFor="rx-reason">Why do you need to read it?</label>
            <textarea
              id="rx-reason"
              className="min-h-20 w-full rounded-md border bg-background p-2 text-sm"
              placeholder="e.g. Pharmacy called to verify the dose (complaint #…)"
              value={reason}
              onChange={e => setReason(e.target.value)}
            />
            {err && <p className="text-xs text-destructive">{err}</p>}
            <div className="flex flex-wrap gap-2">
              {versions.data.filter(v => v.status !== 'draft').map(v => (
                <Button key={v.id} size="sm" disabled={reason.trim().length < 10 || reading !== null}
                  onClick={() => read(v.id)}>
                  <Lock size={14} />
                  {reading === v.id ? 'Recording…' : `Read v${v.version}`}
                </Button>
              ))}
            </div>
          </div>
        )}

        {content && (
          <div className="space-y-3 pt-2 text-sm">
            {[['Complaints', content.complaints], ['Provisional diagnosis', content.diagnosis],
              ['Investigations', content.investigations], ['Advice', content.advice]]
              .filter(([, v]) => v)
              .map(([k, v]) => (
                <div key={k}>
                  <p className="text-xs font-semibold uppercase text-muted-foreground">{k}</p>
                  <p className="whitespace-pre-wrap">{v}</p>
                </div>
              ))}
            {content.items.length > 0 && (
              <div>
                <p className="text-xs font-semibold uppercase text-muted-foreground">Medicines</p>
                <ul className="list-disc pl-5">
                  {content.items.map(i => (
                    <li key={i.position}>
                      {[i.medicine, i.strength].filter(Boolean).join(' ')}
                      {[i.dose, i.frequency, i.duration, i.instructions].some(Boolean) &&
                        ` — ${[i.dose, i.frequency, i.duration, i.instructions].filter(Boolean).join(' · ')}`}
                    </li>
                  ))}
                </ul>
              </div>
            )}
            <div className="flex gap-2">
              {content.pdf_url && (
                <a className={buttonVariants({ size: 'sm', variant: 'outline' })}
                   href={content.pdf_url} target="_blank" rel="noreferrer">PDF</a>
              )}
              {content.upload_url && (
                <a className={buttonVariants({ size: 'sm', variant: 'outline' })}
                   href={content.upload_url} target="_blank" rel="noreferrer">Handwritten</a>
              )}
            </div>
          </div>
        )}
      </DialogContent>
    </Dialog>
  )
}
