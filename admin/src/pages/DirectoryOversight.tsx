import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { format } from 'date-fns'
import { Search, Star, Monitor, Home } from 'lucide-react'
import { api } from '@/lib/api'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'

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

const statusVariant: Record<Doctor['verification_status'], 'success' | 'warning' | 'danger'> = {
  verified: 'success',
  pending: 'warning',
  rejected: 'danger',
}

const statusLabel: Record<Doctor['verification_status'], string> = {
  verified: 'Verified',
  pending: 'Pending',
  rejected: 'Rejected',
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
    },
  })

  function handleSuspend(doctor: Doctor) {
    const confirmed = window.confirm(
      `Suspend Dr. ${doctor.name}? This will mark their account as rejected and remove them from the public directory.`,
    )
    if (!confirmed) return
    suspendMutation.mutate(doctor.id)
  }

  const filtered = (data ?? []).filter(d => {
    if (!search.trim()) return true
    const q = search.toLowerCase()
    return d.name.toLowerCase().includes(q) || d.phone.includes(q)
  })

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-ink">Directory Oversight</h1>
        <p className="text-sm text-ink-muted mt-0.5">
          View and manage all doctors in the Charak directory.
        </p>
      </div>

      {/* Search + count */}
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div className="relative w-full max-w-sm">
          <Search size={15} className="absolute left-3 top-1/2 -translate-y-1/2 text-ink-muted" />
          <Input
            className="pl-9"
            placeholder="Search by name or phone…"
            value={search}
            onChange={e => setSearch(e.target.value)}
          />
        </div>
        {!isLoading && !isError && data && (
          <p className="text-sm text-ink-muted shrink-0">
            {filtered.length} of {data.length} doctor{data.length !== 1 ? 's' : ''}
          </p>
        )}
      </div>

      {/* Error state */}
      {isError && (
        <div className="rounded-card border border-danger/30 bg-red-50 px-4 py-3">
          <p className="text-sm text-danger">
            Failed to load doctors: {(error as Error).message}
          </p>
        </div>
      )}

      {/* Loading skeleton */}
      {isLoading && (
        <div className="overflow-hidden rounded-card border border-border">
          <table className="w-full text-sm">
            <thead className="bg-bg-subtle">
              <tr>
                {['Name', 'Phone', 'Specialty', 'Status', 'Channels', 'Rating', 'Actions'].map(h => (
                  <th key={h} className="px-4 py-3 text-left text-xs font-medium text-ink-muted">
                    {h}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-border bg-white">
              {Array.from({ length: 5 }).map((_, i) => (
                <tr key={i} className="animate-pulse">
                  {Array.from({ length: 7 }).map((_, j) => (
                    <td key={j} className="px-4 py-3">
                      <div className="h-3 rounded bg-bg-subtle w-20" />
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Table */}
      {!isLoading && !isError && (
        <>
          {filtered.length === 0 ? (
            <div className="rounded-card border border-border bg-white px-4 py-12 text-center">
              <p className="text-sm text-ink-muted">
                {search ? 'No doctors match your search.' : 'No doctors found.'}
              </p>
            </div>
          ) : (
            <div className="overflow-x-auto rounded-card border border-border">
              <table className="w-full text-sm">
                <thead className="bg-bg-subtle">
                  <tr>
                    <th className="px-4 py-3 text-left text-xs font-medium text-ink-muted">Name</th>
                    <th className="px-4 py-3 text-left text-xs font-medium text-ink-muted">Phone</th>
                    <th className="px-4 py-3 text-left text-xs font-medium text-ink-muted">Specialty</th>
                    <th className="px-4 py-3 text-left text-xs font-medium text-ink-muted">Status</th>
                    <th className="px-4 py-3 text-left text-xs font-medium text-ink-muted">Channels</th>
                    <th className="px-4 py-3 text-left text-xs font-medium text-ink-muted">Rating</th>
                    <th className="px-4 py-3 text-left text-xs font-medium text-ink-muted">Actions</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-border bg-white">
                  {filtered.map(doctor => (
                    <tr key={doctor.id} className="hover:bg-bg-subtle/50 transition-colors">
                      {/* Name */}
                      <td className="px-4 py-3">
                        <div>
                          <p className="font-medium text-ink">{doctor.name}</p>
                          <p className="text-xs text-ink-muted">
                            Since {format(new Date(doctor.created_at), 'd MMM yyyy')}
                          </p>
                        </div>
                      </td>

                      {/* Phone */}
                      <td className="px-4 py-3 text-ink-muted">{doctor.phone}</td>

                      {/* Specialty */}
                      <td className="px-4 py-3 text-ink-muted">
                        {doctor.category_name ?? '—'}
                      </td>

                      {/* Status */}
                      <td className="px-4 py-3">
                        <Badge
                          label={statusLabel[doctor.verification_status]}
                          variant={statusVariant[doctor.verification_status]}
                        />
                      </td>

                      {/* Channels */}
                      <td className="px-4 py-3">
                        <div className="flex flex-wrap gap-1">
                          {doctor.offers_online_consult && (
                            <span className="inline-flex items-center gap-1 rounded-pill bg-primary-soft px-2 py-0.5 text-xs font-medium text-primary">
                              <Monitor size={10} />
                              Online
                            </span>
                          )}
                          {doctor.offers_home_visit && (
                            <span className="inline-flex items-center gap-1 rounded-pill bg-primary-soft px-2 py-0.5 text-xs font-medium text-primary">
                              <Home size={10} />
                              Home
                            </span>
                          )}
                          {!doctor.offers_online_consult && !doctor.offers_home_visit && (
                            <span className="text-ink-muted">—</span>
                          )}
                        </div>
                      </td>

                      {/* Rating */}
                      <td className="px-4 py-3">
                        {doctor.rating_avg != null ? (
                          <span className="inline-flex items-center gap-1 text-ink">
                            <Star size={12} className="text-warning fill-warning" />
                            {doctor.rating_avg.toFixed(1)}
                          </span>
                        ) : (
                          <span className="text-ink-muted">—</span>
                        )}
                      </td>

                      {/* Actions */}
                      <td className="px-4 py-3">
                        {doctor.verification_status === 'verified' && (
                          <Button
                            variant="danger"
                            className="text-xs px-3 py-1.5 h-auto"
                            disabled={suspendMutation.isPending}
                            onClick={() => handleSuspend(doctor)}
                          >
                            Suspend
                          </Button>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </>
      )}
    </div>
  )
}
