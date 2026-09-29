import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { format } from 'date-fns'
import { Search, Star, Users, ShieldCheck, Video, Home } from 'lucide-react'
import { api } from '@/lib/api'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Avatar, AvatarFallback } from '@/components/ui/avatar'
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from '@/components/ui/table'
import {
  PageBody, PageHeader, Section, StatGrid, StatTile, Toolbar,
  EmptyState, ErrorState, ListSkeleton, TableCard,
} from '@/components/shell'
import { MetaChip, StatusPill } from '@/components/status'
import CompositionBar from '@/components/charts/CompositionBar'
import { SERIES } from '@/lib/chart-theme'

interface Doctor {
  id: string
  name: string
  phone: string
  category_id: string | null
  category_name?: string | null
  verification_status: 'pending' | 'verified' | 'rejected'
  rating_avg: number | null
  offers_online_consult: boolean
  offers_home_visit: boolean
  created_at: string
}

function getInitials(name: string) {
  return name.split(' ').map(w => w[0]).slice(0, 2).join('').toUpperCase()
}

export default function DirectoryOversight() {
  const queryClient = useQueryClient()
  const [search, setSearch] = useState('')

  const { data, isLoading, isError, error } = useQuery<Doctor[]>({
    queryKey: ['doctors-directory'],
    queryFn: () => api.get('/doctors/search'),
  })

  const suspendMutation = useMutation({
    mutationFn: (id: string) =>
      api.patch(`/admin/doctors/${id}/verify`, {
        action: 'reject',
        reason: 'Suspended by admin',
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['doctors-directory'] })
      queryClient.invalidateQueries({ queryKey: ['admin-metrics'] })
    },
  })

  function handleSuspend(doctor: Doctor) {
    const confirmed = window.confirm(
      `Suspend Dr. ${doctor.name}? This marks their account rejected and removes them from the public directory.`
    )
    if (confirmed) suspendMutation.mutate(doctor.id)
  }

  const rows = data ?? []
  const filtered = rows.filter(d => {
    if (!search.trim()) return true
    const q = search.toLowerCase()
    return d.name.toLowerCase().includes(q) || d.phone.includes(q)
  })

  const count = (s: Doctor['verification_status']) =>
    rows.filter(d => d.verification_status === s).length
  const rated = rows.filter(d => d.rating_avg != null)
  const avgRating = rated.length
    ? rated.reduce((s, d) => s + (d.rating_avg ?? 0), 0) / rated.length
    : null

  return (
    <div>
      <PageHeader
        title="Directory"
        description="Every doctor listed on Charak, and the channels they serve"
      />

      <PageBody>
        <Section title="At a glance" hint={`${rows.length} doctors`}>
          <StatGrid>
            <StatTile
              icon={ShieldCheck} tone="good" value={count('verified')}
              label="Verified and listed"
            />
            <StatTile
              icon={Video} tone="neutral"
              value={rows.filter(d => d.offers_online_consult).length}
              label="Offer online consults"
            />
            <StatTile
              icon={Home} tone="neutral"
              value={rows.filter(d => d.offers_home_visit).length}
              label="Offer home visits"
            />
            <StatTile
              icon={Star} tone={avgRating && avgRating < 4 ? 'warning' : 'good'}
              value={avgRating ? avgRating.toFixed(1) : '—'}
              label="Average rating" hint={`${rated.length} rated`}
            />
          </StatGrid>
        </Section>

        <Section title="Verification mix">
          <div className="rounded-card bg-card p-4">
            <CompositionBar
              format={n => String(n)}
              segments={[
                { name: 'Verified', value: count('verified'), color: SERIES.aqua },
                { name: 'Pending',  value: count('pending'),  color: SERIES.yellow },
                { name: 'Rejected', value: count('rejected'), color: SERIES.orange },
              ]}
            />
          </div>
        </Section>

        <Section title="All doctors" hint={`${filtered.length} shown`}>
          <Toolbar>
            <div className="relative w-full max-w-sm">
              <Search
                size={15}
                className="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground"
              />
              <Input
                className="pl-9"
                placeholder="Search by name or phone…"
                value={search}
                onChange={e => setSearch(e.target.value)}
              />
            </div>
          </Toolbar>

          {isLoading && <ListSkeleton rows={6} />}
          {isError && <ErrorState what="the directory" error={error} />}
          {!isLoading && !isError && filtered.length === 0 && (
            <EmptyState
              icon={Users}
              title={search ? 'No doctors match your search' : 'No doctors yet'}
              hint={search ? 'Try a different name or phone number.' : undefined}
            />
          )}

          {!isLoading && !isError && filtered.length > 0 && (
            <TableCard>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Name</TableHead>
                    <TableHead>Phone</TableHead>
                    <TableHead>Status</TableHead>
                    <TableHead>Channels</TableHead>
                    <TableHead>Rating</TableHead>
                    <TableHead className="text-right">Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {filtered.map(doctor => (
                    <TableRow key={doctor.id}>
                      <TableCell>
                        <div className="flex items-center gap-3">
                          <Avatar className="h-8 w-8">
                            <AvatarFallback className="text-xs">
                              {getInitials(doctor.name)}
                            </AvatarFallback>
                          </Avatar>
                          <div>
                            <p className="text-sm font-medium">{doctor.name}</p>
                            <p className="text-xs text-muted-foreground">
                              {doctor.category_name ?? 'Uncategorised'} · since{' '}
                              {format(new Date(doctor.created_at), 'MMM yyyy')}
                            </p>
                          </div>
                        </div>
                      </TableCell>
                      <TableCell className="text-sm text-muted-foreground">
                        {doctor.phone}
                      </TableCell>
                      <TableCell>
                        <StatusPill status={doctor.verification_status} />
                      </TableCell>
                      <TableCell>
                        <div className="flex flex-wrap gap-1">
                          {doctor.offers_online_consult && <MetaChip>Online</MetaChip>}
                          {doctor.offers_home_visit && <MetaChip>Home</MetaChip>}
                          {!doctor.offers_online_consult && !doctor.offers_home_visit && (
                            <span className="text-sm text-muted-foreground">—</span>
                          )}
                        </div>
                      </TableCell>
                      <TableCell>
                        {doctor.rating_avg != null ? (
                          <span className="inline-flex items-center gap-1 text-sm tabular-nums">
                            <Star size={12} className="fill-warning text-warning" />
                            {doctor.rating_avg.toFixed(1)}
                          </span>
                        ) : (
                          <span className="text-sm text-muted-foreground">—</span>
                        )}
                      </TableCell>
                      <TableCell className="text-right">
                        {doctor.verification_status === 'verified' && (
                          <Button
                            variant="outline" size="sm"
                            className="text-destructive hover:bg-destructive/10"
                            disabled={suspendMutation.isPending}
                            onClick={() => handleSuspend(doctor)}
                          >
                            Suspend
                          </Button>
                        )}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </TableCard>
          )}
        </Section>
      </PageBody>
    </div>
  )
}
