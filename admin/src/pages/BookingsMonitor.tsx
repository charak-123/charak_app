import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { format } from 'date-fns'
import { api } from '@/lib/api'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent } from '@/components/ui/card'
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'

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

const STAT_CARDS: {
  label: string
  key: Booking['status']
  dotClass: string
}[] = [
  { label: 'Requested', key: 'requested', dotClass: 'bg-warning' },
  { label: 'Accepted', key: 'accepted', dotClass: 'bg-primary' },
  { label: 'Paid', key: 'paid', dotClass: 'bg-success' },
  { label: 'Completed', key: 'completed', dotClass: 'bg-muted-foreground' },
  { label: 'Cancelled', key: 'cancelled', dotClass: 'bg-destructive' },
]

function StatusBadge({ status }: { status: Booking['status'] }) {
  switch (status) {
    case 'requested':
      return (
        <Badge variant="outline" className="border-warning text-warning">
          Requested
        </Badge>
      )
    case 'accepted':
      return <Badge>Accepted</Badge>
    case 'paid':
      return (
        <Badge variant="outline" className="border-success text-success">
          Paid
        </Badge>
      )
    case 'completed':
      return <Badge variant="secondary">Completed</Badge>
    case 'cancelled':
    case 'declined':
      return <Badge variant="destructive">Cancelled</Badge>
    default:
      return <Badge variant="secondary">{status}</Badge>
  }
}

export default function BookingsMonitor() {
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all')

  const { data: bookings = [], isLoading, isError } = useQuery<Booking[]>({
    queryKey: ['admin-bookings', statusFilter],
    queryFn: () =>
      api.get<Booking[]>(
        statusFilter === 'all' ? '/admin/bookings' : `/admin/bookings?status=${statusFilter}`
      ),
  })

  const countByStatus = (status: Booking['status']) =>
    bookings.filter(b => b.status === status).length

  return (
    <div>
      <div className="p-6 border-b bg-background">
        <h1 className="text-xl font-semibold">Bookings Monitor</h1>
        <p className="text-sm text-muted-foreground">Real-time overview of all patient bookings</p>
      </div>

      <div className="p-6 space-y-6">
        {/* Stat cards */}
        <div className="grid grid-cols-5 gap-4 mb-6">
          {STAT_CARDS.map(({ label, key, dotClass }) => (
            <Card key={key}>
              <CardContent className="p-4 space-y-1">
                <div className="flex items-center gap-2">
                  <span className={`h-2.5 w-2.5 rounded-full ${dotClass}`} />
                  <span className="text-xs text-muted-foreground">{label}</span>
                </div>
                <p className="text-2xl font-bold">
                  {isLoading ? '—' : countByStatus(key)}
                </p>
              </CardContent>
            </Card>
          ))}
        </div>

        {/* Filter tabs */}
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
                <p className="text-sm text-muted-foreground py-8 text-center">Loading bookings…</p>
              ) : isError ? (
                <p className="text-sm text-destructive py-8 text-center">Failed to load bookings.</p>
              ) : bookings.length === 0 ? (
                <p className="text-sm text-muted-foreground py-8 text-center">No bookings found.</p>
              ) : (
                <div className="rounded-md border">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>ID</TableHead>
                        <TableHead>Patient</TableHead>
                        <TableHead>Doctor</TableHead>
                        <TableHead>Channel</TableHead>
                        <TableHead>Scheduled</TableHead>
                        <TableHead>Status</TableHead>
                        <TableHead>Created</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {bookings.map(b => (
                        <TableRow key={b.id}>
                          <TableCell className="font-mono text-xs">{b.id.slice(0, 8)}</TableCell>
                          <TableCell>
                            <div className="font-medium">{b.users?.name ?? '—'}</div>
                            <div className="text-xs text-muted-foreground">{b.users?.phone ?? ''}</div>
                          </TableCell>
                          <TableCell>{b.doctors?.name ?? '—'}</TableCell>
                          <TableCell>
                            {b.channel === 'home_visit' ? 'Home Visit' : 'Online'}
                          </TableCell>
                          <TableCell className="whitespace-nowrap">
                            {b.scheduled_at
                              ? format(new Date(b.scheduled_at), 'd MMM, HH:mm')
                              : '—'}
                          </TableCell>
                          <TableCell>
                            <StatusBadge status={b.status} />
                          </TableCell>
                          <TableCell className="whitespace-nowrap text-muted-foreground">
                            {format(new Date(b.created_at), 'd MMM yyyy')}
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </div>
              )}
            </TabsContent>
          ))}
        </Tabs>
      </div>
    </div>
  )
}
