import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { format } from 'date-fns'
import { Key, Calendar, ShieldCheck, FileText, Clock, Mail, Video, Home, X } from 'lucide-react'
import { api } from '@/lib/api'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Avatar, AvatarFallback } from '@/components/ui/avatar'
import {
  PageBody, PageHeader, Section, StatGrid, StatTile,
  EmptyState, ErrorState, ListSkeleton,
} from '@/components/shell'
import { StatusPill, MetaChip } from '@/components/status'
import { getInitials } from '@/lib/utils'

interface PendingDoctor {
  id: string
  name: string | null
  phone: string | null
  email: string | null
  license_number: string
  bio: string | null
  offers_online_consult: boolean
  offers_home_visit: boolean
  verification_document_path: string | null
  verification_document_mime: string | null
  categories: { name: string } | null
  // Set when the doctor picked "Other" at registration — no category_id
  // exists yet for whatever they typed. See matchCategoryId in the website's
  // Register.jsx and the app's profile_setup_screen.dart for the two places
  // this gets written.
  application_details: { specialty_other?: string } | null
  created_at: string
}

function daysWaiting(iso: string) {
  return Math.floor((Date.now() - new Date(iso).getTime()) / 86_400_000)
}

// Only http(s) URLs are safe to hand to window.open/<img src>: a `javascript:`
// (or `data:`) URL would execute in the admin dashboard's own origin and
// could exfiltrate the ops session token. The signed URL always comes from
// our own backend, but this costs nothing and matches the paranoia already
// applied to the same kind of value elsewhere in this file.
function safeUrl(raw: string | null | undefined): string | null {
  if (!raw) return null
  try {
    const u = new URL(raw, window.location.origin)
    return u.protocol === 'http:' || u.protocol === 'https:' ? u.href : null
  } catch {
    return null
  }
}

function DoctorCard({ doctor }: { doctor: PendingDoctor }) {
  const queryClient = useQueryClient()
  const [rejectOpen, setRejectOpen] = useState(false)
  const [reason, setReason] = useState('')
  const [preview, setPreview] = useState<{ url: string; mime: string | null } | null>(null)

  const verifyMutation = useMutation({
    mutationFn: (payload: { action: 'approve' | 'reject'; reason?: string }) =>
      api.patch(`/admin/doctors/${doctor.id}/verify`, payload),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['pending-doctors'] })
      queryClient.invalidateQueries({ queryKey: ['admin-metrics'] })
    },
  })

  // Signed URLs expire (storage.SIGNED_URL_TTL_SECONDS, backend-side) and
  // name the identity document itself, so this is fetched on demand — not
  // proactively for every doctor in the queue on page load.
  const docMutation = useMutation({
    mutationFn: () =>
      api.get<{ url: string; mime_type: string | null }>(
        `/uploads/doctor/${doctor.id}/verification-document`
      ),
    onSuccess: ({ url, mime_type }) => {
      const safe = safeUrl(url)
      if (!safe) return
      if (mime_type?.startsWith('image/')) {
        setPreview({ url: safe, mime: mime_type })
      } else {
        window.open(safe, '_blank', 'noopener,noreferrer')
      }
    },
  })

  const isLoading = verifyMutation.isPending
  const waited = daysWaiting(doctor.created_at)
  const hasDoc = !!doctor.verification_document_path

  return (
    <Card>
      <CardContent className="space-y-3 p-4">
        <div className="flex items-start justify-between gap-4">
          <div className="flex items-center gap-3">
            <Avatar>
              <AvatarFallback>{getInitials(doctor.name)}</AvatarFallback>
            </Avatar>
            <div>
              <p className="text-sm font-semibold">{doctor.name ?? 'No name set yet'}</p>
              <p className="text-sm text-muted-foreground">{doctor.phone ?? doctor.email ?? '—'}</p>
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

        {/* The application itself — what the form the user filled in actually
            says, so ops can judge it without opening anything else. */}
        <div className="flex flex-wrap items-center gap-1.5 text-sm">
          {doctor.categories?.name && <MetaChip>{doctor.categories.name}</MetaChip>}
          {!doctor.categories?.name && doctor.application_details?.specialty_other && (
            <MetaChip>{doctor.application_details.specialty_other} (not yet a category)</MetaChip>
          )}
          {doctor.offers_online_consult && (
            <MetaChip><Video size={12} className="mr-1 inline" />Online</MetaChip>
          )}
          {doctor.offers_home_visit && (
            <MetaChip><Home size={12} className="mr-1 inline" />Home visit</MetaChip>
          )}
          {doctor.email && (
            <span className="inline-flex items-center gap-1 text-muted-foreground">
              <Mail size={12} />{doctor.email}
            </span>
          )}
        </div>
        {doctor.bio && (
          <p className="rounded-tile bg-muted/40 p-2.5 text-sm text-muted-foreground">
            {doctor.bio}
          </p>
        )}

        {verifyMutation.isError && (
          <p className="text-xs text-destructive">
            {(verifyMutation.error as Error).message}
          </p>
        )}
        {docMutation.isError && (
          <p className="text-xs text-destructive">
            {(docMutation.error as Error).message}
          </p>
        )}

        {preview && (
          <div className="space-y-1.5 border-t pt-3">
            <div className="flex items-center justify-between">
              <span className="text-xs font-medium text-muted-foreground">Submitted document</span>
              <button
                type="button"
                className="text-muted-foreground hover:text-foreground"
                onClick={() => setPreview(null)}
              >
                <X size={14} />
              </button>
            </div>
            {/* The signed URL is short-lived; this <img> is only ever shown
                right after fetching it, never cached across a reload. */}
            <img
              src={preview.url}
              alt="Submitted identity document"
              className="max-h-80 w-full rounded-tile border border-border object-contain"
            />
          </div>
        )}

        <div className="flex flex-wrap items-center gap-2 border-t pt-3">
          <Button
            variant="outline" size="sm"
            disabled={!hasDoc || docMutation.isPending}
            onClick={() => docMutation.mutate()}
          >
            <FileText size={14} />
            {!hasDoc ? 'No document' : docMutation.isPending ? 'Loading…' : 'View document'}
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
              className="min-h-[80px] w-full resize-none rounded-tile border border-border p-2 text-sm focus:outline-none focus:ring-2 focus:ring-ring"
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
  const missingDoc = rows.filter(d => !d.verification_document_path).length

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
