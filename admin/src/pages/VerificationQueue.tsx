import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { format } from 'date-fns'
import { Key, Calendar, ShieldCheck, FileText, Clock } from 'lucide-react'
import { api } from '@/lib/api'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Avatar, AvatarFallback } from '@/components/ui/avatar'
import {
  PageBody, PageHeader, Section, StatGrid, StatTile,
  EmptyState, ErrorState, ListSkeleton,
} from '@/components/shell'
import { StatusPill } from '@/components/status'

interface PendingDoctor {
  id: string
  name: string
  phone: string
  license_number: string
  verification_document_url: string | null
  created_at: string
}

function getInitials(name: string) {
  return name.split(' ').map(w => w[0]).slice(0, 2).join('').toUpperCase()
}

function daysWaiting(iso: string) {
  return Math.floor((Date.now() - new Date(iso).getTime()) / 86_400_000)
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
      queryClient.invalidateQueries({ queryKey: ['admin-metrics'] })
    },
  })

  const isLoading = verifyMutation.isPending
  const waited = daysWaiting(doctor.created_at)

  return (
    <Card>
      <CardContent className="space-y-3 p-4">
        <div className="flex items-start justify-between gap-4">
          <div className="flex items-center gap-3">
            <Avatar>
              <AvatarFallback>{getInitials(doctor.name)}</AvatarFallback>
            </Avatar>
            <div>
              <p className="text-sm font-semibold">{doctor.name}</p>
              <p className="text-sm text-muted-foreground">{doctor.phone}</p>
            </div>
          </div>
          <StatusPill status="pending" />
        </div>

        <div className="flex flex-wrap items-center gap-x-5 gap-y-1.5 text-sm text-muted-foreground">
          <span className="inline-flex items-center gap-1.5">
            <Key size={14} />{doctor.license_number}
          </span>
          <span className="inline-flex items-center gap-1.5">
            <Calendar size={14} />
            Submitted {format(new Date(doctor.created_at), 'd MMM yyyy')}
          </span>
          {waited >= 2 && (
            <span className="inline-flex items-center gap-1.5 text-warning">
              <Clock size={14} />Waiting {waited} days
            </span>
          )}
        </div>

        {verifyMutation.isError && (
          <p className="text-xs text-destructive">
            {(verifyMutation.error as Error).message}
          </p>
        )}

        <div className="flex flex-wrap items-center gap-2 border-t pt-3">
          <Button
            variant="outline" size="sm"
            disabled={!doctor.verification_document_url}
            onClick={() => window.open(doctor.verification_document_url!, '_blank')}
          >
            <FileText size={14} />
            {doctor.verification_document_url ? 'View document' : 'No document'}
          </Button>
          <Button
            size="sm"
            className="bg-success text-white hover:bg-success/90"
            disabled={isLoading || rejectOpen}
            onClick={() => verifyMutation.mutate({ action: 'approve' })}
          >
            Approve
          </Button>
          <Button
            variant="destructive" size="sm"
            disabled={isLoading}
            onClick={() => setRejectOpen(v => !v)}
          >
            Reject
          </Button>
        </div>

        {rejectOpen && (
          <div className="space-y-2 border-t pt-3">
            <textarea
              className="min-h-[80px] w-full resize-none rounded-md border border-border p-2 text-sm focus:outline-none focus:ring-2 focus:ring-ring"
              placeholder="Reason for rejection…"
              value={reason}
              onChange={e => setReason(e.target.value)}
              disabled={isLoading}
            />
            <div className="flex gap-2">
              <Button
                variant="destructive" size="sm"
                disabled={isLoading || !reason.trim()}
                onClick={() => verifyMutation.mutate({ action: 'reject', reason: reason.trim() })}
              >
                Confirm rejection
              </Button>
              <Button
                variant="ghost" size="sm" disabled={isLoading}
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

  const rows = data ?? []
  const waiting = rows.map(d => daysWaiting(d.created_at))
  const stale = waiting.filter(d => d >= 3).length
  const missingDoc = rows.filter(d => !d.verification_document_url).length

  return (
    <div>
      <PageHeader
        title="Verification"
        description="Doctors awaiting identity and licence verification"
      />

      <PageBody>
        <Section title="At a glance" hint={`${rows.length} in queue`}>
          <StatGrid>
            <StatTile
              icon={ShieldCheck} tone="warning" value={rows.length}
              label="Awaiting review"
            />
            <StatTile
              icon={Clock} tone={stale > 0 ? 'critical' : 'neutral'} value={stale}
              label="Waiting 3+ days"
            />
            <StatTile
              icon={FileText} tone={missingDoc > 0 ? 'critical' : 'neutral'} value={missingDoc}
              label="No document attached"
            />
            <StatTile
              icon={Calendar} tone="neutral"
              value={waiting.length ? Math.max(...waiting) : 0}
              label="Longest wait" hint="Days"
            />
          </StatGrid>
        </Section>

        <Section title="Queue" hint="Oldest first">
          {isLoading && <ListSkeleton rows={3} height="h-24" />}
          {isError && <ErrorState what="pending doctors" error={error} />}
          {!isLoading && !isError && rows.length === 0 && (
            <EmptyState
              icon={ShieldCheck}
              title="No pending verifications"
              hint="Every doctor has been reviewed."
            />
          )}
          {!isLoading && !isError && rows.length > 0 && (
            <div className="space-y-3">
              {rows.map(doctor => <DoctorCard key={doctor.id} doctor={doctor} />)}
            </div>
          )}
        </Section>
      </PageBody>
    </div>
  )
}
