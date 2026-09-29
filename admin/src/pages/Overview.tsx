import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { format, parseISO } from 'date-fns'
import {
  ShieldCheck, BookOpen, MessageSquare, ClipboardList,
  ArrowRight, Ban, ScrollText, Activity,
} from 'lucide-react'
import { api } from '@/lib/api'
import { Card, CardContent } from '@/components/ui/card'
import {
  PageBody, PageHeader, SectionHeading, StatGrid, StatTile, Pulse, ErrorState,
} from '@/components/shell'
import { MetaChip } from '@/components/status'
import { SERIES, compactMoney, money } from '@/lib/chart-theme'
import TrendArea, { type TrendPoint } from '@/components/charts/TrendArea'
import CompositionBar from '@/components/charts/CompositionBar'
import FunnelBars from '@/components/charts/FunnelBars'

interface Metrics {
  doctors: {
    total: number; pending: number; verified: number
    rejected: number; suspended: number
  }
  bookings: {
    total: number; requested: number; accepted: number; paid: number
    completed: number; cancelled: number; declined: number; no_show: number
  }
  revenue: {
    consult_gross: number; procedure_gross: number
    commission_earned: number; owed_to_doctors: number
  }
  queues: {
    bills_under_review: number
    complaints_open: number
    complaints_in_review: number
  }
}

interface AuditEntry {
  id: string
  actor_role: string | null
  entity: string
  entity_id: string | null
  action: string
  at: string
}


