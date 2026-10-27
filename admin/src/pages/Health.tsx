import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Activity } from 'lucide-react'
import { api } from '@/lib/api'
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { PageBody, PageHeader, Section, StatGrid, StatTile, Toolbar, ErrorState, ListSkeleton } from '@/components/shell'

/**
 * Where the workflow fails (spec §21), from ops_metrics() (migration 0029):
 * counts only, nothing about any one patient. Rates are shown with their
 * counts so a small sample doesn't read as a trend.
 */
type Metrics = {
  window_days: number
  bookings: Record<string, number>
  attendance: Record<string, number | Record<string, number>>
  incidents: Record<string, number | Record<string, number>>
  refunds: Record<string, number | null | Record<string, number>>
  prescriptions: Record<string, number | null>
  reviews: Record<string, number | null | Record<string, number>>
  money: Record<string, number | Record<string, number>>
  system: Record<string, number>
}

const n = (v: unknown) => (typeof v === 'number' ? v : 0)
const pct = (a: number, b: number) => (b > 0 ? `${Math.round((100 * a) / b)}%` : '—')
const of = (a: number, b: number) => (b > 0 ? `${a} of ${b}` : 'none yet')
const pairs = (o: unknown) => Object.entries((o as Record<string, number>) ?? {}).map(([k, v]) => `${k.replace(/_/g, ' ')} ${v}`).join(' · ') || 'none'

