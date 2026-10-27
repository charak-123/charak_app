import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { format, formatDistanceToNowStrict } from 'date-fns'
import { ShieldAlert } from 'lucide-react'
import { api } from '@/lib/api'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { PageBody, PageHeader, Section, Toolbar, EmptyState, ErrorState, ListSkeleton } from '@/components/shell'
import { MetaChip, StatusPill } from '@/components/status'
import BookingTimeline from '@/components/BookingTimeline'

/**
 * Incidents (backend services/incidents.py, migration 0028). A report is not a
 * verdict: decide from the evidence, with a reason. Only a confirmed incident
 * whose cause is the doctor, not reversed on appeal, counts against their
 * reliability. Every step is recorded (incident_events, audit_log).
 */
type Incident = {
  id: string
  case_ref: string
  booking_id: string
  type: string
  reported_as: string | null
  reported_by_role: string
  cause: string
  status: string
  evidence: Record<string, unknown>
  patient_note: string | null
  doctor_response: string | null
  decision_reason: string | null
  appeal_status: string
  appeal_note: string | null
  remedy_eligible: boolean
  remedy: string
  auto_confirm_at: string | null
  created_at: string
  bookings: { channel: string; scheduled_start: string; status: string } | null
  doctors: { name: string | null } | null
  users: { name: string | null } | null
  events: { event: string; actor_role: string; note: string | null; occurred_at: string }[]
}

const TYPE: Record<string, string> = {
  doctor_no_show: 'Doctor no-show', technical: 'Call problem', doctor_reschedule: 'Doctor moved visit',
  doctor_late_cancel: 'Doctor cancelled late', other: 'Other',
}
const CAUSES = ['doctor', 'patient', 'platform', 'mutual', 'undetermined']

function evidenceLines(e: Record<string, unknown>): string[] {
  const out: string[] = []
  if (e.scheduled_start) out.push(`Slot ${format(new Date(String(e.scheduled_start)), 'd MMM, h:mm a')}`)
  if ('journey_started_at' in e) out.push(e.journey_started_at ? `Journey started ${format(new Date(String(e.journey_started_at)), 'h:mm a')}` : 'No journey started')
  if ('doctor_joined' in e) out.push(`Doctor ${e.doctor_joined ? 'joined' : 'never joined'} the call`)
  if ('patient_joined' in e) out.push(`Patient ${e.patient_joined ? 'joined' : 'never joined'}`)
  if (e.stated_cause) out.push(`Doctor's reason: ${String(e.stated_cause).replace(/_/g, ' ')}`)
  return out
}

