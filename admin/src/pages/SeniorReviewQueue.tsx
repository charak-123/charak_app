import { useQuery, useQueryClient } from '@tanstack/react-query'
import { PackageCheck } from 'lucide-react'
import { api } from '@/lib/api'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Separator } from '@/components/ui/separator'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'

type BillItem = {
  name: string
  qty: number
  price: number
}

type ProcedureBill = {
  id: string
  booking_id: string
  total_amount: number
  status: string
  items: BillItem[]
  bookings: {
    id: string
    doctor_id: string
    doctors: { name: string }
  }
}

export default function SeniorReviewQueue() {
  const queryClient = useQueryClient()

  const { data: bills = [], isLoading, isError } = useQuery<ProcedureBill[]>({
    queryKey: ['admin-procedure-bills-review'],
    queryFn: () => api.get<ProcedureBill[]>('/admin/procedure-bills/review'),
  })

  async function handleApprove(bill: ProcedureBill) {
    await api.patch(`/bookings/${bill.booking_id}/procedure-bill/approve`, {})
    queryClient.invalidateQueries({ queryKey: ['admin-procedure-bills-review'] })
  }

  async function handleFlag(bill: ProcedureBill) {
    await api.patch(`/bookings/${bill.booking_id}/procedure-bill/flag`, {})
    queryClient.invalidateQueries({ queryKey: ['admin-procedure-bills-review'] })
  }

  return (
    <div>
      <div className="p-6 border-b bg-background">
        <h1 className="text-xl font-semibold">Senior Review</h1>
        <p className="text-sm text-muted-foreground">
          Procedure bills pending senior approval
        </p>
      </div>

      <div className="p-6 space-y-4">
        {isLoading ? (
          <p className="text-sm text-muted-foreground py-8 text-center">Loading bills…</p>
        ) : isError ? (
          <p className="text-sm text-destructive py-8 text-center">
            Failed to load procedure bills.
          </p>
        ) : bills.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 gap-3">
            <PackageCheck size={48} className="text-muted-foreground" />
            <p className="text-base font-semibold">No bills pending review</p>
          </div>
        ) : (
          <div className="space-y-4">
            {bills.map(bill => {
              const items: BillItem[] = Array.isArray(bill.items) ? bill.items : []
              const doctorName = bill.bookings?.doctors?.name ?? '—'

              return (
                <Card key={bill.id}>
                  <CardHeader className="pb-3">
                    <div className="flex items-start justify-between gap-4">
                      <div className="space-y-1">
                        <div className="flex items-center gap-2">
                          <CardTitle className="text-sm font-mono font-medium text-muted-foreground">
                            Bill {bill.id.slice(0, 8)}
                          </CardTitle>
                          <Badge
                            variant="outline"
                            className="border-warning text-warning bg-warning/10"
                          >
                            Under Review
                          </Badge>
                        </div>
                        <p className="text-sm font-semibold">{doctorName}</p>
                      </div>

                      {/* Action buttons */}
                      <div className="flex gap-2 shrink-0">
                        <Button
                          className="bg-success hover:bg-success/90 text-white"
                          onClick={() => handleApprove(bill)}
                        >
                          Approve
                        </Button>
                        <Button variant="destructive" onClick={() => handleFlag(bill)}>
                          Flag
                        </Button>
                      </div>
                    </div>
                  </CardHeader>

                  <CardContent className="space-y-4">
                    {/* Line items table */}
                    {items.length > 0 && (
                      <div className="rounded-md border">
                        <Table>
                          <TableHeader>
                            <TableRow>
                              <TableHead>Name</TableHead>
                              <TableHead className="text-right">Qty</TableHead>
                              <TableHead className="text-right">Price</TableHead>
                              <TableHead className="text-right">Subtotal</TableHead>
                            </TableRow>
                          </TableHeader>
                          <TableBody>
                            {items.map((item, i) => (
                              <TableRow key={i}>
                                <TableCell>{item.name}</TableCell>
                                <TableCell className="text-right text-muted-foreground">
                                  {item.qty}
                                </TableCell>
                                <TableCell className="text-right text-muted-foreground">
                                  ₹{item.price.toLocaleString('en-IN')}
                                </TableCell>
                                <TableCell className="text-right">
                                  ₹{(item.qty * item.price).toLocaleString('en-IN')}
                                </TableCell>
                              </TableRow>
                            ))}
                          </TableBody>
                        </Table>
                      </div>
                    )}

                    <Separator />

                    {/* Total row */}
                    <div className="flex justify-between items-center">
                      <span className="text-sm text-muted-foreground">Total</span>
                      <span className="text-sm font-bold">
                        ₹{bill.total_amount.toLocaleString('en-IN')}
                      </span>
                    </div>
                  </CardContent>
                </Card>
              )
            })}
          </div>
        )}
      </div>
    </div>
  )
}
