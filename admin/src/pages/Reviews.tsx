import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { format } from 'date-fns'
import { EyeOff, Flag, Star } from 'lucide-react'
import { api } from '@/lib/api'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs'
import {
  PageBody, PageHeader, Section, Toolbar, EmptyState, ErrorState, ListSkeleton,
} from '@/components/shell'
import { MetaChip } from '@/components/status'

/**
 * Review moderation (backend services/reviews.py). A doctor's report never
 * hides a review on its own. Ops hides one only for a stated reason — abuse,
 * nothing to do with the visit, or someone's private details — never for being
 * negative, and can restore it. Every decision, with its reason, is in the
 * audit log.
 */
type Report = { id: string; reason: string; note: string | null; reporter_role: string; created_at: string }
type Review = {
  id: string
  overall: number
  professionalism: number | null
  communication: number | null
  punctuality: number | null
  comment: string | null
  status: 'published' | 'hidden'
  hidden_reason: string | null
  hidden_at: string | null
  created_at: string
  doctors: { name: string | null } | null
  reports?: Report[]
}

const REASON: Record<string, string> = {
  abusive: 'Abusive', privacy: 'Private details', irrelevant: 'Not about the visit', other: 'Other',
}

export default function Reviews() {
  const [view, setView] = useState<'reported' | 'hidden'>('reported')
  const [reasons, setReasons] = useState<Record<string, string>>({})
  const [busy, setBusy] = useState<string | null>(null)
  const [error, setError] = useState<Record<string, string>>({})
  const qc = useQueryClient()
  const { data = [], isLoading, isError, error: loadError } = useQuery<Review[]>({
    queryKey: ['admin-reviews', view],
    queryFn: () => api.get<Review[]>(`/admin/reviews?status=${view}`),
  })

  async function decide(id: string, action: 'hide' | 'restore' | 'dismiss') {
    setBusy(id)
    setError(e => ({ ...e, [id]: '' }))
    try {
      await api.post(`/admin/reviews/${id}/moderate`, { action, reason: (reasons[id] ?? '').trim() })
      qc.invalidateQueries({ queryKey: ['admin-reviews'] })
    } catch (e) {
      setError(prev => ({ ...prev, [id]: (e as Error).message }))
    } finally {
      setBusy(null)
    }
  }

  return (
    <div>
      <PageHeader
        title="Reviews"
        description="Reported reviews. Hide one only if it's abusive, off-topic or shares private details — never for being negative."
      />
      <PageBody>
        <Section title="Queue" hint={`${data.length} shown`}>
          <Toolbar>
            <Tabs value={view} onValueChange={v => setView(v as 'reported' | 'hidden')}>
              <TabsList>
                <TabsTrigger value="reported">Reported</TabsTrigger>
                <TabsTrigger value="hidden">Hidden</TabsTrigger>
              </TabsList>
            </Tabs>
          </Toolbar>
          {isLoading && <ListSkeleton rows={3} height="h-28" />}
          {isError && <ErrorState what="reviews" error={loadError} />}
          {!isLoading && !isError && data.length === 0 && (
            <EmptyState icon={view === 'reported' ? Flag : EyeOff}
              title={view === 'reported' ? 'No reported reviews' : 'Nothing hidden'} />
          )}
          <div className="space-y-3">
            {data.map(r => {
              const reason = reasons[r.id] ?? ''
              const ok = reason.trim().length >= 5 && busy !== r.id
              return (
                <Card key={r.id}>
                  <CardContent className="space-y-3 p-4">
                    <div className="flex flex-wrap items-center gap-2 text-sm">
                      <span className="inline-flex items-center gap-1 font-semibold tabular-nums">
                        <Star size={14} className="fill-warning text-warning" />{r.overall}
                      </span>
                      <span>about {r.doctors?.name ?? 'a doctor'}</span>
                      <span className="ml-auto text-xs text-muted-foreground">{format(new Date(r.created_at), 'd MMM yyyy')}</span>
                    </div>
                    <p className="whitespace-pre-wrap text-sm">{r.comment ?? <i className="text-muted-foreground">No comment</i>}</p>
                    {r.reports?.map(rep => (
                      <p key={rep.id} className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
                        <MetaChip>{REASON[rep.reason] ?? rep.reason}</MetaChip>
                        reported by the {rep.reporter_role}{rep.note ? `: “${rep.note}”` : ''}
                      </p>
                    ))}
                    {r.status === 'hidden' && (
                      <p className="text-xs text-muted-foreground">
                        Hidden {r.hidden_at ? format(new Date(r.hidden_at), 'd MMM') : ''}: {r.hidden_reason}
                      </p>
                    )}
                    <div className="flex flex-wrap items-center gap-2 border-t pt-3">
                      <input
                        className="min-w-56 flex-1 rounded-md border bg-background px-2 py-1.5 text-sm"
                        placeholder="Reason for your decision (recorded)"
                        value={reason}
                        onChange={e => setReasons(p => ({ ...p, [r.id]: e.target.value }))}
                      />
                      {r.status === 'published' ? (
                        <>
                          <Button size="sm" variant="outline" disabled={!ok} onClick={() => decide(r.id, 'dismiss')}>Keep it up</Button>
                          <Button size="sm" variant="destructive" disabled={!ok} onClick={() => decide(r.id, 'hide')}>Hide</Button>
                        </>
                      ) : (
                        <Button size="sm" disabled={!ok} onClick={() => decide(r.id, 'restore')}>Restore</Button>
                      )}
                    </div>
                    {error[r.id] && <p className="text-xs text-destructive">{error[r.id]}</p>}
                  </CardContent>
                </Card>
              )
            })}
          </div>
        </Section>
      </PageBody>
    </div>
  )
}
