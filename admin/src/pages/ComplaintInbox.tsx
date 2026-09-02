import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { format } from 'date-fns'
import { api } from '@/lib/api'
import { Badge } from '@/components/ui/badge'
import { Card } from '@/components/ui/card'

type ComplaintStatus = 'open' | 'in_review' | 'resolved' | 'closed'

type Complaint = {
  id: string
  description: string
  status: ComplaintStatus
  created_at: string
  bookings: { id: string; patient_id: string; doctor_id: string }
}

type StatusFilter = 'all' | ComplaintStatus

const STATUS_TABS: { label: string; value: StatusFilter }[] = [
  { label: 'All', value: 'all' },
  { label: 'Open', value: 'open' },
  { label: 'In Review', value: 'in_review' },
  { label: 'Resolved', value: 'resolved' },
  { label: 'Closed', value: 'closed' },
]

const STATUS_BADGE: Record<ComplaintStatus, 'danger' | 'warning' | 'success' | 'muted'> = {
  open: 'danger',
  in_review: 'warning',
  resolved: 'success',
  closed: 'muted',
}

const STATUS_LABEL: Record<ComplaintStatus, string> = {
  open: 'Open',
  in_review: 'In Review',
  resolved: 'Resolved',
  closed: 'Closed',
}

const STATUS_OPTIONS: ComplaintStatus[] = ['open', 'in_review', 'resolved', 'closed']

function truncate(text: string, max = 120) {
  return text.length > max ? text.slice(0, max) + '…' : text
}

export default function ComplaintInbox() {
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all')
  const queryClient = useQueryClient()

  const { data: complaints = [], isLoading, isError } = useQuery<Complaint[]>({
    queryKey: ['admin-complaints', statusFilter],
    queryFn: () =>
      api.get<Complaint[]>(
        statusFilter === 'all' ? '/admin/complaints' : `/admin/complaints?status=${statusFilter}`
      ),
  })

  async function handleStatusChange(id: string, newStatus: ComplaintStatus) {
    await api.patch(`/admin/complaints/${id}`, { status: newStatus })
    queryClient.invalidateQueries({ queryKey: ['admin-complaints'] })
  }

  return (
    <div className="space-y-6">
      <h1 className="text-xl font-semibold text-ink">Complaint Inbox</h1>

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

      {/* States */}
      {isLoading ? (
        <p className="text-sm text-ink-muted py-8 text-center">Loading complaints…</p>
      ) : isError ? (
        <p className="text-sm text-danger py-8 text-center">Failed to load complaints.</p>
      ) : complaints.length === 0 ? (
        <p className="text-sm text-ink-muted py-8 text-center">No complaints found.</p>
      ) : (
        <div className="space-y-3">
          {complaints.map((c) => (
            <Card key={c.id} className="flex flex-col gap-3">
              <div className="flex items-start justify-between gap-4">
                <div className="flex flex-col gap-1 min-w-0">
                  <div className="flex items-center gap-3">
                    <span className="font-mono text-xs text-ink-muted">
                      Booking {c.bookings?.id?.slice(0, 8) ?? '—'}
                    </span>
                    <Badge label={STATUS_LABEL[c.status]} variant={STATUS_BADGE[c.status]} />
                  </div>
                  <p className="text-sm text-ink leading-relaxed">
                    {truncate(c.description)}
                  </p>
                  <p className="text-xs text-ink-muted">
                    {format(new Date(c.created_at), 'd MMM yyyy')}
                  </p>
                </div>

                {/* Status update */}
                <select
                  defaultValue={c.status}
                  onChange={(e) => handleStatusChange(c.id, e.target.value as ComplaintStatus)}
                  className="shrink-0 rounded-btn border border-border bg-bg px-2 py-1.5 text-xs text-ink focus:outline-none focus:ring-1 focus:ring-primary"
                >
                  {STATUS_OPTIONS.map((s) => (
                    <option key={s} value={s}>
                      {STATUS_LABEL[s]}
                    </option>
                  ))}
                </select>
              </div>
            </Card>
          ))}
        </div>
      )}
    </div>
  )
}