export default function Incidents() {
  const [view, setView] = useState<'open' | 'appealed' | 'all'>('open')
  const [timeline, setTimeline] = useState<string | null>(null)
  const [form, setForm] = useState<Record<string, { cause: string; reason: string; remedy: boolean }>>({})
  const [busy, setBusy] = useState<string | null>(null)
  const [err, setErr] = useState<Record<string, string>>({})
  const qc = useQueryClient()
  const { data = [], isLoading, isError, error } = useQuery<Incident[]>({
    queryKey: ['admin-incidents', view],
    queryFn: () => api.get<Incident[]>(`/admin/incidents?view=${view}`),
    refetchInterval: 60_000,
  })

  async function post(id: string, path: string, body: unknown) {
    setBusy(id)
    setErr(e => ({ ...e, [id]: '' }))
    try {
      await api.post(`/admin/incidents/${id}/${path}`, body)
      qc.invalidateQueries({ queryKey: ['admin-incidents'] })
    } catch (e) {
      setErr(p => ({ ...p, [id]: (e as Error).message }))
    } finally {
      setBusy(null)
    }
  }

  return (
    <div>
      <PageHeader title="Incidents"
        description="Reported problems with visits. A report isn't a verdict: decide from the evidence, and say why." />
      <PageBody>
        <Section title="Queue" hint={`${data.length} shown`}>
          <Toolbar>
            <Tabs value={view} onValueChange={v => setView(v as typeof view)}>
              <TabsList>
                <TabsTrigger value="open">To decide</TabsTrigger>
                <TabsTrigger value="appealed">Appeals</TabsTrigger>
                <TabsTrigger value="all">All</TabsTrigger>
              </TabsList>
            </Tabs>
          </Toolbar>
          {isLoading && <ListSkeleton rows={3} height="h-40" />}
          {isError && <ErrorState what="incidents" error={error} />}
          {!isLoading && !isError && data.length === 0 && <EmptyState icon={ShieldAlert} title="Nothing waiting" />}
          <div className="space-y-3">
            {data.map(i => {
              const f = form[i.id] ?? { cause: i.cause, reason: '', remedy: false }
              const set = (p: Partial<typeof f>) => setForm(s => ({ ...s, [i.id]: { ...f, ...p } }))
              const ok = f.reason.trim().length >= 5 && busy !== i.id
              return (
                <Card key={i.id}>
                  <CardContent className="space-y-3 p-4">
                    <div className="flex flex-wrap items-center gap-2 text-sm">
                      <span className="font-semibold tabular-nums">{i.case_ref}</span>
                      <MetaChip>{TYPE[i.type] ?? i.type}</MetaChip>
                      <StatusPill status={i.status === 'reported' ? 'open' : i.status === 'under_review' ? 'in_review' : i.status === 'confirmed' ? 'resolved' : 'closed'} />
                      {i.appeal_status !== 'none' && <MetaChip>Appeal: {i.appeal_status}</MetaChip>}
                      <span className="ml-auto text-xs text-muted-foreground">
                        {formatDistanceToNowStrict(new Date(i.created_at), { addSuffix: true })}
                      </span>
                    </div>
                    <p className="text-sm text-muted-foreground">
                      {i.users?.name ?? 'Patient'} · {i.doctors?.name ?? 'Doctor'} ·{' '}
                      {i.bookings?.channel === 'home_visit' ? 'Home visit' : 'Online'} · reported by the {i.reported_by_role}
                      {i.reported_as ? ` as "${i.reported_as.replace(/_/g, ' ')}"` : ''}
                    </p>
                    <ul className="list-disc pl-5 text-sm">{evidenceLines(i.evidence).map(l => <li key={l}>{l}</li>)}</ul>
                    {i.auto_confirm_at && <p className="text-xs text-muted-foreground">Confirms automatically {format(new Date(i.auto_confirm_at), 'd MMM, h:mm a')} unless the doctor responds.</p>}
                    {i.patient_note && <p className="text-sm"><b>Patient:</b> {i.patient_note}</p>}
                    {i.doctor_response && <p className="text-sm"><b>Doctor:</b> {i.doctor_response}</p>}
                    {i.appeal_note && <p className="text-sm"><b>Appeal:</b> {i.appeal_note}</p>}
                    {i.decision_reason && <p className="text-sm"><b>Decision:</b> {i.decision_reason} (cause: {i.cause})</p>}
                    <p className="text-xs text-muted-foreground">
                      Remedy: {i.remedy_eligible ? (i.remedy === 'pending' ? 'offered, not chosen yet' : i.remedy) : 'not offered'}
                      {' · '}{i.events.map(e => e.event.replace(/_/g, ' ')).join(' → ')}
                    </p>

                    <div className="space-y-2 border-t pt-3">
                      <div className="flex flex-wrap items-center gap-2">
                        <select className="rounded-md border bg-background px-2 py-1.5 text-sm" value={f.cause}
                          onChange={e => set({ cause: e.target.value })}>
                          {CAUSES.map(c => <option key={c} value={c}>Cause: {c}</option>)}
                        </select>
                        <input className="min-w-56 flex-1 rounded-md border bg-background px-2 py-1.5 text-sm"
                          placeholder="Reason (recorded, shown to the doctor)" value={f.reason}
                          onChange={e => set({ reason: e.target.value })} />
                        {!i.remedy_eligible && (
                          <label className="flex items-center gap-1 text-xs">
                            <input type="checkbox" checked={f.remedy} onChange={e => set({ remedy: e.target.checked })} />
                            Offer the patient a refund or another doctor
                          </label>
                        )}
                      </div>
                      <div className="flex flex-wrap gap-2">
                        {i.appeal_status === 'appealed' ? (
                          <>
                            <Button size="sm" variant="outline" disabled={!ok} onClick={() => post(i.id, 'appeal-decision', { outcome: 'upheld', reason: f.reason })}>Uphold</Button>
                            <Button size="sm" disabled={!ok} onClick={() => post(i.id, 'appeal-decision', { outcome: 'reversed', reason: f.reason })}>Reverse</Button>
                          </>
                        ) : (
                          <>
                            <Button size="sm" disabled={!ok || f.cause === 'undetermined'} onClick={() => post(i.id, 'decide', { status: 'confirmed', cause: f.cause, reason: f.reason, offer_remedy: f.remedy })}>Confirm</Button>
                            <Button size="sm" variant="outline" disabled={!ok} onClick={() => post(i.id, 'decide', { status: 'dismissed', cause: f.cause, reason: f.reason, offer_remedy: f.remedy })}>Dismiss</Button>
                            <Button size="sm" variant="outline" disabled={!ok} onClick={() => post(i.id, 'decide', { status: 'undetermined', cause: 'undetermined', reason: f.reason, offer_remedy: f.remedy })}>Undetermined</Button>
                          </>
                        )}
                        {i.remedy_eligible && i.remedy === 'pending' && (
                          <Button size="sm" variant="destructive" disabled={busy === i.id} onClick={() => post(i.id, 'refund', {})}>Refund the patient now</Button>
                        )}
                        <Button size="sm" variant="ghost" onClick={() => setTimeline(i.booking_id)}>Booking timeline</Button>
                      </div>
                      {err[i.id] && <p className="text-xs text-destructive">{err[i.id]}</p>}
                    </div>
                  </CardContent>
                </Card>
              )
            })}
          </div>
        </Section>
      </PageBody>
      <BookingTimeline bookingId={timeline} onClose={() => setTimeline(null)} />
    </div>
  )
}
