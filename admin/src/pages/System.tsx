import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { formatDistanceToNowStrict } from 'date-fns'
import { Server } from 'lucide-react'
import { api } from '@/lib/api'
import { useMe, ROLE_LABEL, type Me } from '@/lib/me'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { PageBody, PageHeader, Section, EmptyState, ErrorState, ListSkeleton } from '@/components/shell'
import { MetaChip } from '@/components/status'

/**
 * What stopped retrying (jobs out of attempts, webhooks that keep failing,
 * pushes that couldn't be delivered), and who has which admin role.
 */
type Letters = {
  jobs: { id: number; kind: string; attempts: number; last_error: string | null; updated_at: string }[]
  webhooks: { id: number; event_type: string | null; attempts: number; last_error: string | null; received_at: string }[]
  notifications: { id: string; event: string; recipient_role: string; delivery_error: string | null; created_at: string }[]
}
type Admin = { id: string; email: string; role: Me['role']; totp_enabled: boolean; last_login_at: string | null }

const ago = (iso: string) => formatDistanceToNowStrict(new Date(iso), { addSuffix: true })

export default function System() {
  const qc = useQueryClient()
  const { can, me } = useMe()
  const [msg, setMsg] = useState<string | null>(null)
  const letters = useQuery<Letters>({ queryKey: ['admin-dead-letters'], queryFn: () => api.get('/admin/system/dead-letters') })
  const admins = useQuery<Admin[]>({ queryKey: ['admin-admins'], queryFn: () => api.get('/admin/admins'), enabled: can('admins.manage') })

  async function run(path: string, ok: string) {
    setMsg(null)
    try {
      await api.post(path, {})
      setMsg(ok)
    } catch (e) {
      setMsg((e as Error).message)
    }
    qc.invalidateQueries({ queryKey: ['admin-dead-letters'] })
  }

  const [pending, setPending] = useState<Record<string, { role: string; reason: string }>>({})

  async function saveRole(a: Admin) {
    const p = pending[a.id]
    if (!p) return
    try {
      await api.post(`/admin/admins/${a.id}/role`, { role: p.role, reason: p.reason.trim() })
      setPending(({ [a.id]: _, ...rest }) => rest)
      qc.invalidateQueries({ queryKey: ['admin-admins'] })
    } catch (e) {
      setMsg((e as Error).message)
    }
  }

  const d = letters.data
  return (
    <div>
      <PageHeader title="System" description="Work that stopped retrying, and admin roles." />
      <PageBody>
        {msg && <p className="text-sm">{msg}</p>}
        {letters.isLoading && <ListSkeleton rows={3} />}
        {letters.isError && <ErrorState what="dead letters" error={letters.error} />}
        {d && (
          <>
            <Section title="Dead jobs" hint="Out of attempts. Retrying runs the job again from scratch.">
              {d.jobs.length === 0 ? <EmptyState icon={Server} title="None" /> : (
                <div className="space-y-2">{d.jobs.map(j => (
                  <Card key={j.id}><CardContent className="flex flex-wrap items-center gap-2 p-3 text-sm">
                    <MetaChip mono>{j.kind}</MetaChip><span className="text-muted-foreground">{j.attempts} attempts · {ago(j.updated_at)}</span>
                    <span className="min-w-0 flex-1 truncate text-xs text-destructive">{j.last_error}</span>
                    {can('system.retry') && <Button size="sm" onClick={() => run(`/admin/system/jobs/${j.id}/retry`, 'Job queued again')}>Retry</Button>}
                  </CardContent></Card>
                ))}</div>
              )}
            </Section>
            <Section title="Failed webhooks" hint="Received but never processed. Processing is idempotent.">
              {d.webhooks.length === 0 ? <EmptyState icon={Server} title="None" /> : (
                <div className="space-y-2">{d.webhooks.map(w => (
                  <Card key={w.id}><CardContent className="flex flex-wrap items-center gap-2 p-3 text-sm">
                    <MetaChip mono>{w.event_type ?? 'event'}</MetaChip><span className="text-muted-foreground">{w.attempts} attempts · {ago(w.received_at)}</span>
                    <span className="min-w-0 flex-1 truncate text-xs text-destructive">{w.last_error}</span>
                    {can('system.retry') && <Button size="sm" onClick={() => run(`/admin/system/webhooks/${w.id}/retry`, 'Processed')}>Process again</Button>}
                  </CardContent></Card>
                ))}</div>
              )}
            </Section>
            <Section title="Pushes not delivered (7 days)" hint="The in-app notice still shows.">
              {d.notifications.length === 0 ? <EmptyState icon={Server} title="None" /> : (
                <div className="space-y-1 text-sm">{d.notifications.map(n => (
                  <p key={n.id}><MetaChip mono>{n.event}</MetaChip> to a {n.recipient_role} · {ago(n.created_at)} · <span className="text-muted-foreground">{n.delivery_error}</span></p>
                ))}</div>
              )}
            </Section>
          </>
        )}
        {can('admins.manage') && (
          <Section title="Admins" hint="A new role applies at the admin's next sign-in.">
            <div className="space-y-2">{(admins.data ?? []).map(a => (
              <Card key={a.id}><CardContent className="flex flex-wrap items-center gap-2 p-3 text-sm">
                <span className="font-medium">{a.email}</span>
                <span className="text-xs text-muted-foreground">{a.last_login_at ? `signed in ${ago(a.last_login_at)}` : 'never signed in'}{a.totp_enabled ? '' : ' · 2FA not set up'}</span>
                <select className="ml-auto rounded-md border bg-background px-2 py-1 text-sm"
                  value={pending[a.id]?.role ?? a.role} disabled={a.email === me?.email}
                  onChange={e => setPending(p => ({ ...p, [a.id]: { role: e.target.value, reason: p[a.id]?.reason ?? '' } }))}>
                  {(['support', 'ops_lead', 'finance', 'admin'] as const).map(r => <option key={r} value={r}>{ROLE_LABEL[r]}</option>)}
                </select>
                {pending[a.id] && pending[a.id].role !== a.role && (
                  <div className="flex w-full gap-2">
                    <input className="flex-1 rounded-md border bg-background px-2 py-1 text-sm" placeholder="Why (recorded)"
                      value={pending[a.id].reason}
                      onChange={e => setPending(p => ({ ...p, [a.id]: { ...p[a.id], reason: e.target.value } }))} />
                    <Button size="sm" disabled={pending[a.id].reason.trim().length < 5} onClick={() => saveRole(a)}>Save</Button>
                  </div>
                )}
              </CardContent></Card>
            ))}</div>
          </Section>
        )}
      </PageBody>
    </div>
  )
}
