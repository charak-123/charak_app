import { mockRequest } from '@/lib/mock'
import { clearToken } from '@/lib/auth'

const BASE = import.meta.env.VITE_API_URL ?? 'http://localhost:8000'

/** Dev flag: serve fixtures instead of calling the backend. See lib/mock.ts. */
const MOCK = import.meta.env.VITE_MOCK === '1'

function token() { return localStorage.getItem('charak_admin_token') ?? '' }

async function req<T>(path: string, opts: RequestInit = {}): Promise<T> {
  if (MOCK) {
    const body = opts.body ? JSON.parse(opts.body as string) : undefined
    return mockRequest(path, opts.method ?? 'GET', body) as Promise<T>
  }
  const res = await fetch(`${BASE}${path}`, {
    ...opts,
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token()}`,
      ...opts.headers,
    },
  })
  if (res.status === 401) {
    // The token expired or was rotated out from under us (JWT_SECRET
    // changed). Every subsequent request would fail the same way, so clear
    // the stale token and send the admin back to /login instead of leaving
    // the dashboard stuck on silent request failures.
    clearToken()
    if (!window.location.pathname.startsWith('/login')) {
      window.location.href = '/login'
    }
    throw new Error('Your session has expired. Please sign in again.')
  }
  if (!res.ok) {
    const err = await res.json().catch(() => ({ error: res.statusText }))
    throw new Error(err.error ?? res.statusText)
  }
  return res.json()
}

export const api = {
  get:    <T>(path: string)              => req<T>(path),
  post:   <T>(path: string, body: unknown) => req<T>(path, { method: 'POST',  body: JSON.stringify(body) }),
  patch:  <T>(path: string, body: unknown) => req<T>(path, { method: 'PATCH', body: JSON.stringify(body) }),
  delete: <T>(path: string)              => req<T>(path, { method: 'DELETE' }),
}
