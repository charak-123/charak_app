import { useQuery } from '@tanstack/react-query'
import { api } from '@/lib/api'

/**
 * Who is signed in and what their role allows (GET /admin/me). The console
 * hides what the role can't do; the API refuses it regardless
 * (backend services/admin_roles.py).
 */
export type Me = { email: string | null; role: 'support' | 'ops_lead' | 'finance' | 'admin'; permissions: string[] }

export function useMe() {
  const q = useQuery<Me>({ queryKey: ['admin-me'], queryFn: () => api.get<Me>('/admin/me'), staleTime: 5 * 60_000 })
  const perms = new Set(q.data?.permissions ?? [])
  return { me: q.data, loading: q.isLoading, can: (p: string) => perms.has(p) }
}

export const ROLE_LABEL: Record<Me['role'], string> = {
  support: 'Support', ops_lead: 'Ops lead', finance: 'Finance', admin: 'Admin',
}
