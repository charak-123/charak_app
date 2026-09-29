import { useQuery, useQueryClient } from '@tanstack/react-query'
import { PackageCheck, ClipboardList, IndianRupee, TrendingUp } from 'lucide-react'
import { api } from '@/lib/api'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from '@/components/ui/table'
import {
  PageBody, PageHeader, Section, StatGrid, StatTile,
  EmptyState, ErrorState, ListSkeleton,
} from '@/components/shell'
import { MetaChip, StatusPill } from '@/components/status'
import { money } from '@/lib/chart-theme'

type BillItem = { name: string; qty: number; price: number }

type ProcedureBill = {
  id: string
  booking_id: string
  total_amount: number
  status: string
  items: BillItem[]
  bookings: { id: string; doctor_id: string; doctors: { name: string } }
}

export default function SeniorReviewQueue() {
  const queryClient = useQueryClient()

  const { data: bills = [], isLoading, isError, error } = useQuery<ProcedureBill[]>({
    queryKey: ['admin-procedure-bills-review'],
    queryFn: () => api.get<ProcedureBill[]>('/admin/procedure-bills/review'),
  })

  function invalidate() {
    queryClient.invalidateQueries({ queryKey: ['admin-procedure-bills-review'] })
    queryClient.invalidateQueries({ queryKey: ['admin-metrics'] })
  }

  async function handleApprove(bill: ProcedureBill) {
    await api.patch(`/bookings/${bill.booking_id}/procedure-bill/approve`, {})
    invalidate()
  }

  async function handleFlag(bill: ProcedureBill) {
    await api.patch(`/bookings/${bill.booking_id}/procedure-bill/flag`, {})
    invalidate()
  }

  const pendingValue = bills.reduce((s, b) => s + Number(b.total_amount ?? 0), 0)
  const largest = bills.reduce((m, b) => Math.max(m, Number(b.total_amount ?? 0)), 0)
  const lineItems = bills.reduce(
    (s, b) => s + (Array.isArray(b.items) ? b.items.length : 0), 0,
  )

  return (
    <div>
      <PageHeader
        title="Senior Review"
        description="Procedure bills held for senior approval before capture"
      />

      <PageBody>
        <Section title="At a glance" hint={`${bills.length} in queue`}>
          <StatGrid>
            <StatTile
              icon={ClipboardList} tone="warning" value={bills.length}
              label="Bills awaiting review"
            />
            <StatTile
              icon={IndianRupee} tone="warning" value={money(pendingValue)}
              label="Value on hold"
            />
            <StatTile
              icon={TrendingUp} tone="neutral" value={money(largest)}
              label="Largest single bill"
            />
            <StatTile
              icon={PackageCheck} tone="neutral" value={lineItems}
              label="Line items to check"
            />
          </StatGrid>
        </Section>

        <Section title="Queue" hint="Approve releases capture">
          {isLoading && <ListSkeleton rows={3} height="h-28" />}
          {isError && <ErrorState what="procedure bills" error={error} />}
          {!isLoading && !isError && bills.length === 0 && (
            <EmptyState
              icon={PackageCheck}
              title="No bills pending review"
              hint="Nothing is waiting on a senior decision."
            />
          )}

          {!isLoading && !isError && bills.length > 0 && (
            <div className="space-y-3">
              {bills.map(bill => {
                const items: BillItem[] = Array.isArray(bill.items) ? bill.items : []
                const doctorName = bill.bookings?.doctors?.name ?? '—'

                return (
                  <Card key={bill.id}>
                    <CardContent className="space-y-3 p-4">
                      <div className="flex flex-wrap items-start justify-between gap-3">
                        <div className="space-y-1.5">
                          <div className="flex flex-wrap items-center gap-2">
                            <StatusPill status={bill.status} />
                            <MetaChip mono>Bill {bill.id.slice(0, 8)}</MetaChip>
                          </div>
                          <p className="text-sm font-semibold">{doctorName}</p>
                        </div>
                        <div className="flex shrink-0 gap-2">
                          <Button
                            size="sm"
                            className="bg-success text-white hover:bg-success/90"
                            onClick={() => handleApprove(bill)}
                          >
                            Approve
                          </Button>
                          <Button
                            size="sm" variant="outline"
                            className="text-destructive hover:bg-destructive/10"
                            onClick={() => handleFlag(bill)}
                          >
                            Flag
                          </Button>
                        </div>
                      </div>

                      {items.length > 0 && (
                        <div className="overflow-hidden rounded-lg border">
                          <Table>
                            <TableHeader>
                              <TableRow>
                                <TableHead>Item</TableHead>
                                <TableHead className="text-right">Qty</TableHead>
                                <TableHead className="text-right">Price</TableHead>
                                <TableHead className="text-right">Subtotal</TableHead>
                              </TableRow>
                            </TableHeader>
                            <TableBody>
                              {items.map((item, i) => (
                                <TableRow key={i}>
                                  <TableCell className="text-sm">{item.name}</TableCell>
                                  <TableCell className="text-right text-sm tabular-nums text-muted-foreground">
                                    {item.qty}
                                  </TableCell>
                                  <TableCell className="text-right text-sm tabular-nums text-muted-foreground">
                                    {money(item.price)}
                                  </TableCell>
                                  <TableCell className="text-right text-sm tabular-nums">
                                    {money(item.qty * item.price)}
                                  </TableCell>
                                </TableRow>
                              ))}
                            </TableBody>
                          </Table>
                        </div>
                      )}

                      <div className="flex items-center justify-between border-t pt-3">
                        <span className="text-sm text-muted-foreground">Total</span>
                        <span className="text-base font-semibold tabular-nums">
                          {money(bill.total_amount)}
                        </span>
                      </div>
                    </CardContent>
                  </Card>
                )
              })}
            </div>
          )}
        </Section>
      </PageBody>
    </div>
  )
}
