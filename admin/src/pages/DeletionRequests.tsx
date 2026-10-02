import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { format } from 'date-fns'
import { UserX, AlertCircle } from 'lucide-react'
import { api } from '@/lib/api'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import {
  PageBody, PageHeader, Section, EmptyState, ErrorState, ListSkeleton,
} from '@/components/shell'
import { MetaChip } from '@/components/status'

type DeletionRequest = {
  id: string
  name: string | null
  phone: string
  deletion_requested_at: string
  deletion_status: string
}

export default function DeletionRequests() {
  const queryClient = useQueryClient()
  const [busy, setBusy] = useState<string | null>(null)
  const [errors, setErrors] = useState<Record<string, string>>({})

  const { data = [], isLoading, isError, error } = useQuery<DeletionRequest[]>({
    queryKey: ['admin-deletion-requests'],
    queryFn: () => api.get<DeletionRequest[]>('/admin/doctors/deletion-requests'),
  })

  async function fulfill(id: string) {
    setBusy(id)
    setErrors(e => ({ ...e, [id]: '' }))
    try {
      await api.post(`/admin/doctors/${id}/deletion/fulfill`, {})
      queryClient.invalidateQueries({ queryKey: ['admin-deletion-requests'] })
    } catch (e) {
      setErrors(prev => ({ ...prev, [id]: (e as Error).message }))
    } finally {
      setBusy(null)
    }
  }

  return (
    <div>
      <PageHeader
        title="Deletion requests"
        description="Doctors who asked to delete their account. Settle any pending payout and resolve active bookings before completing the erasure."
      />
      <PageBody>
        <Section title="Pending" hint={`${data.length} waiting`}>
          {isLoading ? (
            <ListSkeleton />
          ) : isError ? (
            <ErrorState what="deletion requests" error={error} />
          ) : data.length === 0 ? (
            <EmptyState icon={UserX} title="No pending requests" />
          ) : (
            <div className="space-y-3">
              {data.map(d => (
                <Card key={d.id}>
                  <CardContent className="flex flex-wrap items-center justify-between gap-4 p-4">
                    <div className="space-y-1">
                      <p className="text-sm font-semibold">{d.name ?? 'Unnamed doctor'}</p>
                      <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm text-muted-foreground">
                        <MetaChip mono>{d.phone}</MetaChip>
                        <span>
                          Requested {format(new Date(d.deletion_requested_at), 'd MMM yyyy')}
                        </span>
                      </div>
                      {errors[d.id] && (
                        <p className="flex items-center gap-1.5 text-xs text-destructive">
                          <AlertCircle size={13} />{errors[d.id]}
                        </p>
                      )}
                    </div>
                    <Button
                      variant="destructive" size="sm"
                      disabled={busy === d.id}
                      onClick={() => fulfill(d.id)}
                    >
                      {busy === d.id ? 'Deleting…' : 'Complete deletion'}
                    </Button>
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
