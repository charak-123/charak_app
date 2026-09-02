import { useQuery, useQueryClient } from '@tanstack/react-query'
import { api } from '@/lib/api'
import { Badge } from '@/components/ui/badge'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'

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
    <div className="space-y-6">
      <h1 className="text-xl font-semibold text-ink">Senior Review Queue</h1>

      {isLoading ? (
        <p className="text-sm text-ink-muted py-8 text-center">Loading bills…</p>
      ) : isError ? (
        <p className="text-sm text-danger py-8 text-center">Failed to load procedure bills.</p>
      ) : bills.length === 0 ? (
        <p className="text-sm text-ink-muted py-8 text-center">No bills pending review 🎉</p>
      ) : (
        <div className="space-y-4">
          {bills.map((bill) => {
            const items: BillItem[] = Array.isArray(bill.items) ? bill.items : []
            const doctorName = bill.bookings?.doctors?.name ?? '—'
            const bookingShort = bill.bookings?.id?.slice(0, 8) ?? '—'

            return (
              <Card key={bill.id} className="space-y-4">
                {/* Header row */}
                <div className="flex items-start justify-between gap-4">
                  <div className="space-y-1">
                    <div className="flex items-center gap-3">
                      <span className="font-mono text-xs text-ink-muted">
                        Bill {bill.id.slice(0, 8)}
                      </span>
                      <Badge label="Under Review" variant="warning" />
                    </div>
                    <div className="text-sm text-ink">
                      <span className="font-medium">{doctorName}</span>
                      <span className="text-ink-muted"> · Booking </span>
                      <span className="font-mono text-xs">{bookingShort}</span>
                    </div>
                  </div>

                  {/* Actions */}
                  <div className="flex gap-2 shrink-0">
                    <Button
                      variant="default"
                      className="bg-success hover:bg-success/90 text-white"
                      onClick={() => handleApprove(bill)}
                    >
                      Approve
                    </Button>
                    <Button variant="danger" onClick={() => handleFlag(bill)}>
                      Flag
                    </Button>
                  </div>
                </div>

                {/* Items table */}
                {items.length > 0 && (
                  <div className="rounded-card border border-border overflow-hidden">
                    <table className="w-full text-sm">
                      <thead className="bg-bg-subtle text-xs text-ink-muted uppercase">
                        <tr>
                          {['Item', 'Qty', 'Price', 'Subtotal'].map((h) => (
                            <th
                              key={h}
                              className={`px-3 py-2 font-medium ${h === 'Item' ? 'text-left' : 'text-right'}`}
                            >
                              {h}
                            </th>
                          ))}
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-border bg-white">
                        {items.map((item, i) => (
                          <tr key={i}>
                            <td className="px-3 py-2 text-ink">{item.name}</td>
                            <td className="px-3 py-2 text-right text-ink-muted">{item.qty}</td>
                            <td className="px-3 py-2 text-right text-ink-muted">
                              ₹{item.price.toLocaleString('en-IN')}
                            </td>
                            <td className="px-3 py-2 text-right text-ink">
                              ₹{(item.qty * item.price).toLocaleString('en-IN')}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}

                {/* Total */}
                <div className="flex justify-end">
                  <span className="text-sm font-bold text-ink">
                    Total: ₹{bill.total_amount.toLocaleString('en-IN')}
                  </span>
                </div>
              </Card>
            )
          })}
        </div>
      )}
    </div>
  )
}
