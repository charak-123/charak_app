import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { format } from 'date-fns'
import { Key, Calendar, CheckCircle } from 'lucide-react'
import { api } from '@/lib/api'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Avatar, AvatarFallback } from '@/components/ui/avatar'

interface PendingDoctor {
  id: string
  name: string
  phone: string
  license_number: string
  verification_document_url: string | null
  created_at: string
}

function SkeletonCard() {
  return (
    <Card>
      <CardContent className="p-4 animate-pulse space-y-3">
        <div className="flex items-center gap-3">
          <div className="h-10 w-10 rounded-full bg-muted" />
          <div className="space-y-1 flex-1">
            <div className="h-4 w-40 rounded bg-muted" />
            <div className="h-3 w-28 rounded bg-muted" />
          </div>
        </div>
        <div className="h-3 w-36 rounded bg-muted" />
        <div className="h-3 w-24 rounded bg-muted" />
        <div className="flex gap-2">
          <div className="h-8 w-28 rounded bg-muted" />
          <div className="h-8 w-20 rounded bg-muted" />
          <div className="h-8 w-20 rounded bg-muted" />
        </div>
      </CardContent>
    </Card>
  )
}

function getInitials(name: string) {
  return name
    .split(' ')
    .map(w => w[0])
    .slice(0, 2)
    .join('')
    .toUpperCase()
}

function DoctorCard({ doctor }: { doctor: PendingDoctor }) {
  const queryClient = useQueryClient()
  const [rejectOpen, setRejectOpen] = useState(false)
  const [reason, setReason] = useState('')

  const verifyMutation = useMutation({
    mutationFn: (payload: { action: 'approve' | 'reject'; reason?: string }) =>
      api.patch(`/admin/doctors/${doctor.id}/verify`, payload),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['pending-doctors'] })
    },
  })

  function handleApprove() {
    verifyMutation.mutate({ action: 'approve' })
  }

  function handleReject() {
    if (!reason.trim()) return
    verifyMutation.mutate({ action: 'reject', reason: reason.trim() })
  }

  const isLoading = verifyMutation.isPending

  return (
    <Card>
      <CardContent className="p-4 space-y-3">
        {/* Top row: avatar + name + phone + badge */}
        <div className="flex items-start justify-between gap-4">
          <div className="flex items-center gap-3">
            <Avatar>
              <AvatarFallback>{getInitials(doctor.name)}</AvatarFallback>
            </Avatar>
            <div>
              <p className="font-semibold text-sm">{doctor.name}</p>
              <p className="text-sm text-muted-foreground">{doctor.phone}</p>
            </div>
          </div>
          <Badge variant="outline" className="border-warning text-warning shrink-0">
            Pending
          </Badge>
        </div>

        {/* License row */}
        <div className="flex items-center gap-1.5 text-sm text-muted-foreground">
          <Key size={14} />
          <span>{doctor.license_number}</span>
        </div>

        {/* Submitted date row */}
        <div className="flex items-center gap-1.5 text-sm text-muted-foreground">
          <Calendar size={14} />
          <span>Submitted {format(new Date(doctor.created_at), 'd MMM yyyy')}</span>
        </div>

        {verifyMutation.isError && (
          <p className="text-xs text-destructive">
            {(verifyMutation.error as Error).message}
          </p>
        )}

        {/* Action row */}
        <div className="flex flex-wrap items-center gap-2">
          <Button
            variant="outline"
            size="sm"
            disabled={!doctor.verification_document_url}
            onClick={() => window.open(doctor.verification_document_url!, '_blank')}
          >
            View Document
          </Button>
          <Button
            size="sm"
            className="bg-success hover:bg-success/90 text-white"
            disabled={isLoading || rejectOpen}
            onClick={handleApprove}
          >
            Approve
          </Button>
          <Button
            variant="destructive"
            size="sm"
            disabled={isLoading}
            onClick={() => setRejectOpen(v => !v)}
          >
            Reject
          </Button>
        </div>

        {/* Rejection area */}
        {rejectOpen && (
          <div className="space-y-2 border-t pt-3">
            <textarea
              className="w-full border border-border rounded-md p-2 text-sm min-h-[80px] mt-2 resize-none focus:outline-none focus:ring-2 focus:ring-ring"
              placeholder="Reason for rejection…"
              value={reason}
              onChange={e => setReason(e.target.value)}
              disabled={isLoading}
            />
            <div className="flex gap-2">
              <Button
                variant="destructive"
                size="sm"
                disabled={isLoading || !reason.trim()}
                onClick={handleReject}
              >
                Confirm Rejection
              </Button>
              <Button
                variant="ghost"
                size="sm"
                disabled={isLoading}
                onClick={() => { setRejectOpen(false); setReason('') }}
              >
                Cancel
              </Button>
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  )
}

export default function VerificationQueue() {
  const { data, isLoading, isError, error } = useQuery<PendingDoctor[]>({
    queryKey: ['pending-doctors'],
    queryFn: () => api.get('/admin/doctors/pending'),
  })

  return (
    <div>
      <div className="p-6 border-b bg-background">
        <h1 className="text-xl font-semibold">Verification Queue</h1>
        <p className="text-sm text-muted-foreground">Doctors awaiting identity verification</p>
      </div>

      <div className="p-6 space-y-4">
        {isLoading && (
          <>
            <SkeletonCard />
            <SkeletonCard />
            <SkeletonCard />
          </>
        )}

        {isError && (
          <Card>
            <CardContent className="p-4">
              <p className="text-sm text-destructive">
                Failed to load pending doctors: {(error as Error).message}
              </p>
            </CardContent>
          </Card>
        )}

        {!isLoading && !isError && data && data.length === 0 && (
          <div className="flex flex-col items-center justify-center py-16 gap-3">
            <CheckCircle size={48} className="text-success" />
            <p className="text-base font-semibold">No pending verifications</p>
            <p className="text-sm text-muted-foreground">All doctors have been reviewed.</p>
          </div>
        )}

        {!isLoading && !isError && data && data.length > 0 && (
          <div className="space-y-3">
            {data.map(doctor => (
              <DoctorCard key={doctor.id} doctor={doctor} />
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
