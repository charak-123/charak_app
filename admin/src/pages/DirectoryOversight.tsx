import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { format } from 'date-fns'
import { Search, Star } from 'lucide-react'
import { api } from '@/lib/api'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Avatar, AvatarFallback } from '@/components/ui/avatar'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'

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
  return name
    .split(' ')
    .map(w => w[0])
    .slice(0, 2)
    .join('')
    .toUpperCase()
}

function StatusBadge({ status }: { status: Doctor['verification_status'] }) {
  switch (status) {
    case 'verified':
      return (
        <Badge variant="outline" className="border-success text-success bg-success/10">
          Verified
        </Badge>
      )
    case 'pending':
      return (
        <Badge variant="outline" className="border-warning text-warning bg-warning/10">
          Pending
        </Badge>
      )
    case 'rejected':
      return <Badge variant="destructive">Rejected</Badge>
  }
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
      `Suspend Dr. ${doctor.name}? This will mark their account as rejected and remove them from the public directory.`
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
    <div>
      <div className="p-6 border-b bg-background">
        <h1 className="text-xl font-semibold">Doctor Directory</h1>
        <p className="text-sm text-muted-foreground">
          View and manage all doctors in the Charak directory.
        </p>
      </div>

      <div className="p-6 space-y-4">
        {/* Search + count */}
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
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
          {!isLoading && !isError && data && (
            <p className="text-sm text-muted-foreground shrink-0">
              {filtered.length} doctor{filtered.length !== 1 ? 's' : ''}
            </p>
          )}
        </div>

        {/* Error state */}
        {isError && (
          <p className="text-sm text-destructive py-4">
            Failed to load doctors: {(error as Error).message}
          </p>
        )}

        {/* Loading skeleton */}
        {isLoading && (
          <div className="rounded-md border">
            <Table>
              <TableHeader>
                <TableRow>
                  {['Name', 'Phone', 'Status', 'Channels', 'Rating', 'Actions'].map(h => (
                    <TableHead key={h}>{h}</TableHead>
                  ))}
                </TableRow>
              </TableHeader>
              <TableBody>
                {Array.from({ length: 5 }).map((_, i) => (
                  <TableRow key={i} className="animate-pulse">
                    {Array.from({ length: 6 }).map((_, j) => (
                      <TableCell key={j}>
                        <div className="h-3 rounded bg-muted w-20" />
                      </TableCell>
                    ))}
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}

        {/* Table */}
        {!isLoading && !isError && (
          <>
            {filtered.length === 0 ? (
              <div className="rounded-md border px-4 py-12 text-center">
                <p className="text-sm text-muted-foreground">
                  {search ? 'No doctors match your search.' : 'No doctors found.'}
                </p>
              </div>
            ) : (
              <div className="rounded-md border overflow-x-auto">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Name</TableHead>
                      <TableHead>Phone</TableHead>
                      <TableHead>Status</TableHead>
                      <TableHead>Channels</TableHead>
                      <TableHead>Rating</TableHead>
                      <TableHead>Actions</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {filtered.map(doctor => (
                      <TableRow key={doctor.id}>
                        {/* Name + Avatar */}
                        <TableCell>
                          <div className="flex items-center gap-3">
                            <Avatar className="h-8 w-8">
                              <AvatarFallback className="text-xs">
                                {getInitials(doctor.name)}
                              </AvatarFallback>
                            </Avatar>
                            <div>
                              <p className="font-medium text-sm">{doctor.name}</p>
                              <p className="text-xs text-muted-foreground">
                                Since {format(new Date(doctor.created_at), 'd MMM yyyy')}
                              </p>
                            </div>
                          </div>
                        </TableCell>

                        {/* Phone */}
                        <TableCell className="text-muted-foreground">{doctor.phone}</TableCell>

                        {/* Status */}
                        <TableCell>
                          <StatusBadge status={doctor.verification_status} />
                        </TableCell>

                        {/* Channels */}
                        <TableCell>
                          <div className="flex flex-wrap gap-1">
                            {doctor.offers_online_consult && (
                              <Badge variant="secondary">Online</Badge>
                            )}
                            {doctor.offers_home_visit && (
                              <Badge variant="secondary">Home</Badge>
                            )}
                            {!doctor.offers_online_consult && !doctor.offers_home_visit && (
                              <span className="text-muted-foreground text-sm">—</span>
                            )}
                          </div>
                        </TableCell>

                        {/* Rating */}
                        <TableCell>
                          {doctor.rating_avg != null ? (
                            <span className="inline-flex items-center gap-1 text-sm">
                              <Star size={12} className="text-warning fill-warning" />
                              {doctor.rating_avg.toFixed(1)}
                            </span>
                          ) : (
                            <span className="text-muted-foreground">—</span>
                          )}
                        </TableCell>

                        {/* Actions */}
                        <TableCell>
                          {doctor.verification_status === 'verified' && (
                            <Button
                              variant="destructive"
                              size="sm"
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
              </div>
            )}
          </>
        )}
      </div>
    </div>
  )
}
