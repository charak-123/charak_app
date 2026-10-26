import { useQuery } from '@tanstack/react-query'
import { format } from 'date-fns'
import { api } from '@/lib/api'
import {
  Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle,
} from '@/components/ui/dialog'
import { ErrorState, ListSkeleton } from '@/components/shell'
import { MetaChip } from '@/components/status'

/**
 * Every price a doctor has had (GET /admin/pricing/{id}/history), for support:
 * "what was I charged, and was that the price then?". Rows are never edited;
 * a change closes one and adds the next. A booking's price_rule_id points at
 * the row it was charged by.
 */
type Rule = {
  id: string
  channel: 'online_consult' | 'home_visit'
  visit_category: 'initial' | 'follow_up'
  duration_min: number
  price_paise: number
  effective_from: string
  effective_until: string | null
}

const inr = new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 0 })
const when = (iso: string) => format(new Date(iso), 'd MMM yyyy, h:mm a')

export default function PricingHistory({
  doctor, onClose,
}: { doctor: { id: string; name: string } | null; onClose: () => void }) {
  const { data, isLoading, isError, error } = useQuery<{ follow_up_validity_days: number | null; rules: Rule[] }>({
    queryKey: ['admin-pricing-history', doctor?.id],
    queryFn: () => api.get(`/admin/pricing/${doctor!.id}/history`),
    enabled: !!doctor,
  })
  const current = data?.rules.filter(r => !r.effective_until) ?? []
  const past = data?.rules.filter(r => r.effective_until) ?? []

  const row = (r: Rule) => (
    <div key={r.id} className="flex flex-wrap items-center gap-2 border-b py-2 text-sm last:border-0">
      <MetaChip>{r.channel === 'home_visit' ? 'Home' : 'Online'}</MetaChip>
      <MetaChip>{r.visit_category === 'follow_up' ? 'Follow-up' : 'First visit'}</MetaChip>
      <span className="tabular-nums">{r.duration_min} min</span>
      <span className="font-semibold tabular-nums">{r.price_paise === 0 ? 'Free' : inr.format(r.price_paise / 100)}</span>
      <span className="ml-auto text-xs tabular-nums text-muted-foreground">
        {when(r.effective_from)}{r.effective_until ? ` – ${when(r.effective_until)}` : ' – now'}
      </span>
    </div>
  )

  return (
    <Dialog open={!!doctor} onOpenChange={o => { if (!o) onClose() }}>
      <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-xl">
        <DialogHeader>
          <DialogTitle>Prices · {doctor?.name}</DialogTitle>
          <DialogDescription>
            Bookings keep the price they were made at. Follow-up prices apply for{' '}
            {data?.follow_up_validity_days ? `${data.follow_up_validity_days} days` : '— (none offered)'} after a visit.
          </DialogDescription>
        </DialogHeader>
        {isLoading && <ListSkeleton rows={4} />}
        {isError && <ErrorState what="pricing history" error={error} />}
        {data && (
          <>
            <p className="text-xs font-semibold uppercase text-muted-foreground">Current</p>
            {current.length ? current.map(row) : <p className="text-sm text-muted-foreground">No prices set.</p>}
            {past.length > 0 && (
              <>
                <p className="pt-3 text-xs font-semibold uppercase text-muted-foreground">Earlier</p>
                {past.map(row)}
              </>
            )}
          </>
        )}
      </DialogContent>
    </Dialog>
  )
}
