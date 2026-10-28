import { useState, type ReactNode } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { format } from 'date-fns'
import { ScrollText } from 'lucide-react'
import { api } from '@/lib/api'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { PageBody, PageHeader, Section, EmptyState, ErrorState, ListSkeleton } from '@/components/shell'
import { MetaChip, StatusPill } from '@/components/status'

/**
 * The legal review gate (D20, migration 0029). A cancellation policy or legal
 * document version applies only once its approval is recorded here, with who
 * reviewed it. Approvals can't be changed or withdrawn; a correction is a new
 * version.
 */
type Approval = { approved_by: string; note: string | null; approved_at: string } | null
type Policy = { id: string; channel: string; version: string; summary: string; decision_ref: string | null;
                effective_from: string; policy_approvals: Approval | Approval[] }
type Doc = { id: string; type: string; version: string; title: string; url: string; material: boolean;
             published_at: string; summary: string | null; highlights: string[] | null; body: string | null;
             sha256: string | null; audience: string[]; legal_document_approvals: Approval | Approval[] }

const first = (a: Approval | Approval[]) => (Array.isArray(a) ? a[0] ?? null : a)

/**
 * The exact text people will be asked to sign (migration 0030), so the
 * reviewer approves what they read. Versions from before 0030 live only on
 * the website.
 */
function DocumentText({ doc }: { doc: Doc }) {
  const [open, setOpen] = useState(false)
  if (!doc.body) return null
  return (
    <div className="space-y-2">
      <Button variant="outline" size="sm" onClick={() => setOpen(o => !o)} aria-expanded={open}>
        {open ? 'Hide the text' : 'Read the full text'}
      </Button>
      {open && (
        <div className="space-y-3 rounded-md border bg-muted/30 p-3">
          {doc.highlights && doc.highlights.length > 0 && (
            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">In short</p>
              <ul className="mt-1 list-disc space-y-1 pl-5 text-sm">
                {doc.highlights.map((h, i) => <li key={i}>{h}</li>)}
              </ul>
            </div>
          )}
          <div className="max-h-[28rem] overflow-auto whitespace-pre-wrap text-sm leading-relaxed">{doc.body}</div>
          {doc.sha256 && (
            <p className="text-xs text-muted-foreground">
              Fingerprint <span className="font-mono tabular-nums">{doc.sha256}</span>. Each signature records it.
            </p>
          )}
        </div>
      )}
    </div>
  )
}

export default function Policies() {
  const qc = useQueryClient()
  const [who, setWho] = useState<Record<string, string>>({})
  const [err, setErr] = useState<Record<string, string>>({})
  const { data, isLoading, isError, error } = useQuery<{ policies: Policy[]; documents: Doc[] }>({
    queryKey: ['admin-policies'], queryFn: () => api.get('/admin/policies'),
  })

  async function approve(kind: 'policies' | 'legal-documents', id: string) {
    setErr(e => ({ ...e, [id]: '' }))
    try {
      await api.post(`/admin/${kind}/${id}/approve`, { approved_by: (who[id] ?? '').trim() })
      qc.invalidateQueries({ queryKey: ['admin-policies'] })
    } catch (e) {
      setErr(p => ({ ...p, [id]: (e as Error).message }))
    }
  }

  const row = (id: string, kind: 'policies' | 'legal-documents', title: string, sub: string, a: Approval,
               extra?: ReactNode) => (
    <Card key={id}>
      <CardContent className="space-y-2 p-4">
        <div className="flex flex-wrap items-center gap-2 text-sm">
          <span className="font-semibold">{title}</span>
          <StatusPill status={a ? 'approved' : 'awaiting_review'} />
          {a && <span className="ml-auto text-xs text-muted-foreground">Approved by {a.approved_by}, {format(new Date(a.approved_at), 'd MMM yyyy')}</span>}
        </div>
        <p className="text-sm text-muted-foreground">{sub}</p>
        {extra}
        {!a && (
          <div className="flex flex-wrap gap-2 border-t pt-3">
            <input className="min-w-64 flex-1 rounded-md border bg-background px-2 py-1.5 text-sm"
              placeholder="Who reviewed it, e.g. Founder; counsel review 2 Nov"
              value={who[id] ?? ''} onChange={e => setWho(w => ({ ...w, [id]: e.target.value }))} />
            <Button size="sm" disabled={(who[id] ?? '').trim().length < 3} onClick={() => approve(kind, id)}>Approve and publish</Button>
            {err[id] && <p className="w-full text-xs text-destructive">{err[id]}</p>}
          </div>
        )}
      </CardContent>
    </Card>
  )

  return (
    <div>
      <PageHeader title="Policies" description="A version applies only once its review is recorded here. Approvals can't be undone; publish a new version instead." />
      <PageBody>
        {isLoading && <ListSkeleton rows={4} height="h-24" />}
        {isError && <ErrorState what="policies" error={error} />}
        {data && (
          <>
            <Section title="Cancellation policies">
              {data.policies.length === 0 ? <EmptyState icon={ScrollText} title="None" /> : (
                <div className="space-y-3">
                  {data.policies.map(p => row(p.id, 'policies',
                    `${p.channel === 'home_visit' ? 'Home visit' : 'Online'} · ${p.version}`,
                    `${p.summary} (from ${format(new Date(p.effective_from), 'd MMM yyyy')}${p.decision_ref ? `, ${p.decision_ref}` : ''})`,
                    first(p.policy_approvals)))}
                </div>
              )}
            </Section>
            <Section title="Legal documents">
              <div className="space-y-3">
                {data.documents.map(d => row(d.id, 'legal-documents', `${d.title} · ${d.version}`,
                  [d.summary ?? d.url, `for ${(d.audience ?? []).join(' and ')}`,
                   d.material ? 'material: everyone signs again' : null].filter(Boolean).join(' · '),
                  first(d.legal_document_approvals), <DocumentText doc={d} />))}
              </div>
            </Section>
          </>
        )}
        <p className="pt-2 text-xs text-muted-foreground"><MetaChip>Tip</MetaChip> New document versions come from docs/legal/&lt;version&gt;/ through docs/legal/publish.py; a new cancellation policy is added in SQL (runbook §6c). Either stays inactive until approved here.</p>
      </PageBody>
    </div>
  )
}