export default function Overview() {
  const metrics = useQuery<Metrics>({
    queryKey: ['admin-metrics'],
    queryFn: () => api.get('/admin/metrics'),
    refetchInterval: 60_000,
  })

  const trend = useQuery<TrendPoint[]>({
    queryKey: ['admin-timeseries', 30],
    queryFn: () => api.get('/admin/metrics/timeseries?days=30'),
  })

  const audit = useQuery<AuditEntry[]>({
    queryKey: ['audit-log', 12],
    queryFn: () => api.get('/admin/audit-log?limit=12'),
  })

  const m = metrics.data
  const series = trend.data ?? []

  const bookings30 = series.reduce((s, d) => s + Number(d.bookings ?? 0), 0)
  const revenue30 = series.reduce((s, d) => s + Number(d.revenue ?? 0), 0)

  return (
    <div>
      <PageHeader
        title="Overview"
        description="Queues waiting on ops, and where the platform stands today"
      />

      <PageBody>
        {metrics.isError && <ErrorState what="metrics" error={metrics.error} />}

        {/* ── Needs attention ─────────────────────────────────────────────── */}
        <section className="space-y-3">
          <SectionHeading hint="Click through to act">Needs attention</SectionHeading>
          <StatGrid>
            {metrics.isLoading && [0, 1, 2, 3].map(i => <Pulse key={i} className="h-[116px]" />)}
            {m && (
              <>
                <StatTile
                  to="/verification" icon={ShieldCheck} tone="warning"
                  label="Doctors awaiting verification" value={m.doctors.pending}
                />
                <StatTile
                  to="/senior-review" icon={ClipboardList} tone="warning"
                  label="Procedure bills under review" value={m.queues.bills_under_review}
                />
                <StatTile
                  to="/complaints" icon={MessageSquare} tone="critical"
                  label="Complaints open" value={m.queues.complaints_open}
                />
                <StatTile
                  to="/bookings" icon={BookOpen} tone="neutral"
                  label="Bookings awaiting a doctor" value={m.bookings.requested}
                />
              </>
            )}
          </StatGrid>
        </section>

        {/* ── Trend. Two measures, two scales, so two charts — never a
             second y-axis on one. ───────────────────────────────────────── */}
        <section className="space-y-3">
          <SectionHeading hint="Last 30 days">
            <span className="inline-flex items-center gap-1.5">
              <Activity size={14} className="text-muted-foreground" />
              Activity
            </span>
          </SectionHeading>

          <div className="grid gap-3 lg:grid-cols-2">
            <Card>
              <CardContent className="space-y-3 p-4">
                <div>
                  <p className="text-xs text-muted-foreground">Bookings created per day</p>
                  <p className="text-2xl font-semibold tabular-nums">{bookings30}</p>
                </div>
                {trend.isLoading
                  ? <Pulse className="h-[180px]" />
                  : <TrendArea
                      data={series} dataKey="bookings" color={SERIES.blue}
                      label="Bookings" formatValue={n => String(n)}
                    />}
              </CardContent>
            </Card>

            <Card>
              <CardContent className="space-y-3 p-4">
                <div>
                  <p className="text-xs text-muted-foreground">Consult revenue per day</p>
                  <p className="text-2xl font-semibold tabular-nums">{money(revenue30)}</p>
                </div>
                {trend.isLoading
                  ? <Pulse className="h-[180px]" />
                  : <TrendArea
                      data={series} dataKey="revenue" color={SERIES.aqua}
                      label="Revenue" formatValue={compactMoney}
                    />}
              </CardContent>
            </Card>
          </div>
        </section>

        {/* ── Money ───────────────────────────────────────────────────────── */}
        <section className="space-y-3">
          <SectionHeading hint="All time">Money</SectionHeading>
          <div className="grid gap-3 lg:grid-cols-2">
            <Card>
              <CardContent className="space-y-4 p-4">
                <div>
                  <p className="text-xs text-muted-foreground">Gross booked</p>
                  <p className="text-3xl font-semibold tabular-nums">
                    {m ? money(m.revenue.consult_gross + m.revenue.procedure_gross) : '—'}
                  </p>
                </div>
                {metrics.isLoading ? <Pulse className="h-16" /> : m && (
                  <CompositionBar
                    format={money}
                    segments={[
                      { name: 'Consults',   value: m.revenue.consult_gross,   color: SERIES.blue },
                      { name: 'Procedures', value: m.revenue.procedure_gross, color: SERIES.orange },
                    ]}
                  />
                )}
              </CardContent>
            </Card>

            <Card>
              <CardContent className="space-y-4 p-4">
                <div>
                  <p className="text-xs text-muted-foreground">Ledger</p>
                  <p className="text-3xl font-semibold tabular-nums">
                    {m ? money(m.revenue.commission_earned + m.revenue.owed_to_doctors) : '—'}
                  </p>
                </div>
                {metrics.isLoading ? <Pulse className="h-16" /> : m && (
                  <CompositionBar
                    format={money}
                    segments={[
                      { name: 'Commission', value: m.revenue.commission_earned, color: SERIES.aqua },
                      { name: 'Owed to doctors', value: m.revenue.owed_to_doctors, color: SERIES.yellow },
                    ]}
                  />
                )}
              </CardContent>
            </Card>
          </div>
        </section>

        {/* ── Breakdowns ──────────────────────────────────────────────────── */}
        <div className="grid gap-3 lg:grid-cols-2">
          <Card>
            <CardContent className="space-y-4 p-4">
              <SectionHeading hint={m ? `${m.bookings.total} total` : undefined}>
                Booking funnel
              </SectionHeading>
              {metrics.isLoading ? <Pulse className="h-[200px]" /> : m && (
                <FunnelBars
                  rows={[
                    { label: 'Requested', value: m.bookings.requested },
                    { label: 'Accepted',  value: m.bookings.accepted },
                    { label: 'Paid',      value: m.bookings.paid },
                    { label: 'Completed', value: m.bookings.completed, tone: 'good' },
                    { label: 'Cancelled', value: m.bookings.cancelled, tone: 'bad' },
                    { label: 'Declined',  value: m.bookings.declined,  tone: 'bad' },
                    { label: 'No-show',   value: m.bookings.no_show,   tone: 'bad' },
                  ]}
                />
              )}
            </CardContent>
          </Card>

          <Card>
            <CardContent className="space-y-4 p-4">
              <SectionHeading hint={m ? `${m.doctors.total} total` : undefined}>
                Doctor roster
              </SectionHeading>
              {metrics.isLoading ? <Pulse className="h-[200px]" /> : m && (
                <>
                  <CompositionBar
                    format={n => String(n)}
                    segments={[
                      { name: 'Verified', value: m.doctors.verified, color: SERIES.aqua },
                      { name: 'Pending',  value: m.doctors.pending,  color: SERIES.yellow },
                      { name: 'Rejected', value: m.doctors.rejected, color: SERIES.orange },
                    ]}
                  />
                  {m.doctors.suspended > 0 && (
                    <Link
                      to="/directory"
                      className="inline-flex items-center gap-1.5 rounded-pill bg-destructive/10 px-2.5 py-1.5 text-sm text-destructive hover:bg-destructive/15"
                    >
                      <Ban size={14} />
                      {m.doctors.suspended} suspended
                      <ArrowRight size={13} />
                    </Link>
                  )}
                </>
              )}
            </CardContent>
          </Card>
        </div>

        {/* ── Audit log ───────────────────────────────────────────────────── */}
        <section className="space-y-3">
          <SectionHeading hint="Most recent first">
            <span className="inline-flex items-center gap-1.5">
              <ScrollText size={14} className="text-muted-foreground" />
              Recent ops activity
            </span>
          </SectionHeading>
          <Card>
            <CardContent className="p-0">
              {audit.isLoading && (
                <div className="space-y-2 p-4">
                  {[0, 1, 2, 3, 4].map(i => <Pulse key={i} className="h-4" />)}
                </div>
              )}
              {audit.isError && (
                <p className="p-4 text-sm text-destructive">
                  Failed to load the audit log: {(audit.error as Error).message}
                </p>
              )}
              {audit.data?.length === 0 && (
                <p className="p-4 text-sm text-muted-foreground">No ops actions recorded yet.</p>
              )}
              {audit.data && audit.data.length > 0 && (
                <ul className="divide-y">
                  {audit.data.map(e => (
                    <li
                      key={e.id}
                      className="flex items-center gap-3 px-4 py-2.5 text-sm transition-colors hover:bg-muted/50"
                    >
                      <MetaChip>{e.actor_role ?? 'system'}</MetaChip>
                      <span className="font-medium">{e.action}</span>
                      <span className="truncate text-muted-foreground">
                        {e.entity}
                        {e.entity_id && (
                          <span className="ml-1 font-mono text-xs">{e.entity_id.slice(0, 8)}</span>
                        )}
                      </span>
                      <span className="ml-auto shrink-0 text-xs tabular-nums text-muted-foreground">
                        {format(parseISO(e.at), 'd MMM, HH:mm')}
                      </span>
                    </li>
                  ))}
                </ul>
              )}
            </CardContent>
          </Card>
        </section>
      </PageBody>
    </div>
  )
}