export default function Health() {
  const [days, setDays] = useState('30')
  const { data: m, isLoading, isError, error } = useQuery<Metrics>({
    queryKey: ['admin-health', days],
    queryFn: () => api.get<Metrics>(`/admin/health?days=${days}`),
  })

  return (
    <div>
      <PageHeader title="Health" description="Where visits, refunds and prescriptions go wrong. Counts only; no patient details." />
      <PageBody>
        <Toolbar>
          <Tabs value={days} onValueChange={setDays}>
            <TabsList>
              <TabsTrigger value="7">7 days</TabsTrigger>
              <TabsTrigger value="30">30 days</TabsTrigger>
              <TabsTrigger value="90">90 days</TabsTrigger>
            </TabsList>
          </Tabs>
        </Toolbar>
        {isLoading && <ListSkeleton rows={6} height="h-24" />}
        {isError && <ErrorState what="health numbers" error={error} />}
        {m && (() => {
          const dist = (m.reviews.distribution ?? {}) as Record<string, number>
          const payouts = (m.money.payouts ?? {}) as Record<string, number>
          return (
          <>
            <Section title="Bookings">
              <StatGrid>
                <StatTile icon={Activity} tone="neutral" value={pct(n(m.bookings.confirmed), n(m.bookings.requested))}
                  label="Confirmed (paid)" hint={of(n(m.bookings.confirmed), n(m.bookings.requested))} />
                <StatTile icon={Activity} tone="neutral" value={n(m.bookings.patient_cancelled_free) + n(m.bookings.patient_cancelled_late)}
                  label="Patient cancellations" hint={`${n(m.bookings.patient_cancelled_late)} late (partial or no refund)`} />
                <StatTile icon={Activity} tone={n(m.bookings.doctor_cancelled) ? 'warning' : 'good'} value={n(m.bookings.doctor_cancelled)}
                  label="Doctor cancellations" hint={`${n(m.bookings.requests_expired)} requests expired unanswered`} />
                <StatTile icon={Activity} tone="neutral" value={n(m.bookings.patient_no_shows)} label="Patient no-shows" />
              </StatGrid>
            </Section>
            <Section title="Attendance">
              <StatGrid>
                <StatTile icon={Activity} tone="neutral" value={n(m.attendance.visits_held)} label="Visits held" />
                <StatTile icon={Activity} tone="neutral"
                  value={pct(n(m.attendance.home_visits_with_journey), n(m.attendance.home_visits_held))}
                  label="Home visits with Start journey" hint={of(n(m.attendance.home_visits_with_journey), n(m.attendance.home_visits_held))} />
                <StatTile icon={Activity} tone={n(m.attendance.doctor_no_shows_confirmed) ? 'critical' : 'good'}
                  value={n(m.attendance.doctor_no_shows_confirmed)} label="Confirmed doctor no-shows"
                  hint={`${n(m.attendance.call_problems_reported)} call problems reported`} />
                <StatTile icon={Activity} tone="neutral" value={Object.values((m.attendance.reschedules as Record<string, number>) ?? {}).reduce((a, b) => a + b, 0)}
                  label="Visits moved by doctors" hint={pairs(m.attendance.reschedules)} />
              </StatGrid>
            </Section>
            <Section title="Cases and refunds">
              <StatGrid>
                <StatTile icon={Activity} tone={n(m.incidents.unresolved) ? 'warning' : 'good'} value={n(m.incidents.unresolved)}
                  label="Unresolved cases" hint={`${n(m.incidents.appeals_open)} appeals open · ${n(m.incidents.appeals_reversed)} reversed`} />
                <StatTile icon={Activity} tone="neutral" value={n(m.incidents.replacements_paid)} label="Replacement doctors paid"
                  hint={`remedies: ${pairs(m.incidents.remedies)}`} />
                <StatTile icon={Activity} tone={n(m.refunds.failed) ? 'critical' : 'good'} value={n(m.refunds.failed)} label="Refunds failed"
                  hint={`${n(m.refunds.open)} open · ${of(n(m.refunds.processed), n(m.refunds.count))} processed`} />
                <StatTile icon={Activity} tone="neutral" value={m.refunds.median_minutes_to_processed == null ? '—' : `${m.refunds.median_minutes_to_processed} min`}
                  label="Median time to refund" hint={pairs(m.refunds.by_reason)} />
              </StatGrid>
            </Section>
            <Section title="Prescriptions and follow-ups">
              <StatGrid>
                <StatTile icon={Activity} tone="neutral" value={m.prescriptions.median_minutes_after_start == null ? '—' : `${m.prescriptions.median_minutes_after_start} min`}
                  label="Median time to prescription" hint="after the visit's start" />
                <StatTile icon={Activity} tone="neutral" value={pct(n(m.prescriptions.opened_within_48h), n(m.prescriptions.sent))}
                  label="Opened within 48 h" hint={`${of(n(m.prescriptions.opened_within_48h), n(m.prescriptions.sent))} · ${n(m.prescriptions.completed_by_fallback)} completed by the 72 h fallback`} />
                <StatTile icon={Activity} tone="neutral" value={n(m.prescriptions.awaiting_view)} label="Waiting to be opened" />
                <StatTile icon={Activity} tone="neutral" value={pct(n(m.prescriptions.follow_ups_booked), n(m.prescriptions.follow_ups_recommended))}
                  label="Follow-ups booked" hint={of(n(m.prescriptions.follow_ups_booked), n(m.prescriptions.follow_ups_recommended))} />
              </StatGrid>
            </Section>
            <Section title="Reviews">
              <StatGrid>
                <StatTile icon={Activity} tone="neutral" value={pct(n(m.reviews.count), n(m.reviews.completed_visits))}
                  label="Visits reviewed" hint={of(n(m.reviews.count), n(m.reviews.completed_visits))} />
                <StatTile icon={Activity} tone="neutral"
                  value={pct(n(dist[4]) + n(dist[5]), n(m.reviews.count))} label="Four or five stars"
                  hint={[5, 4, 3, 2, 1].map(k => `${k}★ ${n(dist[k])}`).join(' · ')} />
                <StatTile icon={Activity} tone="neutral"
                  value={[m.reviews.avg_professionalism, m.reviews.avg_communication, m.reviews.avg_punctuality].map(v => v ?? '—').join(' / ')}
                  label="Courtesy / explanation / on time" />
                <StatTile icon={Activity} tone={n(m.reviews.reported_open) ? 'warning' : 'good'} value={n(m.reviews.reported_open)}
                  label="Reviews reported" hint={`${n(m.reviews.hidden)} hidden in total`} />
              </StatGrid>
            </Section>
            <Section title="Money and system">
              <StatGrid>
                <StatTile icon={Activity} tone={n(payouts.failed) ? 'critical' : 'good'} value={n(payouts.failed)}
                  label="Payouts failed" hint={pairs(m.money.payouts)} />
                <StatTile icon={Activity} tone="neutral" value={n(m.money.ledger_reversals)} label="Earnings reversed" hint="refunds after crediting" />
                <StatTile icon={Activity} tone={n(m.system.dead_jobs) + n(m.system.failed_webhooks) ? 'critical' : 'good'}
                  value={n(m.system.dead_jobs) + n(m.system.failed_webhooks)} label="Dead jobs and webhooks" hint="see System" />
                <StatTile icon={Activity} tone={n(m.system.failed_notifications) ? 'warning' : 'good'}
                  value={n(m.system.failed_notifications)} label="Pushes not delivered" />
              </StatGrid>
            </Section>
          </>
          )
        })()}
      </PageBody>
    </div>
  )
}
