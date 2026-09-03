import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { format } from 'date-fns'
import { api } from '@/lib/api'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent } from '@/components/ui/card'
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'

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

const STATUS_LABEL: Record<ComplaintStatus, string> = {
  open: 'Open',
  in_review: 'In Review',
  resolved: 'Resolved',
  closed: 'Closed',
}

const STATUS_OPTIONS: ComplaintStatus[] = ['open', 'in_review', 'resolved', 'closed']

function ComplaintStatusBadge({ status }: { status: ComplaintStatus }) {
  switch (status) {
    case 'open':
      return <Badge variant="destructive">Open</Badge>
    case 'in_review':
      return (
        <Badge variant="outline" className="border-warning text-warning bg-warning/10">
          In Review
        </Badge>
      )
    case 'resolved':
      return (
        <Badge variant="outline" className="border-success text-success bg-success/10">
          Resolved
        </Badge>
      )
    case 'closed':
      return <Badge variant="secondary">Closed</Badge>
  }
}

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
    <div>
      <div className="p-6 border-b bg-background">
        <h1 className="text-xl font-semibold">Complaint Inbox</h1>
        <p className="text-sm text-muted-foreground">Manage and resolve patient complaints</p>
      </div>

      <div className="p-6 space-y-4">
        <Tabs value={statusFilter} onValueChange={v => setStatusFilter(v as StatusFilter)}>
          <TabsList>
            {STATUS_TABS.map(({ label, value }) => (
              <TabsTrigger key={value} value={value}>
                {label}
              </TabsTrigger>
            ))}
          </TabsList>

          {STATUS_TABS.map(({ value }) => (
            <TabsContent key={value} value={value} className="mt-4">
              {isLoading ? (
                <p className="text-sm text-muted-foreground py-8 text-center">
                  Loading complaints…
                </p>
              ) : isError ? (
                <p className="text-sm text-destructive py-8 text-center">
                  Failed to load complaints.
                </p>
              ) : complaints.length === 0 ? (
                <p className="text-sm text-muted-foreground py-8 text-center">
                  No complaints found.
                </p>
              ) : (
                <div className="space-y-3">
                  {complaints.map(c => (
                    <Card key={c.id}>
                      <CardContent className="p-4 space-y-3">
                        {/* Top row: booking ID chip + status badge + date */}
                        <div className="flex items-center justify-between gap-4 flex-wrap">
                          <div className="flex items-center gap-2 flex-wrap">
                            <Badge variant="secondary" className="font-mono text-xs">
                              Booking {c.bookings?.id?.slice(0, 8) ?? '—'}
                            </Badge>
                            <ComplaintStatusBadge status={c.status} />
                            <span className="text-xs text-muted-foreground">
                              {format(new Date(c.created_at), 'd MMM yyyy')}
                            </span>
                          </div>
                        </div>

                        {/* Description */}
                        <p className="text-sm leading-relaxed">{truncate(c.description)}</p>

                        {/* Status update select */}
                        <div className="flex items-center gap-2">
                          <span className="text-xs text-muted-foreground">Update status:</span>
                          <Select
                            defaultValue={c.status}
                            onValueChange={v =>
                              handleStatusChange(c.id, v as ComplaintStatus)
                            }
                          >
                            <SelectTrigger className="h-8 w-36 text-xs">
                              <SelectValue />
                            </SelectTrigger>
                            <SelectContent>
                              {STATUS_OPTIONS.map(s => (
                                <SelectItem key={s} value={s} className="text-xs">
                                  {STATUS_LABEL[s]}
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
            </TabsContent>
          ))}
        </Tabs>
      </div>
    </div>
  )
}
