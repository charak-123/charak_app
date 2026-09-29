import { mockRequest } from '@/lib/mock'

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
