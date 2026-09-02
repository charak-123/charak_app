import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { format } from 'date-fns'
import { FileText, CheckCircle, XCircle } from 'lucide-react'
import { api } from '@/lib/api'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'

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
    <Card className="animate-pulse">
      <div className="flex items-start justify-between gap-4">
        <div className="flex-1 space-y-2">
          <div className="h-4 w-40 rounded bg-bg-subtle" />
          <div className="h-3 w-28 rounded bg-bg-subtle" />
          <div className="h-3 w-36 rounded bg-bg-subtle" />
          <div className="h-3 w-24 rounded bg-bg-subtle" />
        </div>
        <div className="flex gap-2">
          <div className="h-8 w-24 rounded-btn bg-bg-subtle" />
          <div className="h-8 w-20 rounded-btn bg-bg-subtle" />
          <div className="h-8 w-20 rounded-btn bg-bg-subtle" />
        </div>
      </div>
    </Card>
  )
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
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        {/* Info */}
        <div className="space-y-1">
          <p className="text-sm font-semibold text-ink">{doctor.name}</p>
          <p className="text-xs text-ink-muted">{doctor.phone}</p>
          <p className="text-xs text-ink-muted">
            License: <span className="font-medium text-ink">{doctor.license_number}</span>
          </p>
          <p className="text-xs text-ink-muted">
            Submitted {format(new Date(doctor.created_at), 'd MMM yyyy')}
          </p>
          {verifyMutation.isError && (
            <p className="text-xs text-danger">
              {(verifyMutation.error as Error).message}
            </p>
          )}
        </div>

        {/* Actions */}
        <div className="flex flex-wrap items-center gap-2 shrink-0">
          <Button
            variant="outline"
            className="text-xs px-3 py-1.5 h-auto"
            disabled={!doctor.verification_document_url}
            onClick={() => window.open(doctor.verification_document_url!, '_blank')}
          >
            <FileText size={14} />
            View Document
          </Button>
          <Button
            variant="default"
            className="text-xs px-3 py-1.5 h-auto bg-success hover:bg-success/90"
            disabled={isLoading || rejectOpen}
            onClick={handleApprove}
          >
            <CheckCircle size={14} />
            Approve
          </Button>
          <Button
            variant="danger"
            className="text-xs px-3 py-1.5 h-auto"
            disabled={isLoading}
            onClick={() => setRejectOpen(v => !v)}
          >
            <XCircle size={14} />
            Reject
          </Button>
        </div>
      </div>

      {/* Inline reject form */}
      {rejectOpen && (
        <div className="mt-3 space-y-2 border-t border-border pt-3">
          <textarea
            className="w-full rounded-btn border border-border bg-bg-subtle px-3 py-2 text-sm text-ink placeholder:text-ink-muted focus:outline-none focus:ring-2 focus:ring-primary focus:border-primary resize-none"
            rows={3}
            placeholder="Reason for rejection…"
            value={reason}
            onChange={e => setReason(e.target.value)}
            disabled={isLoading}
          />
          <div className="flex gap-2">
            <Button
              variant="danger"
              className="text-xs px-3 py-1.5 h-auto"
              disabled={isLoading || !reason.trim()}
              onClick={handleReject}
            >
              Confirm Rejection
            </Button>
            <Button
              variant="ghost"
              className="text-xs px-3 py-1.5 h-auto"
              disabled={isLoading}
              onClick={() => { setRejectOpen(false); setReason('') }}
            >
              Cancel
            </Button>
          </div>
        </div>
      )}
    </Card>
  )
}

export default function VerificationQueue() {
  const { data, isLoading, isError, error } = useQuery<PendingDoctor[]>({
    queryKey: ['pending-doctors'],
    queryFn: () => api.get('/admin/doctors/pending'),
  })

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-ink">Verification Queue</h1>
        <p className="text-sm text-ink-muted mt-0.5">
          Review and action pending doctor verification requests.
        </p>
      </div>

      {isLoading && (
        <div className="space-y-3">
          <SkeletonCard />
          <SkeletonCard />
          <SkeletonCard />
        </div>
      )}

      {isError && (
        <Card className="border-danger/30 bg-red-50">
          <p className="text-sm text-danger">
            Failed to load pending doctors: {(error as Error).message}
          </p>
        </Card>
      )}

      {!isLoading && !isError && data && data.length === 0 && (
        <Card className="py-12 text-center">
          <CheckCircle size={32} className="mx-auto text-success mb-3" />
          <p className="text-sm font-medium text-ink">No pending verifications</p>
          <p className="text-xs text-ink-muted mt-1">All doctors have been reviewed.</p>
        </Card>
      )}

      {!isLoading && !isError && data && data.length > 0 && (
        <div className="space-y-3">
          {data.map(doctor => (
            <DoctorCard key={doctor.id} doctor={doctor} />
          ))}
        </div>
      )}
    </div>
  )
}
