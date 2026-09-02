import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { format } from 'date-fns'
import { api } from '@/lib/api'
import { Badge } from '@/components/ui/badge'
import { Card } from '@/components/ui/card'

type Booking = {
  id: string
  channel: 'online' | 'home_visit'
  scheduled_at: string
  status: 'requested' | 'accepted' | 'paid' | 'completed' | 'cancelled' | 'declined'
  created_at: string
  users: { name: string; phone: string }
  doctors: { name: string }
}

type StatusFilter = 'all' | 'requested' | 'accepted' | 'paid' | 'completed' | 'cancelled'

const STATUS_TABS: { label: string; value: StatusFilter }[] = [
  { label: 'All', value: 'all' },
  { label: 'Requested', value: 'requested' },
  { label: 'Accepted', value: 'accepted' },
  { label: 'Paid', value: 'paid' },
  { label: 'Completed', value: 'completed' },
  { label: 'Cancelled', value: 'cancelled' },
]

const STATUS_BADGE: Record<Booking['status'], 'warning' | 'default' | 'success' | 'muted' | 'danger'> = {
  requested: 'warning',
  accepted: 'default',
  paid: 'success',
  completed: 'muted',
  cancelled: 'danger',
  declined: 'danger',
}

const STAT_CARDS: { label: string; key: Booking['status']; dot: string }[] = [
  { label: 'Requested', key: 'requested', dot: 'bg-warning' },
  { label: 'Accepted', key: 'accepted', dot: 'bg-primary' },
  { label: 'Paid', key: 'paid', dot: 'bg-success' },
  { label: 'Completed', key: 'completed', dot: 'bg-ink-muted' },
  { label: 'Cancelled', key: 'cancelled', dot: 'bg-danger' },
]

export default function BookingsMonitor() {
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all')

  const { data: bookings = [], isLoading, isError } = useQuery<Booking[]>({
    queryKey: ['admin-bookings', statusFilter],
    queryFn: () =>
      api.get<Booking[]>(statusFilter === 'all' ? '/admin/bookings' : `/admin/bookings?status=${statusFilter}`),
  })

  const countByStatus = (status: Booking['status']) =>
    bookings.filter((b) => b.status === status).length

  return (
    <div className="space-y-6">
      <h1 className="text-xl font-semibold text-ink">Bookings Monitor</h1>

      {/* Stat cards */}
      <div className="grid grid-cols-5 gap-4">
        {STAT_CARDS.map(({ label, key, dot }) => (
          <Card key={key} className="flex flex-col gap-1">
            <div className="flex items-center gap-2">
              <span className={`h-2.5 w-2.5 rounded-full ${dot}`} />
              <span className="text-xs text-ink-muted">{label}</span>
            </div>
            <p className="text-2xl font-bold text-ink">
              {isLoading ? '—' : countByStatus(key)}
            </p>
          </Card>
        ))}
      </div>

      {/* Filter tabs */}
      <div className="flex gap-1 border-b border-border">
        {STATUS_TABS.map(({ label, value }) => (
          <button
            key={value}
            onClick={() => setStatusFilter(value)}
            className={`px-4 py-2 text-sm font-medium transition-colors border-b-2 -mb-px ${
              statusFilter === value
                ? 'border-primary text-primary'
                : 'border-transparent text-ink-muted hover:text-ink'
            }`}
          >
            {label}
          </button>
        ))}
      </div>

      {/* Table */}
      {isLoading ? (
        <p className="text-sm text-ink-muted py-8 text-center">Loading bookings…</p>
      ) : isError ? (
        <p className="text-sm text-danger py-8 text-center">Failed to load bookings.</p>
      ) : bookings.length === 0 ? (
        <p className="text-sm text-ink-muted py-8 text-center">No bookings found.</p>
      ) : (
        <div className="overflow-x-auto rounded-card border border-border">
          <table className="w-full text-sm text-ink">
            <thead className="bg-bg-subtle text-xs text-ink-muted uppercase">
              <tr>
                {['Booking ID', 'Patient', 'Doctor', 'Channel', 'Scheduled', 'Status', 'Created'].map((h) => (
                  <th key={h} className="px-4 py-3 text-left font-medium">
                    {h}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-border bg-white">
              {bookings.map((b) => (
                <tr key={b.id} className="hover:bg-bg-subtle transition-colors">
                  <td className="px-4 py-3 font-mono text-xs">{b.id.slice(0, 8)}</td>
                  <td className="px-4 py-3">
                    <div className="font-medium">{b.users?.name ?? '—'}</div>
                    <div className="text-xs text-ink-muted">{b.users?.phone ?? ''}</div>
                  </td>
                  <td className="px-4 py-3">{b.doctors?.name ?? '—'}</td>
                  <td className="px-4 py-3">{b.channel === 'home_visit' ? 'Home Visit' : 'Online'}</td>
                  <td className="px-4 py-3 whitespace-nowrap">
                    {b.scheduled_at ? format(new Date(b.scheduled_at), 'd MMM, HH:mm') : '—'}
                  </td>
                  <td className="px-4 py-3">
                    <Badge label={b.status.charAt(0).toUpperCase() + b.status.slice(1)} variant={STATUS_BADGE[b.status]} />
                  </td>
                  <td className="px-4 py-3 whitespace-nowrap text-ink-muted">
                    {format(new Date(b.created_at), 'd MMM yyyy')}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
