import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { format } from 'date-fns'
import { MessageSquare, AlertCircle, Clock, CheckCircle2 } from 'lucide-react'
import { api } from '@/lib/api'
import { Card, CardContent } from '@/components/ui/card'
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs'
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select'
import {
  PageBody, PageHeader, Section, StatGrid, StatTile, Toolbar,
  EmptyState, ErrorState, ListSkeleton,
} from '@/components/shell'
import { MetaChip, StatusPill, statusLabel } from '@/components/status'

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
  { label: 'All',       value: 'all' },
  { label: 'Open',      value: 'open' },
  { label: 'In Review', value: 'in_review' },
  { label: 'Resolved',  value: 'resolved' },
  { label: 'Closed',    value: 'closed' },
]

const STATUS_OPTIONS: ComplaintStatus[] = ['open', 'in_review', 'resolved', 'closed']

export default function ComplaintInbox() {
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all')
  const queryClient = useQueryClient()

  // The summary strip describes the whole inbox, not the current filter, so the
  // numbers stay put when you switch tabs.
  const all = useQuery<Complaint[]>({
    queryKey: ['admin-complaints', 'all'],
    queryFn: () => api.get<Complaint[]>('/admin/complaints'),
  })

  const { data: complaints = [], isLoading, isError, error } = useQuery<Complaint[]>({
    queryKey: ['admin-complaints', statusFilter],
    queryFn: () =>
      api.get<Complaint[]>(
        statusFilter === 'all' ? '/admin/complaints' : `/admin/complaints?status=${statusFilter}`
      ),
  })

  const rows = all.data ?? []
  const count = (s: ComplaintStatus) => rows.filter(c => c.status === s).length

  async function handleStatusChange(id: string, newStatus: ComplaintStatus) {
    await api.patch(`/admin/complaints/${id}`, { status: newStatus })
    queryClient.invalidateQueries({ queryKey: ['admin-complaints'] })
  }

  return (
    <div>
      <PageHeader
        title="Complaints"
        description="Patient complaints raised against a booking"
      />

      <PageBody>
        <Section title="At a glance" hint={`${rows.length} total`}>
          <StatGrid>
            <StatTile
              icon={AlertCircle} tone="critical" value={count('open')}
              label="Open" hint="Not yet picked up"
            />
            <StatTile
              icon={Clock} tone="warning" value={count('in_review')}
              label="In review"
            />
            <StatTile
              icon={CheckCircle2} tone="good" value={count('resolved')}
              label="Resolved"
            />
            <StatTile
              icon={MessageSquare} tone="neutral" value={count('closed')}
              label="Closed"
            />
          </StatGrid>
        </Section>

        <Section title="Inbox" hint={`${complaints.length} shown`}>
          <Toolbar>
            <Tabs value={statusFilter} onValueChange={v => setStatusFilter(v as StatusFilter)}>
              <TabsList>
                {STATUS_TABS.map(({ label, value }) => (
                  <TabsTrigger key={value} value={value}>{label}</TabsTrigger>
                ))}
              </TabsList>
            </Tabs>
          </Toolbar>

          {isLoading && <ListSkeleton rows={4} height="h-16" />}
          {isError && <ErrorState what="complaints" error={error} />}
          {!isLoading && !isError && complaints.length === 0 && (
            <EmptyState
              icon={MessageSquare}
              title="Nothing in this view"
              hint="No complaints match this filter."
            />
          )}

          {!isLoading && !isError && complaints.length > 0 && (
            <div className="space-y-3">
              {complaints.map(c => (
                <Card key={c.id}>
                  <CardContent className="space-y-3 p-4">
                    <div className="flex flex-wrap items-center gap-2">
                      <StatusPill status={c.status} />
                      <MetaChip mono>Booking {c.bookings?.id?.slice(0, 8) ?? '—'}</MetaChip>
                      <span className="ml-auto text-xs text-muted-foreground">
                        {format(new Date(c.created_at), 'd MMM yyyy')}
                      </span>
                    </div>

                    <p className="text-sm leading-relaxed">{c.description}</p>

                    <div className="flex items-center gap-2 border-t pt-3">
                      <span className="text-xs text-muted-foreground">Update status</span>
                      <Select
                        defaultValue={c.status}
                        onValueChange={v => handleStatusChange(c.id, v as ComplaintStatus)}
                      >
                        <SelectTrigger className="h-8 w-36 text-xs">
                          <SelectValue>
                            {(v: unknown) => statusLabel(String(v ?? ''))}
                          </SelectValue>
                        </SelectTrigger>
                        <SelectContent>
                          {STATUS_OPTIONS.map(s => (
                            <SelectItem key={s} value={s} className="text-xs">
                              {statusLabel(s)}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                  </CardContent>
                </Card>
              ))}
            </div>
          )}
        </Section>
      </PageBody>
    </div>
  )
}
