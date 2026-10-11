import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { format } from 'date-fns'
import { BookOpen, CalendarClock, CheckCircle2, IndianRupee, Eye } from 'lucide-react'
import { api } from '@/lib/api'
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs'
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from '@/components/ui/table'
import {
  PageBody, PageHeader, Section, StatGrid, StatTile, Toolbar,
  EmptyState, ErrorState, ListSkeleton, TableCard,
} from '@/components/shell'
import { MetaChip, StatusPill } from '@/components/status'
import FunnelBars from '@/components/charts/FunnelBars'
import { money } from '@/lib/chart-theme'

type BookingStatus =
  | 'requested' | 'accepted' | 'paid' | 'completed' | 'cancelled' | 'declined' | 'no_show'

type Booking = {
  id: string
  channel: 'online_consult' | 'home_visit'
  scheduled_start: string
  status: BookingStatus
  created_at: string
  price_confirmed?: number | null
  users: { name: string; phone: string | null }
  doctors: { name: string }
}

type StatusFilter = 'all' | BookingStatus

const STATUS_TABS: { label: string; value: StatusFilter }[] = [
  { label: 'All',       value: 'all' },
  { label: 'Requested', value: 'requested' },
  { label: 'Accepted',  value: 'accepted' },
  { label: 'Paid',      value: 'paid' },
  { label: 'Completed', value: 'completed' },
  { label: 'Cancelled', value: 'cancelled' },
]

export default function BookingsMonitor() {
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all')
  const [revealed, setRevealed] = useState<Record<string, string>>({})
  const queryClient = useQueryClient()

  const revealPhone = useMutation({
    mutationFn: (bookingId: string) =>
      api.get<{ phone: string | null }>(`/admin/bookings/${bookingId}/phone`),
    onSuccess: (data, bookingId) => {
      setRevealed(r => ({ ...r, [bookingId]: data.phone ?? '—' }))
      queryClient.invalidateQueries({ queryKey: ['audit-log'] })
    },
  })

  // The summary strip always describes the whole book, not the current filter,
  // so the numbers don't move when you change tabs.
  const all = useQuery<Booking[]>({
    queryKey: ['admin-bookings', 'all'],
    queryFn: () => api.get<Booking[]>('/admin/bookings'),
  })

  const { data: bookings = [], isLoading, isError, error } = useQuery<Booking[]>({
    queryKey: ['admin-bookings', statusFilter],
    queryFn: () =>
      api.get<Booking[]>(
        statusFilter === 'all' ? '/admin/bookings' : `/admin/bookings?status=${statusFilter}`
      ),
  })

  const rows = all.data ?? []
  const count = (s: BookingStatus) => rows.filter(b => b.status === s).length
  const revenue = rows
    .filter(b => b.status === 'paid' || b.status === 'completed')
    .reduce((s, b) => s + Number(b.price_confirmed ?? 0), 0)

  return (
    <div>
      <PageHeader
        title="Bookings"
        description="Every consult and home visit moving through the platform"
      />

      <PageBody>
        <Section title="At a glance" hint={`${rows.length} total`}>
          <StatGrid>
            <StatTile
              icon={CalendarClock} tone="warning" value={count('requested')}
              label="Awaiting a doctor"
            />
            <StatTile
              icon={BookOpen} tone="neutral" value={count('accepted')}
              label="Accepted, not yet paid"
            />
            <StatTile
              icon={CheckCircle2} tone="good" value={count('completed')}
              label="Completed"
            />
            <StatTile
              icon={IndianRupee} tone="good" value={money(revenue)}
              label="Consult revenue" hint="Paid and completed"
            />
          </StatGrid>
        </Section>

        <Section title="Funnel" hint="Where the book stands">
          <div className="rounded-card bg-card p-4">
            <FunnelBars
              rows={[
                { label: 'Requested', value: count('requested') },
                { label: 'Accepted',  value: count('accepted') },
                { label: 'Paid',      value: count('paid') },
                { label: 'Completed', value: count('completed'), tone: 'good' },
                { label: 'Cancelled', value: count('cancelled'), tone: 'bad' },
                { label: 'Declined',  value: count('declined'),  tone: 'bad' },
                { label: 'No-show',   value: count('no_show'),   tone: 'bad' },
              ]}
            />
          </div>
        </Section>

        <Section title="All bookings" hint={`${bookings.length} shown`}>
          <Toolbar>
            <Tabs value={statusFilter} onValueChange={v => setStatusFilter(v as StatusFilter)}>
              <TabsList>
                {STATUS_TABS.map(({ label, value }) => (
                  <TabsTrigger key={value} value={value}>{label}</TabsTrigger>
                ))}
              </TabsList>
            </Tabs>
          </Toolbar>

          {isLoading && <ListSkeleton rows={6} />}
          {isError && <ErrorState what="bookings" error={error} />}
          {!isLoading && !isError && bookings.length === 0 && (
            <EmptyState
              icon={BookOpen}
              title="No bookings here"
              hint="Nothing matches this filter yet."
            />
          )}

          {!isLoading && !isError && bookings.length > 0 && (
            <TableCard>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>ID</TableHead>
                    <TableHead>Patient</TableHead>
                    <TableHead>Doctor</TableHead>
                    <TableHead>Channel</TableHead>
                    <TableHead>Scheduled</TableHead>
                    <TableHead>Status</TableHead>
                    <TableHead className="text-right">Created</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {bookings.map(b => (
                    <TableRow key={b.id}>
                      <TableCell><MetaChip mono>{b.id.slice(0, 8)}</MetaChip></TableCell>
                      <TableCell>
                        <p className="text-sm font-medium">{b.users?.name ?? '—'}</p>
                        <button
                          type="button"
                          disabled={!b.users?.phone || revealPhone.isPending}
                          onClick={() => revealPhone.mutate(b.id)}
                          className="flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground disabled:hover:text-muted-foreground"
                          title={revealed[b.id] ? undefined : 'Reveal — this is logged'}
                        >
                          {revealed[b.id] ?? b.users?.phone ?? ''}
                          {!revealed[b.id] && b.users?.phone && <Eye size={12} />}
                        </button>
                      </TableCell>
                      <TableCell className="text-sm">{b.doctors?.name ?? '—'}</TableCell>
                      <TableCell>
                        <MetaChip>{b.channel === 'home_visit' ? 'Home visit' : 'Online'}</MetaChip>
                      </TableCell>
                      <TableCell className="whitespace-nowrap text-sm">
                        {b.scheduled_start ? format(new Date(b.scheduled_start), 'd MMM, HH:mm') : '—'}
                      </TableCell>
                      <TableCell><StatusPill status={b.status} /></TableCell>
                      <TableCell className="whitespace-nowrap text-right text-sm text-muted-foreground">
                        {format(new Date(b.created_at), 'd MMM yyyy')}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </TableCard>
          )}
        </Section>
      </PageBody>
    </div>
  )
}
